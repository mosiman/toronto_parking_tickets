# essentially tix.jl without comments, made to run all in one go.



using Pkg
Pkg.activate(".")
using CSV
using Plots
using DataFrames
using HTTP
using JSON
using Distributed

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


df = CSV.read("small_data.csv")
df = df[.!map(ismissing, df[:location2]),:]
df = df[ [!(ismissing(x)) for x in df.location2], : ]

allstreetsegs = allStreetSegments(df)

open("small_streetsegs.json", "w") do f
    write(f,JSON.json(allstreetsegs))
end

