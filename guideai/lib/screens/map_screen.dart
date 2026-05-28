import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/planner_result.dart';
import '../models/route_result.dart';
import '../models/interest_point.dart';
import '../services/overpass_service.dart';
import '../services/route_planner.dart';
import '../services/routing_service.dart';

class MapScreen extends StatefulWidget {
  final LatLng startPoint;
  final LatLng? endPoint;
  final double targetDistanceMeters;

  const MapScreen({
    super.key,
    required this.startPoint,
    this.endPoint,
    this.targetDistanceMeters = 5000,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<InterestPoint> _places = [];
  RouteResult? _route;
  bool _loading = true;
  String _loadingMessage = 'Szukam ciekawych miejsc...';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      // Krok 1: pobierz kandydatów z Overpass
      final candidates = await fetchInterestPoints(
        widget.startPoint,
        endPoint: widget.endPoint,
      );

      if (widget.endPoint != null) {
        // Krok 2: planuj trasę przez wybrane miejsca
        setState(() => _loadingMessage =
            'Planuję trasę przez ${candidates.length} kandydatów...');

        final PlannerResult result = await planRoute(
          start: widget.startPoint,
          end: widget.endPoint!,
          candidates: candidates,
          targetMeters: widget.targetDistanceMeters,
        );

        setState(() {
          _places = result.selectedPlaces;
          _route = result.route;
          _loading = false;
          _status =
              '${_places.length} miejsc · ${_route!.distanceLabel} · ${_route!.durationLabel}';
        });
      } else {
        // Tylko start — pokaż wszystkie miejsca bez trasy
        setState(() {
          _places = candidates;
          _route = null;
          _loading = false;
          _status = 'Znaleziono ${candidates.length} miejsc';
        });
      }
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

  // ── Markery ───────────────────────────────────────────────────────────────

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

  Marker get _startMarker => Marker(
        point: widget.startPoint,
        width: 44,
        height: 52,
        child: const Column(
          children: [
            Icon(Icons.place, color: Colors.green, size: 40),
            SizedBox(height: 2),
          ],
        ),
      );

  Marker? get _endMarker => widget.endPoint == null
      ? null
      : Marker(
          point: widget.endPoint!,
          width: 44,
          height: 52,
          child: const Column(
            children: [
              Icon(Icons.place, color: Colors.blue, size: 40),
              SizedBox(height: 2),
            ],
          ),
        );

  // ── Centrum widoku ────────────────────────────────────────────────────────

  LatLng get _mapCenter {
    if (widget.endPoint == null) return widget.startPoint;
    return LatLng(
      (widget.startPoint.latitude + widget.endPoint!.latitude) / 2,
      (widget.startPoint.longitude + widget.endPoint!.longitude) / 2,
    );
  }

  // ── Widgety pomocnicze ────────────────────────────────────────────────────

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

  Widget _routeInfoItem(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.blueAccent),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generuję trasę...')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                _loadingMessage,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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

              // Trasa (pod markerami)
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      color: Colors.blueAccent,
                      strokeWidth: 4.5,
                    ),
                  ],
                ),

              MarkerLayer(markers: [
                ..._placeMarkers,
                _startMarker,
                if (_endMarker != null) _endMarker!,
              ]),
            ],
          ),

          // Panel z informacjami o trasie
          if (_route != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withOpacity(0.93),
                elevation: 2,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _routeInfoItem(
                          Icons.straighten, _route!.distanceLabel, 'dystans'),
                      const VerticalDivider(width: 24, thickness: 1),
                      _routeInfoItem(Icons.directions_walk,
                          _route!.durationLabel, 'szac. czas'),
                      const VerticalDivider(width: 24, thickness: 1),
                      _routeInfoItem(Icons.location_on,
                          '${_places.length}', 'miejsc'),
                    ],
                  ),
                ),
              ),
            ),

          // Legenda
          Positioned(
            bottom: 16,
            left: 16,
            child: Material(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _legendItem(Icons.place, Colors.green, 'Start'),
                    if (widget.endPoint != null)
                      _legendItem(Icons.place, Colors.blue, 'Koniec'),
                    _legendItem(
                        Icons.location_on, Colors.red, 'Punkt zainteresowania'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
