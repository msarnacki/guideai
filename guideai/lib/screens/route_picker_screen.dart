import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

class RouteSelection {
  final LatLng start;
  final String startLabel;
  final LatLng? end;
  final String? endLabel;
  final bool isLoop;

  const RouteSelection({
    required this.start,
    required this.startLabel,
    this.end,
    this.endLabel,
    required this.isLoop,
  });
}

enum _ActivePoint { start, end }

class RoutePickerScreen extends StatefulWidget {
  final LatLng? initialStart;
  final String? initialStartLabel;
  final LatLng? initialEnd;
  final String? initialEndLabel;
  final bool initialLoop;

  const RoutePickerScreen({
    super.key,
    this.initialStart,
    this.initialStartLabel,
    this.initialEnd,
    this.initialEndLabel,
    this.initialLoop = false,
  });

  @override
  State<RoutePickerScreen> createState() => _RoutePickerScreenState();
}

class _RoutePickerScreenState extends State<RoutePickerScreen> {
  LatLng? _start;
  String? _startLabel;
  LatLng? _end;
  String? _endLabel;
  bool _isLoop = false;
  _ActivePoint _active = _ActivePoint.start;

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;
  bool _loadingGps = false;

  static const LatLng _fallback = LatLng(52.2297, 21.0122);

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _startLabel = widget.initialStartLabel;
    _end = widget.initialEnd;
    _endLabel = widget.initialEndLabel;
    _isLoop = widget.initialLoop;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _loadingGps = true);
    try {
      final loc = Location();
      bool svc = await loc.serviceEnabled();
      if (!svc) svc = await loc.requestService();
      if (!svc) throw Exception('Usługi lokalizacji wyłączone');

      PermissionStatus perm = await loc.hasPermission();
      if (perm == PermissionStatus.denied) {
        perm = await loc.requestPermission();
        if (perm != PermissionStatus.granted) {
          throw Exception('Brak uprawnień do lokalizacji');
        }
      }

      final pos = await loc.getLocation();
      final pt = LatLng(pos.latitude!, pos.longitude!);
      _applyPoint(pt, 'Moja lokalizacja');
      _mapController.move(pt, 14);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _applyPoint(LatLng pt, String? label) {
    setState(() {
      if (_active == _ActivePoint.start) {
        _start = pt;
        _startLabel = label;
        if (_isLoop) {
          _end = pt;
          _endLabel = label;
        }
      } else {
        _end = pt;
        _endLabel = label;
      }
      _searchResults = [];
      _searchController.clear();
    });
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}&format=json&limit=5',
      );
      final resp = await http.get(uri, headers: {'User-Agent': 'GuideAI/1.0'});
      if (!mounted) return;
      final list = jsonDecode(resp.body) as List;
      setState(() {
        _searchResults = list.cast<Map<String, dynamic>>();
        _searchLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _onSearchChanged(String q) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _searchAddress(q));
  }

  void _toggleLoop(bool val) {
    setState(() {
      _isLoop = val;
      if (val && _start != null) {
        _end = _start;
        _endLabel = _startLabel;
      }
    });
  }

  String _displayLabel(LatLng? pt, String? label, String fallback) {
    if (pt == null) return fallback;
    if (label != null) return label;
    return '${pt.latitude.toStringAsFixed(4)}, ${pt.longitude.toStringAsFixed(4)}';
  }

  bool get _canConfirm => _start != null;

  void _confirm() {
    if (_start == null) return;
    Navigator.pop(
      context,
      RouteSelection(
        start: _start!,
        startLabel: _displayLabel(_start, _startLabel, ''),
        end: _isLoop ? null : _end,
        endLabel: _isLoop ? null : (_end != null ? _displayLabel(_end, _endLabel, '') : null),
        isLoop: _isLoop,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _start ?? _fallback;
    final showResults = _searchResults.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustaw trasę'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13,
                onTap: (_, pt) => _applyPoint(pt, null),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.guideai',
                ),
                MarkerLayer(
                  markers: [
                    if (_start != null)
                      Marker(
                        point: _start!,
                        width: 44,
                        height: 44,
                        child: const _PinMarker(label: 'A', color: Colors.green),
                      ),
                    if (_end != null && !_isLoop)
                      Marker(
                        point: _end!,
                        width: 44,
                        height: 44,
                        child: const _PinMarker(label: 'B', color: Colors.red),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Hint bar
          if (!showResults)
            Material(
              color: _active == _ActivePoint.start
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 15,
                      color: _active == _ActivePoint.start ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Dotknij mapy aby ustawić '
                      '${_active == _ActivePoint.start ? "Start" : "Koniec"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _active == _ActivePoint.start ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Panel dolny
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Start / Koniec tabs + Pętla toggle
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PointTab(
                            label: 'Start',
                            sublabel: _displayLabel(_start, _startLabel, 'Nie ustawiono'),
                            color: Colors.green,
                            letter: 'A',
                            isActive: _active == _ActivePoint.start,
                            onTap: () => setState(() => _active = _ActivePoint.start),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PointTab(
                            label: 'Koniec',
                            sublabel: _isLoop
                                ? 'Pętla (= Start)'
                                : _displayLabel(_end, _endLabel, 'Nie ustawiono'),
                            color: _isLoop ? Colors.orange : Colors.red,
                            letter: 'B',
                            isActive: !_isLoop && _active == _ActivePoint.end,
                            onTap: _isLoop
                                ? null
                                : () => setState(() => _active = _ActivePoint.end),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: _isLoop,
                              onChanged: _toggleLoop,
                              activeColor: Colors.orange,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            const Text('Pętla', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 14),

                  // Wyszukiwarka + GPS
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Szukaj adresu...',
                              prefixIcon: _searchLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : const Icon(Icons.search, size: 20),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchResults = []);
                                      },
                                    )
                                  : null,
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Moja lokalizacja',
                          child: OutlinedButton(
                            onPressed: _loadingGps ? null : _useGps,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(10),
                              minimumSize: const Size(44, 44),
                            ),
                            child: _loadingGps
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.my_location, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Potwierdź
                  if (_canConfirm)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _confirm,
                          icon: const Icon(Icons.check),
                          label: const Text('Potwierdź trasę'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),

                  // Wyniki wyszukiwania
                  if (showResults)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        itemBuilder: (_, i) {
                          final r = _searchResults[i];
                          final displayName = r['display_name'] as String? ?? '';
                          final shortName = displayName.split(',').take(2).join(', ');
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined, size: 18),
                            title: Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap: () {
                              final pt = LatLng(
                                double.parse(r['lat'] as String),
                                double.parse(r['lon'] as String),
                              );
                              _applyPoint(pt, shortName);
                              _mapController.move(pt, 15);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinMarker extends StatelessWidget {
  final String label;
  final Color color;

  const _PinMarker({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_pin, color: color, size: 44),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _PointTab extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final String letter;
  final bool isActive;
  final VoidCallback? onTap;

  const _PointTab({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.letter,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? color : Colors.grey.shade300,
            width: isActive ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isActive ? color.withOpacity(0.07) : null,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: color,
              child: Text(
                letter,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
