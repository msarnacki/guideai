import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'pick_location_screen.dart';
import 'map_screen.dart';

class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  // Punkt startowy
  LatLng? _startPoint;
  bool _loadingStartLocation = false;
  String? _startLabel;

  // Punkt końcowy
  LatLng? _endPoint;
  bool _loadingEndLocation = false;
  String? _endLabel;

  // Dystans (placeholder)
  double _distanceKm = 5.0;

  // ── GPS: pobierz aktualną lokalizację ──────────────────────────────────────
  Future<LatLng?> _getGpsLocation() async {
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

    final pos = await location.getLocation();
    return LatLng(pos.latitude!, pos.longitude!);
  }

  String _coordLabel(LatLng point) =>
      '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';

  // ── Punkt startowy: GPS ────────────────────────────────────────────────────
  Future<void> _useMyLocationAsStart() async {
    setState(() => _loadingStartLocation = true);
    try {
      final pos = await _getGpsLocation();
      setState(() {
        _startPoint = pos;
        _startLabel = 'Twoja lokalizacja (${_coordLabel(pos!)})';
        _loadingStartLocation = false;
      });
    } catch (e) {
      setState(() => _loadingStartLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e')));
      }
    }
  }

  // ── Punkt startowy: mapa ───────────────────────────────────────────────────
  Future<void> _pickStartFromMap() async {
    final center = _startPoint ?? const LatLng(52.2297, 21.0122);
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(
          initialCenter: center,
          title: 'Wybierz punkt startowy',
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _startPoint = result;
        _startLabel = 'Z mapy (${_coordLabel(result)})';
      });
    }
  }

  // ── Punkt końcowy: GPS ─────────────────────────────────────────────────────
  Future<void> _useMyLocationAsEnd() async {
    setState(() => _loadingEndLocation = true);
    try {
      final pos = await _getGpsLocation();
      setState(() {
        _endPoint = pos;
        _endLabel = 'Twoja lokalizacja (${_coordLabel(pos!)})';
        _loadingEndLocation = false;
      });
    } catch (e) {
      setState(() => _loadingEndLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e')));
      }
    }
  }

  // ── Punkt końcowy: mapa ────────────────────────────────────────────────────
  Future<void> _pickEndFromMap() async {
    final center = _endPoint ?? _startPoint ?? const LatLng(52.2297, 21.0122);
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(
          initialCenter: center,
          title: 'Wybierz punkt końcowy',
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _endPoint = result;
        _endLabel = 'Z mapy (${_coordLabel(result)})';
      });
    }
  }

  // ── Generuj ────────────────────────────────────────────────────────────────
  void _onGenerate() {
    if (_startPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz punkt startowy')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          startPoint: _startPoint!,
          endPoint: _endPoint,
          targetDistanceMeters: _distanceKm * 1000,
        ),
      ),
    );
  }

  // ── Pomocnicze widgety ─────────────────────────────────────────────────────
  Widget _selectedPointInfo(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.green, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );

  Widget _locationButtons({
    required bool loading,
    required VoidCallback onGps,
    required VoidCallback onMap,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: loading ? null : onGps,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: const Text('Moja lokalizacja'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onMap,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Wybierz z mapy'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guided Walk')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Punkt startowy ──────────────────────────────────────────────
            _sectionTitle('Punkt startowy'),
            const SizedBox(height: 12),
            _locationButtons(
              loading: _loadingStartLocation,
              onGps: _useMyLocationAsStart,
              onMap: _pickStartFromMap,
            ),
            if (_startLabel != null) _selectedPointInfo(_startLabel!),

            const SizedBox(height: 28),

            // ── Punkt końcowy ───────────────────────────────────────────────
            _sectionTitle('Punkt końcowy'),
            const SizedBox(height: 4),
            const Text(
              'Opcjonalny — wymagany do planowania trasy przez miejsca',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _locationButtons(
              loading: _loadingEndLocation,
              onGps: _useMyLocationAsEnd,
              onMap: _pickEndFromMap,
            ),
            if (_endLabel != null) _selectedPointInfo(_endLabel!),

            const SizedBox(height: 28),

            // ── Dystans ─────────────────────────────────────────────────────
            _sectionTitle('Dystans spaceru'),
            const SizedBox(height: 4),
            const Text(
              'Używany gdy wybrano punkt startowy i końcowy',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('1 km', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Expanded(
                  child: Slider(
                    value: _distanceKm,
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '${_distanceKm.round()} km',
                    onChanged: (v) => setState(() => _distanceKm = v),
                  ),
                ),
                const Text('20 km', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            Center(
              child: Text(
                '${_distanceKm.round()} km',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),

            const Spacer(),

            // ── Przycisk Generuj ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startPoint != null ? _onGenerate : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Generuj trasę', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
