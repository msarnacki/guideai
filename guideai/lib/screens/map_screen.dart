import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/war_place.dart';
import '../services/overpass_service.dart';

class MapScreen extends StatefulWidget {
  final LatLng startPoint;
  final LatLng? endPoint;

  const MapScreen({super.key, required this.startPoint, this.endPoint});

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
      final places = await fetchWarPlaces(widget.startPoint, endPoint: widget.endPoint);
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

  // ── Markery miejsc historycznych (czerwone) ───────────────────────────────
  List<Marker> get _placeMarkers => _places
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

  // ── Marker punktu startowego (zielony) ───────────────────────────────────
  Marker get _startMarker => Marker(
        point: widget.startPoint,
        width: 44,
        height: 52,
        child: Column(
          children: const [
            Icon(Icons.place, color: Colors.green, size: 40),
            SizedBox(height: 2),
          ],
        ),
      );

  // ── Marker punktu końcowego (niebieski) ──────────────────────────────────
  Marker? get _endMarker => widget.endPoint == null
      ? null
      : Marker(
          point: widget.endPoint!,
          width: 44,
          height: 52,
          child: Column(
            children: const [
              Icon(Icons.place, color: Colors.blue, size: 40),
              SizedBox(height: 2),
            ],
          ),
        );

  // ── Oblicz centrum widoku ─────────────────────────────────────────────────
  LatLng get _mapCenter {
    if (widget.endPoint == null) return widget.startPoint;
    return LatLng(
      (widget.startPoint.latitude + widget.endPoint!.latitude) / 2,
      (widget.startPoint.longitude + widget.endPoint!.longitude) / 2,
    );
  }

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
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.guideai',
              ),
              MarkerLayer(markers: [
                ..._placeMarkers,
                _startMarker,
                if (_endMarker != null) _endMarker!,
              ]),
            ],
          ),

          // Legenda
          Positioned(
            bottom: 16,
            left: 16,
            child: Material(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _legendItem(Icons.place, Colors.green, 'Start'),
                    if (widget.endPoint != null)
                      _legendItem(Icons.place, Colors.blue, 'Koniec'),
                    _legendItem(Icons.location_on, Colors.red, 'Miejsce historyczne'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(IconData icon, Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
