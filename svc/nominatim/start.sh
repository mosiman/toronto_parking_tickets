podman run -it --shm-size=1g \
  -e PBF_URL=https://download.bbbike.org/osm/bbbike/Toronto/Toronto.osm.pbf \
  -e IMPORT_WIKIPEDIA=false \
  -e NOMINATIM_PASSWORD=very_secure_password \
  -e IMPORT_STYLE=address \
  -v nominatim-data:/var/lib/postgresql/14/main \
  -p 8080:8080 \
  -p 5432:5432 \
  mediagis/nominatim:4.3
