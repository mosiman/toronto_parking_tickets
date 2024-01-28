import duckdb
import pandas as pd
import psycopg
import requests
import time
from tqdm import tqdm

tqdm.pandas()

LIBPOSTAL_URL="http://localhost:8081"
MAX_LIBPOSTAL_RETRIES=5

# A function to query libpostal-rest
def query_libpostal_rest(address):
    """
    Queries libpostal-rest for a given address and returns the response.
    """

    if address is None:
        return None

    # Construct the URL
    url = f"{LIBPOSTAL_URL}/expand"

    payload = {"query": address}

    retry_counter = 0

    try:
        # POST to the url with the payload
        response = requests.post(url, json=payload)
    except:
        # If we get an error, retry up to MAX_LIBPOSTAL_RETRIES times
        while retry_counter < MAX_LIBPOSTAL_RETRIES:
            try:
                response = requests.post(url, json=payload)
                break
            except:
                retry_counter += 1
                # sleep for a second
                time.sleep(1)

    # Return the response
    expanded_options = response.json()

    # if there are no expanded options, return None. Otherwise, return the first result.
    if len(expanded_options) == 0:
        return None
    return expanded_options[0]


# A function to query Nominatim for a given address
def query_nominatim(address):
    """
    Queries Nominatim for a given address and returns the response.
    """
    # Construct the URL
    url = "http://localhost:8080/search"

    payload = {"q": address, "format": "json"}

    # GET to the url with the payload
    response = requests.get(url, params=payload)
    # Return the response

    # if there are no results for the query, return None. Otherwise, return the first result.
    if len(response.json()) == 0:
        return None
    return response.json()[0]


# Open a duckdb connection to data/untracked/parking-tickets-2022.db
con = duckdb.connect(database="data/untracked/parking-tickets-2022.db")

# Show the first 5 rows of the tickets table
print(con.execute("SELECT * FROM tickets LIMIT 5").fetchdf())

#   tag_number_masked  date_of_infraction  infraction_code          infraction_description  ...  location3 location4 province                                  filename
# 0          ***73863            20220101               29  PARK PROHIBITED TIME NO PERMIT  ...       None      None       ON  untracked/Parking_Tags_Data_2022.000.csv
# 1          ***46942            20220101               15  PARK-WITHIN 3M OF FIRE HYDRANT  ...       None      None       ON  untracked/Parking_Tags_Data_2022.000.csv
# 2          ***73864            20220101               29  PARK PROHIBITED TIME NO PERMIT  ...       None      None       MA  untracked/Parking_Tags_Data_2022.000.csv
# 3          ***63914            20220101                9  STOP-SIGNED HWY-PROHIBIT TM/DY  ...       None      None       ON  untracked/Parking_Tags_Data_2022.000.csv
# 4          ***73865            20220101               29  PARK PROHIBITED TIME NO PERMIT  ...       None      None       ON  untracked/Parking_Tags_Data_2022.000.csv

tickets_df = con.execute("SELECT * FROM tickets order by random()").fetchdf()

# Run the value of location2 and location4 through libpostal into new columns, location2_clean and location4_clean
# This can take some time.
# Parallelizing might work if the libpostal-rest server is multithreaded. But let's keep it simple for now.
tickets_df["location2_clean"] = tickets_df["location2"].progress_apply(query_libpostal_rest)
tickets_df["location4_clean"] = tickets_df["location4"].progress_apply(query_libpostal_rest)

# It doesn't always work so well. For example, `DE GRASSI ST` -> `de grassi saint`. But I think that's something  we can live with.


# Create a new table, tickets_cleaned, with the cleaned data from tickets_df
con.register("tickets_df", tickets_df)
con.execute("DROP TABLE IF EXISTS tickets_cleaned")
con.execute("""
CREATE TABLE tickets_cleaned AS
SELECT
    *
FROM tickets_df
""")
