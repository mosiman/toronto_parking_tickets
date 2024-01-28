We're starting from scratch!

## TODO

- May as well package libpostal + nominatim in a docker-compose file

## Why a libpostal docker image, and not the python bindings?

As a result of my insistence on using Nix the package manager and my refusal to actually learn how it works, I gave up after trying to install `pypostal` through `poetry` (which is already a concession, to be clear).

I'm in no rush, so interfacing with libpostal through a very old (6 years at the time of writing!) docker image is just fine.

```
docker run -it -p 8080:8080 clicksend/libpostal-rest
```

## Data

The data is obtained from the [Toronto Open Data Portal](https://open.toronto.ca/dataset/parking-tickets/)
Since the raw data is actually quite small, I'll include it in the repository at `data/parking-tickets-2022.csv`.

The README for the data is in xls format, so I've included the relevant information here:

| Column Name             | Description                                            |
|-------------------------|--------------------------------------------------------|
| TAG_NUMBER_MASKED       | First three (3) characters masked with asterisks       |
| DATE_OF_INFRACTION      | Date the infraction occurred in YYYYMMDD format       |
| INFRACTION_CODE         | Applicable Infraction code (numeric)                   |
| INFRACTION_DESCRIPTION  | Short description of the infraction                    |
| SET_FINE_AMOUNT         | Amount of set fine applicable (in dollars)             |
| TIME_OF_INFRACTION      | Time the infraction occurred in HHMM format (24-hr clock) |
| LOCATION1               | Code to denote proximity (see table below)             |
| LOCATION2               | Street address                                         |
| LOCATION3               | Code to denote proximity (optional)                    |
| LOCATION4               | Street address (optional)                              |
| PROVINCE                | Province or state code of vehicle licence plate        |

The proximity code (LOCATION1) is additional information about the location of the infraction in relation to the address (LOCATION2). Similar for (LOCATION3) and (LOCATION4), I assume.

| Proximity Code | Description |
|----------------|-------------|
| AT             | At          |
| NR             | Near        |
| OPP            | Opposite     |
| R/O            | Rear of      |
| N/S            | North Side   |
| S/S            | South Side   |
| E/S            | East Side    |
| W/S            | West Side    |
| N/O            | North of     |
| S/O            | South of     |
| E/O            | East of      |
| W/O            | West of      |

We may be able to leverage this. We'll see. The intersection-type tickets make up a substantial portion of the total tickets issued (a little over 20%)

```
D select (select (count(*)) * 1.0 from tickets where location1 in ('NR', 'AT', 'OPP')) / (select count(*) from tickets) as perc_exact_address;
┌────────────────────┐
│ perc_exact_address │
│       double       │
├────────────────────┤
│ 0.7947161377187498 │
└────────────────────┘
```

### Data pipeline.

The first step is to extract the `csv` files from the raw zip file. We then use duckdb to load the data into a database.

```sql
select * from read_csv('Parking_Tags_Data_2022.*.csv', delim=',', header = true, quote='"', auto_detect=true, filename=true);
```

To process this in the way we want, we're going to need to do some cleaning and transformation of the location columns. In particular, we want to extract the coordinates of the infraction. 

Converting from an address name (e.g. 233 COLERIDGE AVE) to a pair of coordinates is called geocoding.

En lieu of expensive hosted geocoding services, we'll self host our own. But before this, we should try to normalize the addresses as much as possible. We can do this with `libpostal`

#### Normalizing locations with libpostal


#### Geocoding with Nominatim

I was going to try Pelias, but the single docker container for Nominatim is just too easy.

Running the `./start.sh` script in the `nominatim` directory should get nominatim all set up. After downloading the pbg file for Toronto (thanks bbbike.org!), it took a little over 5 minutes.

Once you see `Nominatim is ready to accept requests`, we're good to go! E.g.

```
❯ time curl 'http://localhost:8080/search.php?q=convocation%20hall'
[{"place_id":579324,"licence":"Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright","osm_type":"way","osm_id":330718925,"boundingbox":["43.6605236","43.6610283","-79.3957883","-79.3951072"],"lat":"43.66077185","lon":"-79.3954329541008","display_name":"Convocation Hall, 31, King's College Circle, Discovery District, University—Rosedale, Old Toronto, Toronto, M5S 1A1, Canada","place_rank":30,"category":"place","type":"house","importance":0.20000999999999997}]
real	0m0.047s
user	0m0.004s
sys	0m0.001s
```

Unforunately, it can't do intersections -- this will be a problem, as many locations are actually specified via intersections. We may have to actually learn about how it works at the database level. We'll consult the [documentation](https://nominatim.org/release-docs/latest/develop/Database-Layout/)

Find all OSM "ways" that have "elm" in the name. These filters seem to give you actual roads, but sometimes also trails (e.g. cycleways).
```
select * from place where class = 'highway' and osm_type = 'W' and name['name'] ilike '%elm%';
```

We can get the way nodes via the ID

```
select * from planet_osm_ways where id = 9509939;
```

And I'm sure we can do something with the nodes?
```
nominatim> select * from planet_osm_nodes where id = 73217886;
+----------+-----------+------------+
| id       | lat       | lon        |
|----------+-----------+------------|
| 73217886 | 437035405 | -795146125 |
+----------+-----------+------------+
```

So we can construct lines from the nodes in a way. For an intersection, perhaps we find ways that intersect? (unless ways "end" at intersections and are "open" intervals. But most likely they are closed if it is based on nodes).

We don't have to literally draw lines, hopefully. According to [this answer](https://help.openstreetmap.org/questions/9344/how-to-detect-intersection-of-ways), ways that intersect _should_ have an intersection node.

> If two streets intersect and neither of them is a bridge or tunnel, then they should have an intersection node; editors and validators will complain if they haven't.

Example: University Ave and Queen St W

I'm hoping libpostal will correct that to
- University Avenue
- Queen Street West


```sql

-- ~0.1s to run

WITH university_ways as (
    select
        p.osm_id,
        p.name,
        w.nodes,
        w.tags
    from place p
    left join planet_osm_ways w
        on w.id = p.osm_id
    where p.class = 'highway' and p.osm_type = 'W' and p.name['name'] = 'University Avenue'
), queen_ways as (
    select
        p.osm_id,
        p.name,
        w.nodes,
        w.tags
    from place p
    left join planet_osm_ways w
        on w.id = p.osm_id
    where p.class = 'highway' and p.osm_type = 'W' and p.name['name'] = 'Queen Street West'
), intersection as (
    select
        u.osm_id as u_osm_id,
        u.name as u_name,
        u.nodes as u_nodes,
        u.tags as u_tags,
        q.osm_id as q_osm_id,
        q.name as q_name,
        q.nodes as q_nodes,
        q.tags as q_tags
    from university_ways u
    join queen_ways q
        on u.nodes && q.nodes
)
select * from intersection
;

-- Calculating intersection using the geometries is slower than joining to ways and intersecting the nodes.
-- ~ 0.3s

WITH university_geom as (
    select
        p.osm_id,
        p.name,
        p.geometry
    from place p
    where p.class = 'highway' and p.osm_type = 'W' and p.name['name'] = 'University Avenue'
), queen_geom as (
    select
        p.osm_id,
        p.name,
        p.geometry
    from place p
    where p.class = 'highway' and p.osm_type = 'W' and p.name['name'] = 'Queen Street West'
), intersection as (
    select
        u.osm_id as u_osm_id,
        u.name as u_name,
        q.osm_id as q_osm_id,
        q.name as q_name
    from university_geom u
    join queen_geom q
        on st_intersects(u.geometry, q.geometry)
)
select * from intersection
;

```

Either way you go about it, it actually returns multiple intersection. I'm not really sure why.

```
nominatim> select tags from planet_osm_ways where id in (35565361, 62058056);
+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------->
| tags                                                                                                                                                                                                              >
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------->
| ['cycleway', 'no', 'highway', 'secondary', 'lanes', '1', 'lit', 'yes', 'maxspeed', '40', 'name', 'University Avenue', 'note', '2023-07-07: All but one lane closed off for Metrolinx construction, likely long ter>
| ['cycleway', 'track', 'highway', 'secondary', 'lanes', '3', 'lit', 'yes', 'maxspeed', '40', 'name', 'University Avenue', 'old_ref', '11A', 'oneway', 'yes', 'sidewalk:left', 'no', 'sidewalk:right', 'separate', '>
+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------->
```

Looks like it could be an update of another?

You can plot a way quick and dirty with the OSM browser tool, e.g. [](https://www.openstreetmap.org/way/62058056)

I think we should use `rels` (relations), as they represent a collection of ways as a larger object.

For example:

```
select * from planet_osm_rels where 35565362 = ANY(parts) and (hstore(tags))['type'] = 'street';
```

Get "university avenue" (the street).

Where we had 8 results trying to find the intersection, I think if we try to get the rel, we should only get one result (with type = street)

```

WITH university_ways as (
    select
        p.osm_id,
        p.name,
        w.nodes
    from place p
    left join planet_osm_ways w
        on w.id = p.osm_id
    where p.class = 'highway' and p.osm_type = 'W' and p.name['name'] = 'University Avenue'
), queen_ways as (
    select
        p.osm_id,
        p.name,
        w.nodes
    from place p
    left join planet_osm_ways w
        on w.id = p.osm_id
    where p.class = 'highway' and p.osm_type = 'W' and p.name['name'] = 'Queen Street West'
), intersection as (
    select
        u.osm_id as u_osm_id,
        u.name as u_name,
        u.nodes as u_nodes,
        q.osm_id as q_osm_id,
        q.name as q_name,
        q.nodes as q_nodes
    from university_ways u
    join queen_ways q
        on u.nodes && q.nodes
), rels as (
    select
        array[i.u_osm_id, i.q_osm_id] as intersection_ways,
        r.id as rel_id,
        r.tags
    from intersection i
    left join planet_osm_rels r
        on array[i.u_osm_id, i.q_osm_id] && parts
    where (hstore(r.tags))['type'] = 'street'
)
select * from rels
;


```

Ultimately, rels are way too big [](https://www.openstreetmap.org/relation/13415306#map=14/43.6571/-79.3613) 

We chose a hard example. University is two streets (one northbound, one southbound), and Queen is one long-ass street. It intersects the west side of university at two places, and the east side of university at two places.

See: ![this image I'm totally going to get]()

to avoid spending too much here, I'll make an executive decision: We'll assign it any one of the ways. Maybe, the longest way (I think there are postGIS functions, like ST_Length on geometries) or way with the most number of points (the easy way).



Edge case: `R/O`
means "rear of". Usually points to an exact address:
```
select count(*) from tickets_cleaned where location1 = 'R/O' and location3 is not null; -- 56
select count(*) from tickets_cleaned where location1 = 'R/O'; -- 5959
```
We'll treat `R/O` as an exact address, and if there is also a location3 proximity code (intersection?) then we'll ignore those rows.


We'll also ignore this case (neither location is a "primary street"):
```
 select * from tickets_intersection where location1 not in ('N/S', 'S/S', 'E/S', 'W/S') and location3 not in ('N/S', 'S/S', 'E/S', 'W/S'); -- 2020
D select count(*) from tickets_intersection;
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│       158173 │
└──────────────┘
D select 2020.0 / 158173;
┌──────────────────────┐
│  (2020.0 / 158173)   │
│        double        │
├──────────────────────┤
│ 0.012770826879429485 │
└──────────────────────┘
```
