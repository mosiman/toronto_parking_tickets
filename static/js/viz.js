
$(document).ready(function() {

	var mymap = L.map('mapid').setView([43.653908, -79.384293], 13);
	L.tileLayer('http://dev.mosiman.ca:8080/styles/klokantech-basic/{z}/{x}/{y}.png', {
		attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
		maxZoom: 18,
		id: 'mapbox.streets',
		accessToken: 'your.mapbox.access.token'
	}).addTo(mymap); 

	var polygon = L.polygon([
							[43.6606658,-79.3748618],
							[43.6606658,-79.3722203],
							[43.6612191,-79.3722203],
							[43.6612191,-79.3748618]
							]).addTo(mymap);

    var georgeSt = L.polygon([
                            [43.6555838, -79.3734656],
                            [43.6555838, -79.3727395],
                            [43.6572936, -79.3727395],
                            [43.6572936, -79.3734656]
                            ]).addTo(mymap);
                            

	var popup = L.popup()


	function onMapClick(e){
		// This is going to be the workhorse function, probably.
		popup.setLatLng(e.latlng).setContent("Clicked map at: " + e.latlng.toString()).openOn(mymap)
        $.ajax({
            url: "http://dev.mosiman.ca:8888/ajaxMapClick", 
            data: {lat: e.latlng.lat, lng: e.latlng.lng},
            type: 'POST',
            success: function(data) {
                console.log(data.result)
            }})

	}

	mymap.on('click', onMapClick);

	$("#ajaxButton").click( function() {
		console.log("clickeddd")
        $.ajax({
            url: "http://dev.mosiman.ca:8888/ajaxTest", 
            data: {somenum: 8},
            type: 'POST',
            success: function(data) {
                console.log(data.result)
            }})
	})


})
