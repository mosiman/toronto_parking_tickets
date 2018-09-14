

struct InfractionNode
    date::Int
    code::Int
    fine::Int
    time::Int
    loc::String
end

mutable struct StreetSegment
    name::String
    osm_id::String
    boundingBox::Array{Float64}
    infraction_nodes::Array{InfractionNode}
end

# We have a dictionary of StreetSegments (key is osm_id), so 
# we make a custom merge function dispatched to StreetSegment dicts.

import Base.merge!

function merge!(d::Dict{String, StreetSegment},
                others::Dict{String, StreetSegment})
    for other in others
        k = other.first
        v = other.second
        if haskey(d, k)
            # concatenate infraction_nodes
            d[k].infraction_nodes = vcat(d[k].infraction_nodes,
                                         v.infraction_nodes)
        else
            d[k] = v
        end
    end
    return d
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
                                    map(x -> parse(Float64, x), q_way["boundingbox"]),
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

function make_db(i)
    db = SQLite.DB(string("streetsegdb_", i))
    SQLite.query(db,
                 "create table if not exists streetsegments(
                    osm_id int primary key,
                    name text,
                    slat real,
                    nlat real,
                    wlng real,
                    elng real)")
    SQLite.query(db,
                 "create table if not exists streetsegmentinfraction(
                    osm_id int,
                    date int,
                    code int,
                    fine int,
                    time int,
                    loc text)")
    return db
end

function amongst(num, workers)
    quotient = Int(floor(num / workers))
    rs = push!([(quotient*x + 1):(quotient*(x+1)) for x in 0:workers-2],
               (quotient*(workers-1)+1):num)
    return rs
end

function addToDB(df,db)
    # println(string("worker: ", Threads.threadid()))
    for j in 1:size(df)[1]
        row = df[j,:]
        try
            #SQLite.execute!(db, "BEGIN TRANSACTION")
            qstring = row.location2[1] * ", Toronto"
            q_way = getStreetSegment(qstring)
            qquery = nominatim_query(qstring)
            qresponse = nominatim_response(qquery)
            infnode = InfractionNode(row.date_of_infraction[1],
                                     row.infraction_code[1],
                                     row.set_fine_amount[1],
                                     row.time_of_infraction[1],
                                     row.location2[1])
            if isempty(SQLite.query(db, "select * from streetsegments where osm_id=:osmid",
                                     values = Dict(:osmid => q_way["osm_id"])))
                SQLite.query(db, "insert into streetsegments values (:osmid, :name, :slat, :nlat, :wlng, :elng)",
                             values = Dict(:osmid => q_way["osm_id"],
                                           :name => q_way["display_name"],
                                           :slat => parse(Float64, q_way["boundingbox"][1]),
                                           :nlat => parse(Float64, q_way["boundingbox"][2]),
                                           :wlng => parse(Float64, q_way["boundingbox"][3]),
                                           :elng => parse(Float64, q_way["boundingbox"][4])
                                          ))
            end
            SQLite.query(db, "insert into streetsegmentinfraction values (:osmid, :date, :code, :fine, :time, :loc)", 
                         values = Dict(:osmid => q_way["osm_id"],
                                       :date => row.date_of_infraction[1],
                                       :code => row.infraction_code[1],
                                       :fine => row.set_fine_amount[1],
                                       :time => row.time_of_infraction[1],
                                       :loc => row.location2[1]
                                      ))
            #SQLite.execute!(db, "END TRANSACTION")
        catch err
            # probably going to be an error where nominatim can't find the query
            println(string(err, "at: ", j))
        end
    end
end
function addToDB(row, db_procs, j)
    db = db_procs[Threads.threadid()]
    # println(string("worker: ", Threads.threadid()))
    try
        println("starto")
        #SQLite.execute!(db, "BEGIN TRANSACTION")
        qstring = row.location2[1] * ", Toronto"
        q_way = getStreetSegment(qstring)
        qquery = nominatim_query(qstring)
        qresponse = nominatim_response(qquery)
        infnode = InfractionNode(row.date_of_infraction[1],
                                 row.infraction_code[1],
                                 row.set_fine_amount[1],
                                 row.time_of_infraction[1],
                                 row.location2[1])
        println("before check")
        if isempty(SQLite.query(db, sr"select * from streetsegments where osm_id=:osmid",
                                 values = Dict(:osmid => q_way["osm_id"])))
            SQLite.query(db, sr"insert into streetsegments values (:osmid, :name, :slat, :nlat, :wlng, :elng)",
                         values = Dict(:osmid => q_way["osm_id"],
                                       :name => q_way["display_name"],
                                       :slat => parse(Float64, q_way["boundingbox"][1]),
                                       :nlat => parse(Float64, q_way["boundingbox"][2]),
                                       :wlng => parse(Float64, q_way["boundingbox"][3]),
                                       :elng => parse(Float64, q_way["boundingbox"][4])
                                      ))
        end
        println("after check")
        SQLite.query(db, sr"insert into streetsegmentinfraction values (:osmid, :date, :code, :fine, :time, :loc)", 
                     values = Dict(:osmid => q_way["osm_id"],
                                   :date => row.date_of_infraction[1],
                                   :code => row.infraction_code[1],
                                   :fine => row.set_fine_amount[1],
                                   :time => row.time_of_infraction[1],
                                   :loc => row.location2[1]
                                  ))
        #SQLite.execute!(db, "END TRANSACTION")
    catch err
        # probably going to be an error where nominatim can't find the query
        println(string(err, "at: ", j))
    end
end

function multiSS2sqlite(df)
    # make a vector of databases to accThreads.nthreads())
                        
    @everywhere db_procs = map(make_db, 1:Threads.nthreads())

    # helper function
    # warning: mutable!! mutates thedict

    ranges = amongst(size(df)[1], Threads.nthreads())

    streetsegs = @sync [@async addToDB(df[ranges[x], :], db_procs[x]) for x in 1:Threads.nthreads()]

    return streetsegs
end

function multiSS2(df)
    # helper function
    # warning: mutable!! mutates thedict
    @everywhere listStreetSegments = Dict{String, StreetSegment}()
    function addToDict(row, thedict, j)
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
                                    map(x -> parse(Float64, x), q_way["boundingbox"]),
                                    [infnode])
                thedict[q_way["osm_id"]] = seg
            end
        catch err
            # probably going to be an error where nominatim can't find the query
            println(err)
            print("at: ")
            println(j)
        end
    end

    
    @sync for j in 1:size(df)[1]
        @spawn addToDict(df[j,:], listStreetSegments, j)
    end

    return listStreetSegments
end

function multiStreetSegments(df)

    function amongst(num, workers)
        quotient = Int(floor(num / workers))
        rs = push!([(quotient*x + 1):(quotient*(x+1)) for x in 0:workers-2],
                   (quotient*(workers-1)+1):num)
        return rs
    end

    ranges = amongst(size(df)[1], nprocs())

    streetsegs = @sync [@spawn allStreetSegments(df[x, :]) for x in ranges]
     
    return foldl(merge!,[fetch(x) for x in streetsegs])
end

