# Behind the Scenes: A beginner's experience with Julia, data visualization, and multithreading (Part 1)

Bear with me, this is going to be my first technical blog post. I'm hoping that this provides a somewhat realistic datapoint concerning what it's like to try and wrangle data for the first time. 

My language of choice for doing the data wrangling is [Julia](https://julialang.org), which had recently just released its version 1.0. Being a 1.0 release, this was certainly exciting and I thought it would be the perfect time to try it out (I was wrong). 

The first thing you have to do is get data. I'll be trying to take a stab at Toronto's parking ticket data for 2016 (and potentially previous years), graciously provided by [Toronto Open Data](https://www.toronto.ca/city-government/data-research-maps/open-data/open-data-catalogue/transportation/#75d14c24-3b7e-f344-4412-d8fd41f89455). I say graciously, because I have come to expect little from this city, but as public information, this should rightfully be available to everybody. 

The data comes as 4 different CSV files, roughly split by season, because of its large size. In total, there 2254762 tickets logged for the year of 2016 alone. 

Firing up Julia with the `CSV.jl` and `DataFrames.jl` packages, we can load the entire file into a dataframe. For testing purposes, I only started out by using a subset of the entire data.

```{Julia}

julia>using Pkg
julia>Pkg.activate(".") # New package manager in Julia 1.0 is quite nice! 
julia>                  # I've always wanted a virtualenv-esque thing for Julia.
julia>using CSV
julia>using DataFrames
julia>
julia>df = CSV.read("tickets1.csv")

2499×11 DataFrame. Omitted printing of 8 columns
│ Row  │ tag_number_masked │ date_of_infraction │ infraction_code │
├──────┼───────────────────┼────────────────────┼─────────────────┤
│ 1    │ ***03850          │ 20160101           │ 29              │
│ 2    │ ***03851          │ 20160101           │ 29              │
│ 3    │ ***98221          │ 20160101           │ 29              │
│ 4    │ ***85499          │ 20160101           │ 29              │
│ 5    │ ***03852          │ 20160101           │ 406             │
│ 6    │ ***16117          │ 20160101           │ 3               │
│ 7    │ ***03853          │ 20160101           │ 29              │
│ 8    │ ***03854          │ 20160101           │ 29              │
│ 9    │ ***03855          │ 20160101           │ 406             │
│ 10   │ ***03856          │ 20160101           │ 29              │
│ 11   │ ***12254          │ 20160101           │ 3               │
│ 12   │ ***98222          │ 20160101           │ 29              │
│ 13   │ ***27500          │ 20160101           │ 29              │
│ 14   │ ***98223          │ 20160101           │ 29              │
│ 15   │ ***27501          │ 20160101           │ 29              │
│ 16   │ ***98224          │ 20160101           │ 29              │
│ 17   │ ***03857          │ 20160101           │ 29              │
│ 18   │ ***27502          │ 20160101           │ 29              │
│ 19   │ ***98225          │ 20160101           │ 29              │
│ 20   │ ***03858          │ 20160101           │ 29              │
⋮
│ 2479 │ ***26318          │ 20160102           │ 28              │
│ 2480 │ ***32011          │ 20160102           │ 29              │
│ 2481 │ ***03998          │ 20160102           │ 28              │
│ 2482 │ ***15452          │ 20160102           │ 29              │
│ 2483 │ ***53766          │ 20160102           │ 28              │
│ 2484 │ ***53767          │ 20160102           │ 28              │
│ 2485 │ ***63389          │ 20160102           │ 29              │
│ 2486 │ ***03999          │ 20160102           │ 28              │
│ 2487 │ ***16365          │ 20160102           │ 3               │
│ 2488 │ ***20307          │ 20160102           │ 29              │
│ 2489 │ ***16366          │ 20160102           │ 3               │
│ 2490 │ ***05135          │ 20160102           │ 336             │
│ 2491 │ ***61963          │ 20160102           │ 406             │
│ 2492 │ ***36598          │ 20160102           │ 28              │
│ 2493 │ ***20308          │ 20160102           │ 29              │
│ 2494 │ ***20751          │ 20160102           │ 28              │
│ 2495 │ ***53768          │ 20160102           │ 28              │
│ 2496 │ ***53769          │ 20160102           │ 28              │
│ 2497 │ ***16367          │ 20160102           │ 3               │
│ 2498 │ ***15453          │ 20160102           │ 29              │
│ 2499 │ ***28796          │ 20160102           │ 29              │

```

What I'm most interested at this point is the location data, because I was really excited to try out some spatial visualization javascript libraries. I settled on [Leaflet.js](https://leafletjs.com) for its supposed simplicity. 

There are actually four location columns, for different uses. The Open Data page containing the data says more about it. I am interested in `location2`.

```{Julia}

julia> df.location2
2499-element Array{Union{Missing, String},1}:
 "49 GLOUCESTER ST" 
 "45 GLOUCESTER ST" 
 "274 GEORGE ST"    
 "270 GEORGE ST"    
 "45 GLOUCESTER ST" 
 "621 KING ST W"    
 "43 GLOUCESTER ST" 
 "39 GLOUCESTER ST" 
 "39 GLOUCESTER ST" 
 ⋮                  
 "EASTERN AVE"      
 "216 OLIVE AVE"    
 "15 LESTER AVE"    
 "25 LEITH HILL RD" 
 "DALEMOUNT AVE"    
 "DALEMOUNT AVE"    
 "3045 FINCH AV W"  
 "43 EARLSCOURT AVE"
 "28 EDMUND AVE"    

```

You'll notice that right off the bat that these addresses are not precise at all. For example, Eastern avenue is a very long busy arterial road. Not to mention that different 'boroughs' of Toronto have streets with the same name. Furthermore, take a look at the type of the array `2499-element Array{Union{Missing, String},1}`. For those who don't know Julia, this is an array containing `String` types and `Missing` types, whose dimensionality is `1` (a column vector). How can there even be missing types? This actually boggles me, because I feel like the location of an infraction is actually a critical piece of information. Nevertheless, we must cleanse it of this nonsense.

```{Julia}

julia> df = df[ [!(ismissing(x)) for x in df.location2], : ] 
2498×11 DataFrame. Omitted printing of 8 columns
│ Row  │ tag_number_masked │ date_of_infraction │ infraction_code │
├──────┼───────────────────┼────────────────────┼─────────────────┤
│ 1    │ ***03850          │ 20160101           │ 29              │
│ 2    │ ***03851          │ 20160101           │ 29              │
│ 3    │ ***98221          │ 20160101           │ 29              │
│ 4    │ ***85499          │ 20160101           │ 29              │
│ 5    │ ***03852          │ 20160101           │ 406             │
│ 6    │ ***16117          │ 20160101           │ 3               │
│ 7    │ ***03853          │ 20160101           │ 29              │
│ 8    │ ***03854          │ 20160101           │ 29              │
⋮
│ 2490 │ ***61963          │ 20160102           │ 406             │
│ 2491 │ ***36598          │ 20160102           │ 28              │
│ 2492 │ ***20308          │ 20160102           │ 29              │
│ 2493 │ ***20751          │ 20160102           │ 28              │
│ 2494 │ ***53768          │ 20160102           │ 28              │
│ 2495 │ ***53769          │ 20160102           │ 28              │
│ 2496 │ ***16367          │ 20160102           │ 3               │
│ 2497 │ ***15453          │ 20160102           │ 29              │
│ 2498 │ ***28796          │ 20160102           │ 29              │

```

Julia, like Python, has these awesome [list comprehensions](https://en.wikipedia.org/wiki/List_comprehension) that allow us to construct new lists from old with very mathematical notation. In this case, `[ !(ismissing(x)) for x in df.location2 ]` creates a vector with elements true or false corresponding to elements in the dataframe for which `location2` is not missing.  We then subset the dataframe with this list in order to extract rows that do not contain missing `location2` elements.

It's great that I have this mildly clean data, but I'm not interested in specific addresses, like in the data. I'm more interested in clusters of addresses. I.e., street segments. For example, I'd like to find a way to list all the parking tickets that were issued on Elm street between Yonge and Bay. 

Initially, I had considered typical clustering algorithms, like `k`-means clustering. But I would have to define a special metric that gave emphasis to points along the same axis, not to even mention the parts of Toronto that aren't gridlike! 

I was very lucky to find that an Open Street Map software, [Nominatim](http://nominatim.org/), was available free to install, or free to use for a limited number of API calls a month. I opted for now to install my own server, but this had its own problems (perhaps, a separate post). In hindsight, the right move would be to use the [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API), which is more focused on querying data rather than modifying it. 

Nevertheless, with Nominatim, I'm able to (in a very convoluted way) get the "way" that an address lies on. A Way is a structure that houses multiple nodes. To do this, I first geocode the address, find it's latitude and longitude, and then *reverse* geocode the latitude and longitude at a specific zoom level to find the street. It works, but I have to admit that I don't much like the solution either. 

```{Julia}

using HTTP
using JSON

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
    q *= "zoom=16"                                      # "street" level
    return q
end

function nominatim_response(nom_query,reverse=false)
    req = HTTP.request("GET", nom_query)
    reqjson = JSON.parse(String(req.body))
    if reverse==true
        return reqjson
    else
        try                         # slightly different formats in search vs reverse
            return reqjson[1]
        catch
            return reqjson
        end
    end
end 

# Package it up into a function

function getStreetSegment(qstring)
    nom_query = nominatim_query(qstring)
    qstring_req = nominatim_response(nom_query)
    # reverse geolocate with 
    lat = qstring_req["lat"]
    lon = qstring_req["lon"]
    reversereq = nominatim_response(nominatim_reverse(lat,lon), true)
    return reversereq
end

```

Now all that's left to do is package it all up into a database! Easy, right? Sort of. Here are some numbers:

- Retrieving a single street segment with a local Nominatim server (not even an external server) took about `0.17s`. 
- Retrieving 10 street segments takes about `1.7s`
- Retrieving 100 street segments takes about `177s`
- Given that there are well over `2,000,000` entries, this would take a whopping 94 hours if it continues to scale linearly (which is likely an underestimation). 

Since the Nominatim server seemingly had no trouble accepting multiple concurrent connections, I figured the best way to go would be to parallelize this. This is my first shot at parallelizing an operation, and luckily it seemed to be straightforward with Julia.

```{Julia}

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

```

This was also my first go at using a database. As you can see, I've commented out the areas where I tried to speed up sqlite operations by wrapping it inside one transaction (instead of multiple), but then we get into concurrent transactions and all that hairy stuff, which I decided I would forego for the sake of finishing *something* (at this point, I was quite frustrated with the whole matter). 

Also, you can see that I've wrapped everything in a try/catch block. This is because an error is thrown if the server can't find the address you're looking for. For example, if `ALESSIA CIRCLE` is used, Nominatim finds it just fine. But if `ALESSIA CIRC` is used instead, it doesn't find it and something breaks along the way. 

For the time being, any address not found by Nominatim is ignored, but a large part of this missing data is because of uncommon abbreviations, and I hope to clean the data further in my next iteration of this analysis.

I think it's a fair point to cut off the analysis here, as I've got the data I need. The next part will go over the front end / back end interaction between Leaflet.js and my Django server.
