#!/usr/bin/env bash

# A simple data processing pipeline.

# First, unzip the contents of raw/parking-tickets-2022.zip into untracked/
unzip raw/parking-tickets-2022.zip -d untracked/

duckdb -c "create table tickets as (select * from read_csv('untracked/Parking_Tags_Data_2022.*.csv', delim=',', header = true, quote='"'"'"', auto_detect=true, filename=true))" untracked/parking-tickets-2022.db
