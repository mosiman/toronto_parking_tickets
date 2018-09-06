# essentially tix.jl without comments, made to run all in one go.

using Distributed
println("Threads: " * string(Threads.nthreads()))

addprocs(15)

println("Procs: " * string(length(procs())))

println("loading library")
@everywhere include("parking_viz_library.jl")
println("library loaded")

@everywhere using Pkg
@everywhere Pkg.activate(".")
@everywhere using CSV
@everywhere using DataFrames
@everywhere using HTTP
@everywhere using JSON
@everywhere using Distributed

println("Loaded packages and functions")

println("Loading df")
df = CSV.read("all_2016.csv")
df = df[.!map(ismissing, df[:location2]),:]
df = df[ [!(ismissing(x)) for x in df.location2], : ]
println("df successfully loaded")

dfsize = 0
if isempty(ARGS)
    println("Args: None")
    println("Using the whole dataframe")
    dfsize = size(df)[1]
else
    print("Args: ")
    println(ARGS)
    dfsize = parse(Int, ARGS[1])
    print("df size to use: ")
    println(parse(Int, ARGS[1]))
end


println("making dfsmall")

dfsmall = df[1:dfsize, :]

println("dfsmall made")

println("Computing Street Segments")

allstreetsegs = multiSS2(dfsmall)

println("Done computing street segments")

println("writing to JSON")

open("all_streetsegs.json", "w") do f
    write(f,JSON.json(allstreetsegs))
end

println("All done!")

