

# Some commands cause I can't get the notebooks to work well right now

using Pkg
Pkg.activate(".")
using CSV
using Plots
using DataFrames

df = CSV.read("Parking_Tags_Data_2016_1.csv")

# addresses are in df.location2
# some addresses are missing, let's filter them out.
# originally has 750000 rows

df = df[.!map(ismissing, df[:location2]),:]

# now has 749875 rows
# The Query package isn't updated
# basically .! vectorises negation of map(ismissing, df[:sdfas])
# which is a vector of elements not missing.


# now I need to get lat/long coordinates to plot with plotly. But before that, let's look at some data.

# A street near and dear (not) to my wallet: Elm street

elms = unique([x for x in df.location2 if occursin(r"\d+ ELM ST", x)])

# example: at 41 elm street, there are 105 infractions
# df[df[:locations2] .== elms[1], :]

# the Elm street between bay and yonge is essentially 1 Elm to 41 Elm.

elm_bay_yonge = [x for x in elms if parse(Int,split(x)[1]) <= 41]

df_EBY = df[map(x -> x in elm_bay_yonge, df[:location2]), :]

# now let's get the data for infractions in january 2 (jan1 is a holiday)

# I'm not sure how data is collected, but if this is just raw cop input, then
# how is it possible to have missing values???? out of 2399 elements, 

# nevermind, looks like theyre all non missing, the data type is just wack.
# 32 infractions on this street. What is the distribution like?

df_EBY_jan2 = df_EBY[df_EBY[:date_of_infraction] .== 20160102, :]

using Plots

histogram(df_EBY_jan2[:time_of_infraction], bins=23)

# what about for all dates on this street?

# holy balls theres actually a missing value, how do you even print that ticket wtf

df_EBY = df_EBY[ [!ismissing(x) for x in df_EBY.time_of_infraction], :]

histogram(df_EBY[:time_of_infraction], bins=23)

# well it isn't all that surprising, I guess. 
# Time of infraction is kinda normal, with mean around
# 5:30pm (visual)
# this is only for the winter, though. Looks like the dates only go
# until march 29. 

# Need a way of binning addresses together, so I don't have to manually do this

# K means clustering? once I have a nominatin server set up and geolocate all these street names (addr -> lat/long)
# would want to use taxicab or similar metric with emphasis on
# north/south , etc

# split into street names (like elms)
# find "continuous" strand (how?)
# each continuous strand is an interactive point 


# Turns out that from an address, Nominatim will give you the
# "street" as a "Way" type: basically a path of nodes. 
# I will group addresses based on the Way that Nominatim gives me
# Then, Leaflet.js looks like it can plot arbitrary polygons, polylines, etc. Make a polyline with the nodes on the Way, and plot! Can be interactive (has popups). 


# nominatim API: Examples:
# get location in JSON http://localhost:7070/search/?format=json&q=1209+Queen+Street+East,+Toronto&addressdetails=1
# Using the osm_id, we can search to get more info
# http://localhost:7070/lookup?osm_ids=N804614415 [[ the N is for "node" ]]
# What we really want is the Way ID that contains the node

# We can try to search the street name
# http://localhost:7070/search/?format=xml&q=Queen+Street+East,+Toronto&limit=1000

# looks like I need to research the overpass API
# There seems to be an updated docker container https://hub.docker.com/r/wiktorn/overpass-api/

# 1209 Queen St E lat/long is 43.6628783/-79.3313065 (from above API search query)
# nominatim reverse with zoom at 16:
# http://localhost:7070/reverse?format=xml&lat=43.6628783&lon=-79.3313065&zoom=16
# this has the correct way osm_id [W]551976979!
# zoom at 16 gives us a the street level.
# Seems kinda wasteful, but whatever
# We can even output the bounding box to use with leaflet.js


