import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/war_place.dart';
import '../services/overpass_service.dart';

class MapScreen extends StatefulWidget {
  final LatLng startPoint;

  const MapScreen({super.key, required this.startPoint});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<WarPlace> _places = [];
  bool _loading = true;
  String _status = 'Pobieranie danych...';

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    try {
      final places = await fetchWarPlaces(widget.startPoint);
      setState(() {
        _places = places;
        _loading = false;
        _status = 'Znaleziono ${places.length} miejsc';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'Błąd: $e';
      });
    }
  }

  void _showPlaceDialog(String name) {
    showDialog(
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
    );
  }

  List<Marker> get _markers => _places
      .map(
        (place) => Marker(
          point: place.position,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showPlaceDialog(place.name),
            child: const Icon(Icons.location_on, color: Colors.red, size: 36),
          ),
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Szukam miejsc...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_status)),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: widget.startPoint,
          initialZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.guideai',
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
    );
  }
}
