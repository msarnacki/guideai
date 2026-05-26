import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: MapScreen());
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final double radiusKm = 2.0;

  LatLng? gpsPosition;
  List<Marker> markers = [];
  bool loading = true;
  String status = 'Pobieranie lokalizacji...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final pos = await _getCurrentLocation();
      setState(() {
        gpsPosition = LatLng(pos.latitude!, pos.longitude!);
        status = 'Pobieranie danych...';
      });
      await fetchWarPlaces();
    } catch (e) {
      setState(() {
        loading = false;
        status = 'Błąd lokalizacji: $e';
      });
    }
  }

  Future<LocationData> _getCurrentLocation() async {
    final location = Location();

    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) throw Exception('Usługi lokalizacji wyłączone');
    }

    PermissionStatus permission = await location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await location.requestPermission();
      if (permission != PermissionStatus.granted) {
        throw Exception('Brak uprawnień do lokalizacji');
      }
    }

    return await location.getLocation();
  }

  Future<void> fetchWarPlaces() async {
    if (gpsPosition == null) return;

    final lat = gpsPosition!.latitude;
    final lon = gpsPosition!.longitude;

    final query = '''
[out:json][timeout:25];
node["historic"="memorial"](around:1000,$lat,$lon);
out 5;
''';

    try {
      final encoded = Uri.encodeComponent(query);
      final url = 'https://overpass-api.de/api/interpreter?data=$encoded';
      print('>>> Wysyłam request do: $lat, $lon');

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'GuideAI/1.0 (test@test.com)'},
      );

      print('>>> Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        final newMarkers = <Marker>[];
        for (final el in elements) {
          double? elLat, elLon;
          if (el['type'] == 'node') {
            elLat = el['lat']?.toDouble();
            elLon = el['lon']?.toDouble();
          } else if (el['center'] != null) {
            elLat = el['center']['lat']?.toDouble();
            elLon = el['center']['lon']?.toDouble();
          }
          if (elLat == null || elLon == null) continue;

          final name = el['tags']?['name'] ?? el['tags']?['historic'] ?? 'Brak nazwy';

          newMarkers.add(Marker(
            point: LatLng(elLat, elLon),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Miejsce'),
                  content: Text(name),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: const Icon(Icons.location_on, color: Colors.red, size: 36),
            ),
          ));
        }

        setState(() {
          markers = newMarkers;
          loading = false;
          status = 'Znaleziono ${markers.length} miejsc';
        });
      } else {
        setState(() {
          loading = false;
          status = 'Błąd HTTP: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
        status = 'Błąd: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (gpsPosition == null) {
      return Scaffold(
        appBar: AppBar(title: Text(status)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(status)),
      body: FlutterMap(
        options: MapOptions(initialCenter: gpsPosition!, initialZoom: 14),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.guideai',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}