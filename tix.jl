# ===============================================
# NOTES FOR DATA VISUALIZATION AND ANALYSIS
# OF TORONTO PARKING TICKET DATA
# ===============================================

# in shell, should do
# export JULIA_NUM_THREADS=4
# to set 4 threads
# also, i think need to @everywhere include("tix.jl")



# Some commands cause I can't get the notebooks to work well right now

using Pkg
Pkg.activate(".")
using CSV
using Plots
using DataFrames
using HTTP
using JSON
using Distributed

df = CSV.read("small_data.csv")

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

# Have "Way" objects. Each Way is POD (export to json) and has the info
# - average infractions per day
# - Number of each type of infraction
# - Most common infraction type / cost
# - 3 hour window with the highest average infraction (weekend vs weekday?)
# - List of nodes in dataframe corresponding to the segment.

struct InfractionNode
    date::Int
    code::Int
    fine::Int
    time::Int
    loc::String
end

struct StreetSegment
    name::String
    osm_id::String
    boundingBox::Array{Any}
    infraction_nodes::Array{InfractionNode}
end


function nominatim_query(qstring)
    q = "http://localhost:7070/search/?format=json&q="
    for word in split(qstring)
        q *= word * "+"
    end
    return q[1:end-1]
end

function nominatim_reverse(lat,lon,zoom=16)
    q = "http://localhost:7070/reverse?format=json&"
    q *= "lat=" * lat * "&"
    q *= "lon=" * lon * "&"
    q *= "zoom=16"
    return q
end

    
function nominatim_response(nom_query,reverse=false)
    req = HTTP.request("GET", nom_query)
    reqjson = JSON.parse(String(req.body))
    if reverse==true
        return reqjson
    else
        try
            return reqjson[1]
        catch
            return reqjson
        end
    end
end 

function getStreetSegment(qstring)
    nom_query = nominatim_query(qstring)
    qstring_req = nominatim_response(nom_query)
    # reverse geolocate with 
    lat = qstring_req["lat"]
    lon = qstring_req["lon"]
    reversereq = nominatim_response(nominatim_reverse(lat,lon), true)
    return reversereq
end

# generate random ways:
getStreetSegment(df.location2[rand(1:1000)] * ", Toronto")

# clear missings

df = df[ [!(ismissing(x)) for x in df.location2], : ]


# naiive implementation, probably need to specialize later 
# so checking containment is more like O(1). Hash map maybe?


# ArgumentError("Invalid index: lat of type String")
# error at: 90, 93, 95, 98, 103, .. , 1269, 1578, ...
# This happens when nominatim doesn't find a match for the address. 
# Example: ALESSIA CRCL confuses nominatim but ALESSIA CIRCLE is okay.
# TODO: address sanitizer

# @time allStreetSegmentsOld(df[1:100,:]) ~~~~ roughly 17 seconds
# @time allStreetSegmentsOld(df[1:100,:]) ~~~~ roughly 177 seconds
function allStreetSegmentsOld(df)
    # make sure df has no missings, etc
    listStreetSegments = []
    for i in 1:size(df)[1]
        try
            qstring = df[i,:].location2[1] * ", Toronto"
            q_way = getStreetSegment(qstring)
            qquery = nominatim_query(qstring)
            qresponse = nominatim_response(qquery)
            foundWay = false
            for seg in listStreetSegments
                if seg.osm_id == q_way["osm_id"]
                    foundWay = true
                    # add this node
                    push!(seg.infraction_nodes,
                          qresponse["osm_id"])
                end
            end
            if !foundWay
                # new StreetSegment
                seg = StreetSegment(q_way["display_name"],
                                    q_way["osm_id"],
                                    q_way["boundingbox"],
                                    [qresponse["osm_id"]])
                push!(listStreetSegments, seg)
            end
        catch err
            print("ERROR: ")
            println(err)
            print("error at: ")
            println(i)
        end
    end
    return listStreetSegments
end


# @time allStreetSegments(df[1:100, :]) ~~~~ roughly 17 seconds
# @time allStreetSegments(df[1:1000, :]) ~~~~ roughly 175 seconds
# profiling:
# @time allStreetSegments(df[1:10, :]) ~~~ roughly 1.7, 1.8 seconds
# getStreetSegment ~~~ 0.126
# nominatim_response ~~~ 0.07
# minifunc is qstring, q_way, qquery, qresponse
# @time minifunc(df[1:10, :]) ~~~ 1.7 seconds. 
# Conclude: Most of the time is taken by querying the nominatim API
#           especially the reverse geocoding portion.

function allStreetSegments(df)
    # make sure df has no missings, etc
    listStreetSegments = Dict{String, StreetSegment}()
    for i in 1:size(df)[1]
        try
            qstring = df[i,:].location2[1] * ", Toronto"
            q_way = getStreetSegment(qstring)
            qquery = nominatim_query(qstring)
            qresponse = nominatim_response(qquery)
            infnode = InfractionNode(df[i,:].date_of_infraction[1],
                                     df[i,:].infraction_code[1],
                                     df[i,:].set_fine_amount[1],
                                     df[i,:].time_of_infraction[1],
                                     df[i,:].location2[1])
            if haskey(listStreetSegments, q_way["osm_id"])
                push!(listStreetSegments[q_way["osm_id"]].infraction_nodes,
                      infnode)
            else
                seg = StreetSegment(q_way["display_name"],
                                    q_way["osm_id"],
                                    q_way["boundingbox"],
                                    [infnode])
                listStreetSegments[q_way["osm_id"]] = seg
            end
        catch err
            # probably going to be an error where nominatim can't find the query
            print("ERROR: ")
            println(err)
            print("error at: ")
            println(i)
        end
    end
    return listStreetSegments
end

# this is pretty slow still. But if we start with multiple processes, we can speed up. 
# example:
# function test()
#   r1 = remotecall(allStreetSegments, 2, df[1:50, :])
#   r2 = remotecall(allStreetSegments, 2, df[51:100, :])
#   f1 = fetch(r1)
#   f2 = fetch(r2)
#   return f1,f2
# end
# ===============================
# This runs in 8.44 seconds (compare with ~17 seconds single threaded)
# Running the test splitting 1000 into 1:333, 334:666, 667:1000 it takes ~60.9 seconds!!!
# This should reduce the approximate 3 hour runthrough into 1 hour, but we still need to merge the results
# TODO: think of merging algorithm

function multiStreetSegments(df)
    # hardcode to 5 procs, and 749874 entries
    r1 = remotecall(allStreetSegments, 2, df[1:187468,:])
    r2 = remotecall(allStreetSegments, 3, df[187469:374936,:])
    r3 = remotecall(allStreetSegments, 4, df[374937:562404,:])
    r4 = remotecall(allStreetSegments, 5, df[562405:749875,:])
    
    f1 = fetch(r1)
    f2 = fetch(r2)
    f3 = fetch(r3)
    f4 = fetch(r4)
    return f1,f2,f3, f4
end



function multiSS2(df)
    # helper function
    # warning: mutable!! mutates thedict
    listStreetSegments = Dict{String, StreetSegment}()
    function addToDict(row, thedict)
        try
            qstring = row.location2[1] * ", Toronto"
            q_way = getStreetSegment(qstring)
            qquery = nominatim_query(qstring)
            qresponse = nominatim_response(qquery)
            infnode = InfractionNode(row.date_of_infraction[1],
                                     row.infraction_code[1],
                                     row.set_fine_amount[1],
                                     row.time_of_infraction[1],
                                     row.location2[1])
            if haskey(thedict, q_way["osm_id"])
                push!(thedict[q_way["osm_id"]].infraction_nodes,
                      infnode)
            else
                seg = StreetSegment(q_way["display_name"],
                                    q_way["osm_id"],
                                    q_way["boundingbox"],
                                    [infnode])
                thedict[q_way["osm_id"]] = seg
            end
        catch err
            # probably going to be an error where nominatim can't find the query
            println(err)
        end
    end
    

    @sync for i in 1:size(df)[1]
        @spawn addToDict(df[i,:], listStreetSegments)
    end

    return listStreetSegments
end



function allStreetSegmentsThreaded(df)
    # make sure df has no missings, etc
    listStreetSegments = Dict{String, StreetSegment}()
    Threads.@threads for i in 1:size(df)[1]
        try
            qstring = df[i,:].location2[1] * ", Toronto"
            q_way = getStreetSegment(qstring)
            qquery = nominatim_query(qstring)
            qresponse = nominatim_response(qquery)
            infnode = InfractionNode(df[i,:].date_of_infraction[1],
                                     df[i,:].infraction_code[1],
                                     df[i,:].set_fine_amount[1],
                                     df[i,:].time_of_infraction[1],
                                     df[i,:].location2[1])
            if haskey(listStreetSegments, q_way["osm_id"])
                push!(listStreetSegments[q_way["osm_id"]].infraction_nodes,
                      infnode)
            else
                seg = StreetSegment(q_way["display_name"],
                                    q_way["osm_id"],
                                    q_way["boundingbox"],
                                    [infnode])
                listStreetSegments[q_way["osm_id"]] = seg
            end
        catch err
            # probably going to be an error where nominatim can't find the query
            print("ERROR: ")
            println(err)
            print("error at: ")
            println(i)
        end
    end
    return listStreetSegments
end


# write to json help: https://gist.github.com/silgon/0ba43e00e0749cdf4f8d244e67cd9d6a






        





# Have "Neighbourhood" objects. Each neighbourhood contains a list of ways
# as wel as the bounding box (how to get?) so that we can plot in Leaflet.


# TODO Still! Can now look at data PER STREET SECTION per day
# Cops come by at random times? How is it distributed? 
# If you leave the car, what is the probability a cop comes by in the next X minutes?
# Follow a typical waiting time distribution?
# QUESTION: Given that parking is maximum 3 hours, and the distribution of cop visits to street, 
#           using the green P app, how can you maximize total parking time?
#           i.e., average wait + 3 hours + average wait
