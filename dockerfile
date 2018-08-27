FROM julia:latest

RUN julia -e 'using Pkg; Pkg.add.(["DataFrames", "CSV", "Plots"])' && \
    julia -e 'using CSV' && \
    julia -e 'using DataFrames' && \
    julia -e 'using Plots'
