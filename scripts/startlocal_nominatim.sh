sudo docker run --restart=always -p 6432:5432 -p 7070:8080 -d -v /home/mosiman/sideproj/toronto_parking_tickets/postgresdata:/var/lib/postgresql/9.5/main nominatim sh /app/start.sh
