import duckdb
import pandas as pd
import psycopg
import requests
import time
import psycopg
import pprint
from tqdm import tqdm

# Hide the warning from pandas "UserWarning: pandas only suppoers SQLAlchemy connectable"
import warnings
warnings.filterwarnings("ignore", category=UserWarning)

tqdm.pandas()

pp = pprint.PrettyPrinter(indent=4)

# Yeah, harcoded connection strings are bad, but this is one-off and I'm lazy.
# Also, everything is confined to my tailnet.
NOMINATIM_URL="http://csclubvm:8080"
NOMINATIM_DB_STR="dbname=nominatim user=nominatim host=csclubvm port=5432 password=very_secure_password"
MAX_NOMINATIM_RETRIES=5

SHITTY_CACHE = {}

# Open a duckdb connection to ../data/untracked/parking-tickets-2022.db
con = duckdb.connect(database="../data/untracked/parking-tickets-2022.db")
nominatim_con = psycopg.connect(NOMINATIM_DB_STR)

# Connect to the nominatim database from duckdb as well
con.execute("install postgres; load postgres; ATTACH 'dbname=nominatim user=nominatim host=csclubvm password=very_secure_password' AS nominatim (TYPE postgres);")

def query_nominatim_search(address):
    """
    Queries Nominatim for a given address and returns the response.
    query_type is one of "search", "reverse"
    """

    if address is None:
        return None

    url = f"{NOMINATIM_URL}/search"
    payload = {"q": address, "format": "json"}
    retry_counter = 0
    try:
        # POST to the url with the payload
        response = requests.get(url, params=payload)
    except:
        # If we get an error, retry up to MAX_NOMINATIM_RETRIES times
        while retry_counter < MAX_NOMINATIM_RETRIES:
            try:
                response = requests.post(url, json=payload)
                break
            except:
                retry_counter += 1
                # sleep for a second
                time.sleep(1)
    # GET to the url with the payload
    response = requests.get(url, params=payload)
    # if there are no results for the query, return None. Otherwise, return the first result.
    if len(response.json()) == 0:
        return None
    return response.json()

# Do a reverse geocode given lat,lon
# 17 is the zoom level for "major and minor streets", just above the maximum zoom level of 18 for buildings.
def query_nominatim_reverse(lat, lon, zoom=17):
    """
    Queries Nominatim for a given address and returns the response.
    query_type is one of "search", "reverse"
    """

    if lat is None or lon is None:
        return None

    # Construct the url
    url = f"{NOMINATIM_URL}/reverse"
    payload = {"lat": lat, "lon": lon, "zoom": zoom, "format": "json"}
    retry_counter = 0
    try:
        # POST to the url with the payload
        response = requests.get(url, params=payload)
    except:
        # If we get an error, retry up to MAX_NOMINATIM_RETRIES times
        while retry_counter < MAX_NOMINATIM_RETRIES:
            try:
                response = requests.post(url, json=payload)
                break
            except:
                retry_counter += 1
                # sleep for a second
                time.sleep(1)
    # GET to the url with the payload
    response = requests.get(url, params=payload)
    # if there are no results for the query, return None. Otherwise, return the first result.
    if len(response.json()) == 0:
        return None
    return response.json()

# We'll use the API for NR / AT / OPP locations.
# Since the API doesn't allow us to locate intersections, we'll hit the database directly for those.

# When using the API, it will return an OSM object (usually a node or way). We want to find the closest way to that object that is a street ("highway" in OSM parlance).

# Problem: e.g. 2850 jane street does not return a street. It returns a building.
# One possible solution is to take the lat/lon of the building and reverse geocode it with a zoom level that skips buildings. E.g. see: https://help.openstreetmap.org/questions/68109/getting-closest-streetroad-given-latitude-longitude-coordinate
# Another solution is to figure how the Nominatim database works. We could avoid having to query the API twice.
# I would actually prefer this, but I think it is a little bit out of scope for this project.

# Some addresses are just not good. E.g.
# - 1364 street clair avenue west (Actually: this one might be because of bad libpostal)
# Some addresses exist according to google maps, but not in OSM. E.g.
# - 55 merchants wharf
# There are just straight up typos? E.g.
# - 121 gpp gore vale avenida
# Let's just take what we can get.
# Also, should we bother caching? ... meh. But that's easy low hanging fruit.
def hydrate_address(row):
    try:
        src_column = "location2_clean"
        addr = row["location2_clean"]
        addr_search = query_nominatim_search(addr)

        if addr_search is None or len(addr_search) == 0:
            # Try again with the "unclean" address -- maybe it was a libpostal error?
            print(f"None returned when searching {addr} -- trying backup name")
            src_column = "location2"
            addr = row["location2"]
            addr_search = query_nominatim_search(addr)
            if addr_search is None or len(addr_search) == 0:
                errmsg = f"None returned when searching {addr} -- giving up"
                errtype = "search_fail"
                return {"errmsg": errmsg, "errtype": errtype}

        # Get the lat/lon out of the first object
        lat = addr_search[0]["lat"]
        lon = addr_search[0]["lon"]

        # Reverse geocode the lat/lon
        addr_reverse = query_nominatim_reverse(lat, lon)

        if 'error' in addr_reverse:
            errmsg = f"Error: {addr_reverse['error']} when reverse geocoding {addr}'s lat/lon ({lat}, {lon})"
            errtype = "reverse_geocode_fail"
            return {"errmsg": errmsg, "errtype": errtype}

        # Get the way from the reverse geocoded
        way = addr_reverse["osm_id"]

        return {'way_id': way, 'src_column': src_column}
    except Exception as e:
        errmsg = f"Error: {e} when hydrating row {row}"
        errtype = "unknown_error"
        return {"errmsg": errmsg, "errtype": errtype}

VALID_PROXIMITY_CODES=[
    "AT",
    "NR",
    "OPP",
    "R/O",
    "N/S",
    "S/S",
    "E/S",
    "W/S",
    "N/O",
    "S/O",
    "E/O",
    "W/O"
]

# # What proportion of tickets contain valid proximity codes in location1?
# # Only 88! I think we'll need to do some cleaning ... 
# con.execute("""
#     SELECT
#         COUNT(*) filter (WHERE location1 in ('AT', 'NR', 'OPP', 'R/O', 'N/S', 'S/S', 'E/S', 'W/S', 'N/O', 'S/O', 'E/O', 'W/O')) as num_valid,
#         COUNT(*) as num_total,
#         num_valid / num_total as proportion_valid
#     from tickets_cleaned
# """).fetchdf()
# 
# # Select distinct location1 from tickets_cleaned where the location1 is not valid
# irregular_codes = list(con.execute("""
#     SELECT DISTINCT location1
#     FROM tickets_cleaned
#     WHERE location1 not in ('AT', 'NR', 'OPP', 'R/O', 'N/S', 'S/S', 'E/S', 'W/S', 'N/O', 'S/O', 'E/O', 'W/O')
# """).fetchdf()['location1'])
# 
# pp.pprint(irregular_codes)

# There are only 127 irregular proximity codes ... I'll do my best to clean them.
# Ok, that's not close to 127 but that's as good as we're gonna get because lazy.

irregular_proximity_code_mapping = { "ACROSS": "OPP",
    "OPPS": "OPP",
    "AT ": "AT",
    "NR N/S": "NR",
    "NEAR E/SOF": "NR",
    'OUT FRONT': "NR",
    "ATR": "AT",
    "EAST  SIDE": "E/S",
    "REAR": "NR",
    "AT REAROF": "NR",
    "NEAR": "NR",
    "LOT/AT": "AT",
    "NR S/SOF": "NR",
    "NEAR/OPP": "OPP",
    "PARKING/LO": "AT",
    "OPPOSITE": "OPP",
    "AT ACCROSS": "OPP",
    "EAST/SIDE": "E/S",
    "ACRSS REAR": "OPP",
    "NEQR": "NR",
    "NR S/SIDE": "NR",
    "NEAR/OPPOS": "OPP",
    "NR ": "NR",
    "AT ACROSS": "OPP",
    "ACROSS FRM": "OPP",
    "ACROSS FR": "OPP",
    "NR S/S": "NR",
    "NR E/OF": "NR",
    "S/S OF": "S/S",
    "N/R": "NR",
    "I/F": "AT",
    "N": "NR",
    "OUT/FRONT": "NR",
    "ACROSS/": "OPP",
    "EAST OF": "E/O"
}

def clean_proxcode(proxcode):
    if proxcode in irregular_proximity_code_mapping:
        return irregular_proximity_code_mapping[proxcode]
    else:
        return proxcode


def get_street_ways(streetname, nominatim_con):
    query = """
        with word_token as (
            select * from word where word_token ilike %s
            order by (info->>'count')::int desc
            limit 1
        ), word_name as (
            select * from search_name where (select word_id from word_token)
                = ANY(name_vector)
        ), word_places as (
            select
                px.place_id,
                px.parent_place_id,
                px.osm_type,
                px.osm_id,
                px.class,
                px.type,
                px.admin_level,
                px.name,
                px.address,
                px.extratags,
                px.geometry
            from placex px
            join word_name wn on
                wn.place_id = px.place_id
            where px.osm_type = 'W'
        ), word_ways as (
            select
                px.*,
                w.nodes,
                w.tags
            from word_places px
            join planet_osm_ways w
                on w.id = px.osm_id
        )
        select 
            *, 
            %s as og_token,
            st_xmax(geometry) as xmax,
            st_xmin(geometry) as xmin,
            st_ymax(geometry) as ymax,
            st_ymin(geometry) as ymin
        from word_ways
        ;
    """
    df = pd.read_sql(query, nominatim_con, params=[streetname, streetname])
    return df


def get_intersecting_ways(row, nominatim_con):
    df_s1 = get_street_ways(row["location2_clean"], nominatim_con)
    if df_s1.empty:
        df_s1 = get_street_ways(row["location2"], nominatim_con)
    df_s2 = get_street_ways(row["location4_clean"], nominatim_con)
    if df_s2.empty:
        df_s2 = get_street_ways(row["location4"], nominatim_con)

    if df_s1.empty or df_s2.empty:
        print(f"Unable to find ways for {row['location2_clean']} and {row['location4_clean']}")
        return None

    query = """
        select
            u.osm_id as u_osm_id,
            u.name as u_name,
            u.nodes as u_nodes,
            u.tags as u_tags,
            u.og_token as u_og_token,
            u.geometry as u_geometry,
            u.xmax as u_xmax,
            u.xmin as u_xmin,
            u.ymax as u_ymax,
            u.ymin as u_ymin,
            q.osm_id as q_osm_id,
            q.name as q_name,
            q.nodes as q_nodes,
            q.tags as q_tags,
            q.og_token as q_og_token,
            q.geometry as q_geometry,
            q.xmax as q_xmax,
            q.xmin as q_xmin,
            q.ymax as q_ymax,
            q.ymin as q_ymin
        from df_s1 u
        join df_s2 q
            on u.nodes && q.nodes
    """
    df = duckdb.sql(query).fetchdf()
    return df


# Some tickets are located by two streets with identifiers like "N/S" (north side) and "W/O" (west of).
# This function tries to find the OSM way that corresponds to this location.
# Good intersections to test:
# - St Clair Avenue West & Spadina Road
# - University Avenue & Elm
# Weird cases
# - St Clair Avenue West & Avenue road (the st clair way goes through the intersection)
# = St Clair Avenune East (N/S) & Yonge Street (E/S) (the way is super duper teeny tiny)
# - Yonge Street (W/S) & The Esplanade (N/O):
#   the esplanade (w: 62207369) is not exactly "horizontal", so its ymax is actually higher 
#   than the intersecting way on yonge street (w: 62207368)
def get_way_from_intersection(row, nominatim_con):
    df_i = get_intersecting_ways(row, nominatim_con)
    if df_i is None:
        errmsg = f"Unable to get ways for street"
        return {"errmsg": errmsg, "errtype": "street_lookup_fail"}
    proxcode_1 = row["location1"]
    proxcode_2 = row["location3"]

    if df_i.shape[0] == 0:
        errmsg = f"No intersecting ways"
        return {"errmsg": errmsg, "errtype": "no_intersecting_ways"}
    else:
        if proxcode_1 in ['N/S', 'S/S', 'E/S', 'W/S']:
            col_prefix_primary = 'u'
            col_prefix_secondary = 'q'
            proxcode_primary = proxcode_1
            proxcode_secondary = proxcode_2
        elif proxcode_2 in ['N/S', 'S/S', 'E/S', 'W/S']:
            col_prefix_primary = 'q'
            col_prefix_secondary = 'u'
            proxcode_primary = proxcode_2
            proxcode_seconday = proxcode_1
        else:
            errmsg = f"Neither location1 {proxcode_1} or location3 {proxcode_2} indicate a primary street."
            return {"errmsg": errmsg, "errtype": "no_primary_street"}

        if df_i.shape[0] == 1:
            return {"way_id": df_i[f"{col_prefix_primary}_osm_id"].iloc[0], "geometry": df_i[f"{col_prefix_primary}_geometry"].iloc[0]}

        # First, cut based on the secondary proximity code.
        # then sort by which side its on via the primary proximity code.
        if proxcode_secondary == 'N/O':
            df_i = duckdb.sql(f"select * from df_i where {col_prefix_primary}_ymax >= {col_prefix_secondary}_ymax").fetchdf()
        elif proxcode_secondary == 'S/O':
            df_i = duckdb.sql(f"select * from df_i where {col_prefix_primary}_ymax <= {col_prefix_secondary}_ymax").fetchdf()
        elif proxcode_secondary == 'E/O':
            df_i = duckdb.sql(f"select * from df_i where {col_prefix_primary}_xmax >= {col_prefix_secondary}_xmax").fetchdf()
        elif proxcode_secondary == 'W/O':
            df_i = duckdb.sql(f"select * from df_i where {col_prefix_primary}_xmax <= {col_prefix_secondary}_xmax").fetchdf()
        else:
            errmsg = f"Unknown proxcode_secondary: {proxcode_secondary}"
            return {"errmsg": errmsg, "errtype": "unknown_proxcode_secondary"}

        # E.g. jones avenue and queen st east. why???
        if df_i.empty:
            errmsg = f"empty dataframe after cutting!"
            return {"errmsg": errmsg, "errtype": "empty_dataframe_after_cut"}

        if proxcode_primary == 'N/S':
            intersecting_row = duckdb.sql(f"select * from df_i order by {col_prefix_primary}_ymax desc limit 1").fetchdf()
        elif proxcode_primary == 'S/S':
            intersecting_row = duckdb.sql(f"select * from df_i order by {col_prefix_primary}_ymax asc limit 1").fetchdf()
        elif proxcode_primary == 'E/S':
            intersecting_row = duckdb.sql(f"select * from df_i order by {col_prefix_primary}_xmax desc limit 1").fetchdf()
        elif proxcode_primary == 'W/S':
            intersecting_row = duckdb.sql(f"select * from df_i order by {col_prefix_primary}_xmax asc limit 1").fetchdf()
        else:
            errmsg = f"Unknown primary proxcode: {proxcode_primary}"
            return {"errmsg": errmsg, "errtype": "unknown_proxcode_primary"}

        intersecting_row = intersecting_row.iloc[0]

        return {"way_id": intersecting_row[f'{col_prefix_primary}_osm_id'], "geometry": intersecting_row[f"{col_prefix_primary}_geometry"]}


def get_ways_for_ticket(row, nominatim_con):
    # unique key on location1, location2, location3, location 4
    # There are ~218K such unique keys, and 1821K total rows, so a cache would speed things up.

    k = (row["location1"], row["location2"], row["location3"], row["location4"])
    if k in SHITTY_CACHE:
        print(f"Cache hit for {k}!")
        return SHITTY_CACHE[k]
    if (row["location1"] in ['NR', 'AT', 'OPP', 'R/O', None]) or (row["location4"] is None):
        v = hydrate_address(row)
    else:
        v = get_way_from_intersection(row, nominatim_con)

    SHITTY_CACHE[k] = v
    return v


def get_geojson_for_way(way_id, nominatim_con):
    query = """
        select
            w.id,
            w.nodes,
            w.tags,
            w.geometry,
            w.xmax,
            w.xmin,
            w.ymax,
            w.ymin
        from planet_osm_ways w
        where w.id = %s
    """
    df = pd.read_sql(query, nominatim_con, params=[way_id])
    return df

print("Loading cleaned tickets into memory dataframe")

# tickets = con.execute("select * from tickets_cleaned").fetchdf()
tickets = con.execute("select * from tickets_cleaned").fetchdf()
# Clean the proxcodes in location1

print("Cleaning proxcodes")
tickets['location1'] = tickets['location1'].apply(clean_proxcode)

print("Getting ways for each ticket")
ways = tickets.progress_apply(lambda x: get_ways_for_ticket(x, nominatim_con), axis=1, result_type = 'expand')

tickets_cleaned_ways = pd.concat([tickets, ways], axis=1)

print("Saving to duckdb")
# Create a parquet file from tickets_cleaned_ways
con.execute("drop table if exists tickets_ways")
con.execute("create table tickets_ways as select * from tickets_cleaned_ways")

print("Getting the geojson for each way")
con.execute("""
    drop table if exists tickets_ways_geometry;
    create table tickets_ways_geometry as
    select
        tw.date_of_infraction,
        tw.infraction_code,
        tw.infraction_description,
        tw.set_fine_amount,
        tw.time_of_infraction,
        tw.location1,
        tw.location2,
        tw.location3,
        tw.location4,
        tw.way_id,
        ST_GeomFromHEXWKB(p.geometry), -- Use ST_AsGeoJSON later?
        p.name
    from tickets_ways tw
    left join nominatim.place p
        on p.osm_id = tw.way_id
        and p.osm_type = 'W'
    ;
""")

print("Done!")
