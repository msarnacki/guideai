import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PickLocationScreen extends StatefulWidget {
  final LatLng initialCenter;
  final String title;

  const PickLocationScreen({
    super.key,
    required this.initialCenter,
    required this.title,
  });

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  LatLng? _picked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_picked != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _picked),
              child: const Text(
                'Potwierdź',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: 13,
              onTap: (_, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.guideai',
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_pin, color: Colors.blue, size: 40),
                    ),
                  ],
                ),
            ],
          ),

          // Wskazówka na górze mapy
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Material(
              borderRadius: BorderRadius.circular(8),
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  _picked == null
                      ? 'Dotknij mapy, aby wybrać lokalizację'
                      : 'Wybrano: ${_picked!.latitude.toStringAsFixed(4)}, '
                          '${_picked!.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),

      floatingActionButton: _picked != null
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, _picked),
              icon: const Icon(Icons.check),
              label: const Text('Potwierdź'),
            )
          : null,
    );
  }
}
