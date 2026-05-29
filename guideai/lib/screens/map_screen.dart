import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import '../models/interest_category.dart';
import '../models/interest_point.dart';
import '../models/planner_result.dart';
import '../models/route_result.dart';
import '../services/navigation_service.dart';
import '../services/overpass_service.dart';
import '../services/route_planner.dart';
import 'navigation_popup.dart';
import 'place_details_sheet.dart';
import 'route_list_sheet.dart';

class MapScreen extends StatefulWidget {
  final LatLng startPoint;
  final LatLng? endPoint;
  final double targetDistanceMeters;
  final List<InterestCategory> categories;

  const MapScreen({
    super.key,
    required this.startPoint,
    this.endPoint,
    this.targetDistanceMeters = 5000,
    required this.categories,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  List<InterestPoint> _places = [];
  RouteResult? _route;
  bool _loading = true;
  String _loadingMessage = 'Szukam ciekawych miejsc...';
  String _status = '';
  bool _legendVisible = true;

  // ── Map controller ────────────────────────────────────────────────────────
  final _mapController = MapController();
  bool _mapReady = false;

  // ── Map-rotation animation ────────────────────────────────────────────────
  late final AnimationController _rotAnimCtrl;
  late final CurvedAnimation _rotCurve;
  double _fromMapRot = 0;
  double _toMapRot = 0;

  // ── Ambient location (without navigation) ─────────────────────────────────
  LatLng? _ambientPosition;
  StreamSubscription<LocationData>? _ambientSub;

  // ── Navigation state ──────────────────────────────────────────────────────
  bool _navMode = false;
  NavigationService? _navService;
  StreamSubscription<NavigationUpdate>? _navUpdateSub;
  StreamSubscription<ProximityEvent>? _navProximitySub;
  LatLng? _userPosition;
  double _userBearing = 0;
  bool _isOffRoute = false;
  bool _headingUp = true;

  // true when user panned/zoomed manually in nav mode → auto-follow paused
  bool _freeCam = false;

  static const _navZoom = 17.0;

  // Popup queue
  InterestPoint? _currentPopup;
  final List<InterestPoint> _popupQueue = [];
  Timer? _popupTimer;

  @override
  void initState() {
    super.initState();
    _rotAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_onRotTick);
    _rotCurve =
        CurvedAnimation(parent: _rotAnimCtrl, curve: Curves.easeOut);
    _loadAll();
  }

  @override
  void dispose() {
    _navUpdateSub?.cancel();
    _navProximitySub?.cancel();
    _navService?.dispose();
    _ambientSub?.cancel();
    _popupTimer?.cancel();
    _rotCurve.dispose();
    _rotAnimCtrl.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ── Ambient location ──────────────────────────────────────────────────────

  Future<void> _startAmbientLocation() async {
    if (_ambientSub != null) return;
    final loc = Location();

    bool svc = await loc.serviceEnabled();
    if (!svc) svc = await loc.requestService();
    if (!svc) return;

    PermissionStatus perm = await loc.hasPermission();
    if (perm == PermissionStatus.denied) {
      perm = await loc.requestPermission();
      if (perm != PermissionStatus.granted) return;
    }

    await loc.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 5000,
      distanceFilter: 10,
    );

    _ambientSub = loc.onLocationChanged.listen((data) {
      if (!mounted || data.latitude == null || data.longitude == null) return;
      setState(() {
        _ambientPosition = LatLng(data.latitude!, data.longitude!);
      });
    });
  }

  void _stopAmbientLocation() {
    _ambientSub?.cancel();
    _ambientSub = null;
  }

  // ── Rotation animation ────────────────────────────────────────────────────

  void _onRotTick() {
    if (!mounted || !_mapReady) return;
    final rot =
        _fromMapRot + (_toMapRot - _fromMapRot) * _rotCurve.value;
    _mapController.rotate(rot);
  }

  void _animateMapRotation(double targetDeg) {
    if (!_mapReady) return;
    final from = _mapController.camera.rotation;
    final diff = ((targetDeg - from) % 360 + 540) % 360 - 180;
    _fromMapRot = from;
    _toMapRot = from + diff;
    _rotAnimCtrl.forward(from: 0);
  }

  // ── Route loading ─────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    try {
      final candidates = await fetchInterestPoints(
        widget.startPoint,
        endPoint: widget.endPoint,
        categories: widget.categories,
        targetDistanceMeters: widget.targetDistanceMeters.toDouble(),
      );

      if (widget.endPoint != null) {
        setState(() => _loadingMessage =
            'Planuję trasę przez ${candidates.length} kandydatów...');

        final PlannerResult result = await planRoute(
          start: widget.startPoint,
          end: widget.endPoint!,
          candidates: candidates,
          targetMeters: widget.targetDistanceMeters,
        );

        setState(() => _loadingMessage = 'Szukam punktów pobocznych...');

        List<InterestPoint> gapFillers = [];
        try {
          final broadCandidates = await fetchBroadInterestPoints(
            widget.startPoint,
            widget.endPoint!,
            selectedCategories: widget.categories,
          );
          gapFillers = findGapFillers(
            start: widget.startPoint,
            end: widget.endPoint!,
            selectedPlaces: result.selectedPlaces,
            allExistingPlaces: result.allPlacesOrdered,
            routePolyline: result.route.points,
            broadCandidates: broadCandidates,
          );
        } catch (_) {}

        final allPlaces = sortPointsByRoute(
          [...result.allPlacesOrdered, ...gapFillers],
          result.route.points,
        );

        final mainCount = result.allPlacesOrdered.length;
        final sideCount = gapFillers.length;

        setState(() {
          _places = allPlaces;
          _route = result.route;
          _loading = false;
          _status =
              '$mainCount miejsc · ${_route!.distanceLabel} · ${_route!.durationLabel}'
              '${sideCount > 0 ? ' · +$sideCount pobocznych' : ''}';
        });
      } else {
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

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _startNavigation() async {
    if (_route == null) return;
    _stopAmbientLocation();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    final service = NavigationService(
      polyline: _route!.points,
      orderedPoints: _places,
    );

    final ok = await service.start();
    if (!ok) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      _startAmbientLocation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Nie można uruchomić nawigacji – brak dostępu do GPS'),
        ));
      }
      service.dispose();
      return;
    }

    _navUpdateSub = service.updates.listen(_handleNavUpdate);
    _navProximitySub = service.proximityEvents.listen(_handleProximity);

    setState(() {
      _navService = service;
      _navMode = true;
      _headingUp = true;
      _freeCam = false;
      _userPosition = _ambientPosition; // show marker immediately from last known position
    });
  }

  void _stopNavigation() {
    _navUpdateSub?.cancel();
    _navProximitySub?.cancel();
    _navService?.dispose();
    _popupTimer?.cancel();
    _navUpdateSub = null;
    _navProximitySub = null;
    _navService = null;

    _rotAnimCtrl.stop();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _animateMapRotation(0);

    setState(() {
      _navMode = false;
      _freeCam = false;
      _userPosition = null;
      _isOffRoute = false;
      _currentPopup = null;
      _popupQueue.clear();
    });

    _startAmbientLocation();
  }

  void _handleNavUpdate(NavigationUpdate update) {
    if (!mounted) return;
    setState(() {
      _userPosition = update.snappedPosition;
      _userBearing = update.bearing;
      _isOffRoute = update.isOffRoute;
    });
    if (!_mapReady || _freeCam) return;
    _mapController.move(update.snappedPosition, _mapController.camera.zoom);
    if (_headingUp) _animateMapRotation(-update.bearing);
  }

  // Centers camera on user. In nav mode also resumes auto-follow.
  void _recenter() {
    if (!_mapReady) return;
    if (_navMode) {
      setState(() => _freeCam = false);
      if (_userPosition != null) {
        _mapController.move(_userPosition!, _navZoom);
        if (_headingUp) _animateMapRotation(-_userBearing);
      }
    } else {
      if (_ambientPosition != null) {
        _mapController.move(_ambientPosition!, _mapController.camera.zoom);
      }
    }
  }

  void _handleProximity(ProximityEvent event) {
    if (!mounted) return;
    if (_currentPopup == null) {
      _showPopup(event.point);
    } else {
      setState(() => _popupQueue.add(event.point));
    }
  }

  void _showPopup(InterestPoint place) {
    _popupTimer?.cancel();
    setState(() => _currentPopup = place);
    _popupTimer = Timer(const Duration(minutes: 2), _dismissPopup);
  }

  void _dismissPopup() {
    _popupTimer?.cancel();
    setState(() {
      _currentPopup =
          _popupQueue.isNotEmpty ? _popupQueue.removeAt(0) : null;
    });
    if (_currentPopup != null) {
      _popupTimer = Timer(const Duration(minutes: 2), _dismissPopup);
    }
  }

  void _toggleHeadingMode() {
    setState(() => _headingUp = !_headingUp);
    if (!_headingUp) {
      _animateMapRotation(0);
    } else if (!_freeCam && _userPosition != null) {
      _animateMapRotation(-_userBearing);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  InterestCategory? _categoryFor(InterestPoint place) {
    try {
      return widget.categories.firstWhere((c) => c.id == place.categoryId);
    } catch (_) {
      return null;
    }
  }

  Color _colorFor(InterestPoint place) =>
      _categoryFor(place)?.color ?? Colors.red;

  void _showDetails(InterestPoint place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          PlaceDetailsSheet(place: place, category: _categoryFor(place)),
    );
  }

  void _showRouteList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => RouteListSheet(
        places: _places,
        categories: widget.categories,
        isOrdered: widget.endPoint != null,
      ),
    );
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  List<Marker> get _placeMarkers => _places.map((place) {
        if (place.isSidePoint) {
          return Marker(
            point: place.position,
            width: 28,
            height: 28,
            child: GestureDetector(
              onTap: () => _showDetails(place),
              child:
                  Icon(Icons.location_on, color: Colors.grey[500], size: 22),
            ),
          );
        }
        return Marker(
          point: place.position,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showDetails(place),
            child: Icon(Icons.location_on, color: _colorFor(place), size: 36),
          ),
        );
      }).toList();

  Marker get _startMarker => Marker(
        point: widget.startPoint,
        width: 44,
        height: 52,
        child: const Column(children: [
          Icon(Icons.place, color: Colors.green, size: 40),
          SizedBox(height: 2),
        ]),
      );

  Marker? get _endMarker => widget.endPoint == null
      ? null
      : Marker(
          point: widget.endPoint!,
          width: 44,
          height: 52,
          child: const Column(children: [
            Icon(Icons.place, color: Colors.blue, size: 40),
            SizedBox(height: 2),
          ]),
        );

  Marker? get _userMarker {
    if (_navMode) {
      if (_userPosition == null) return null;
      return Marker(
        point: _userPosition!,
        width: 32,
        height: 32,
        child: AnimatedRotation(
          turns: _userBearing / 360.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.arrow_upward,
                color: Colors.white, size: 14),
          ),
        ),
      );
    }

    if (_ambientPosition == null) return null;
    return Marker(
      point: _ambientPosition!,
      width: 18,
      height: 18,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4),
          ],
        ),
      ),
    );
  }

  // ── Map center ────────────────────────────────────────────────────────────

  LatLng get _mapCenter {
    if (widget.endPoint == null) return widget.startPoint;
    return LatLng(
      (widget.startPoint.latitude + widget.endPoint!.latitude) / 2,
      (widget.startPoint.longitude + widget.endPoint!.longitude) / 2,
    );
  }

  // ── Legend ────────────────────────────────────────────────────────────────

  bool get _hasSidePoints => _places.any((p) => p.isSidePoint);

  Widget _legendItem(IconData icon, Color color, String label,
      {double iconSize = 16}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: iconSize),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _buildLegend() {
    return Material(
      key: const ValueKey('legend'),
      borderRadius: BorderRadius.circular(8),
      color: Colors.white.withOpacity(0.93),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Legenda',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: () => setState(() => _legendVisible = false),
                child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
              ),
            ]),
            const SizedBox(height: 4),
            _legendItem(Icons.place, Colors.green, 'Start'),
            if (widget.endPoint != null)
              _legendItem(Icons.place, Colors.blue, 'Koniec'),
            const Divider(height: 10, thickness: 0.5),
            ...widget.categories
                .map((cat) => _legendItem(cat.icon, cat.color, cat.label)),
            if (_hasSidePoints) ...[
              const Divider(height: 10, thickness: 0.5),
              _legendItem(Icons.location_on, const Color(0xFF9E9E9E),
                  'Punkt poboczny',
                  iconSize: 13),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegendToggleButton() {
    return GestureDetector(
      key: const ValueKey('legend-btn'),
      onTap: () => setState(() => _legendVisible = true),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.93),
        elevation: 2,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.layers, size: 20, color: Colors.blueAccent),
        ),
      ),
    );
  }

  // ── Info panel ────────────────────────────────────────────────────────────

  Widget _routeInfoItem(IconData icon, String value, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 20, color: Colors.blueAccent),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    ]);
  }

  Widget _buildInfoPanel() {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Material(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withOpacity(0.93),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _routeInfoItem(
                  Icons.straighten, _route!.distanceLabel, 'dystans'),
              const VerticalDivider(width: 24, thickness: 1),
              _routeInfoItem(Icons.directions_walk, _route!.durationLabel,
                  'szac. czas'),
              const VerticalDivider(width: 24, thickness: 1),
              _routeInfoItem(
                  Icons.location_on,
                  '${_places.where((p) => !p.isSidePoint).length}',
                  'miejsc'),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom-right action buttons ───────────────────────────────────────────

  bool get _hasKnownPosition =>
      _navMode ? _userPosition != null : _ambientPosition != null;

  Widget _buildActionButtons() {
    final recenterColor =
        (_navMode && _freeCam) ? Colors.blueAccent : Colors.grey[600]!;

    return Positioned(
      right: 16,
      bottom: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Re-center — always visible when position is known
          if (_hasKnownPosition) ...[
            FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: _recenter,
              backgroundColor: Colors.white,
              elevation: 3,
              child: Icon(Icons.my_location, color: recenterColor),
            ),
            const SizedBox(height: 10),
          ],

          // Nawiguj / Stop
          if (_route != null)
            _navMode
                ? FloatingActionButton.extended(
                    heroTag: 'nav_stop',
                    onPressed: _stopNavigation,
                    backgroundColor: Colors.red[600],
                    icon: const Icon(Icons.stop_rounded, color: Colors.white),
                    label: const Text('Stop',
                        style: TextStyle(color: Colors.white)),
                  )
                : FloatingActionButton.extended(
                    heroTag: 'nav_start',
                    onPressed: _startNavigation,
                    backgroundColor: Colors.green[700],
                    icon: const Icon(Icons.navigation, color: Colors.white),
                    label: const Text('Nawiguj',
                        style: TextStyle(color: Colors.white)),
                  ),

          // Lista miejsc (only outside nav mode)
          if (!_navMode && _places.isNotEmpty) ...[
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'lista',
              onPressed: _showRouteList,
              icon: const Icon(Icons.format_list_numbered),
              label: const Text('Lista miejsc'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generuję trasę...')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_loadingMessage,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }

    final markers = [
      ..._placeMarkers,
      _startMarker,
      if (_endMarker != null) _endMarker!,
      if (_userMarker != null) _userMarker!,
    ];

    return Scaffold(
      appBar: _navMode ? null : AppBar(title: Text(_status)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 14,
              onMapReady: () {
                setState(() => _mapReady = true);
                _startAmbientLocation();
              },
              onMapEvent: (event) {
                if (!_navMode) return;
                if (event.source == MapEventSource.mapController) return;
                if (!_freeCam) setState(() => _freeCam = true);
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.guideai',
              ),
              if (_route != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _route!.points,
                    color: Colors.blueAccent,
                    strokeWidth: 4.5,
                  ),
                ]),
              MarkerLayer(markers: markers),
            ],
          ),

          // Route info panel (distance / time / count)
          if (_route != null) _buildInfoPanel(),

          // Off-route warning
          if (_navMode && _isOffRoute)
            Positioned(
              top: 80,
              left: 16,
              right: 80,
              child: Material(
                borderRadius: BorderRadius.circular(8),
                color: Colors.amber[700],
                elevation: 3,
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Zboczono z trasy',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

          // Heading-up / North-up toggle (nav mode only)
          if (_navMode)
            Positioned(
              top: _route != null ? 80 : 16,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'compass',
                onPressed: _toggleHeadingMode,
                backgroundColor: Colors.white,
                elevation: 3,
                child: Icon(
                  _headingUp ? Icons.explore : Icons.north,
                  color: Colors.blueAccent,
                ),
              ),
            ),

          // Legend
          Positioned(
            bottom: 80,
            left: 16,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _legendVisible
                  ? _buildLegend()
                  : _buildLegendToggleButton(),
            ),
          ),

          // Bottom-right action buttons (re-center + nav/stop + lista)
          _buildActionButtons(),

          // Proximity popup
          if (_navMode && _currentPopup != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: NavigationPopup(
                place: _currentPopup!,
                category: _categoryFor(_currentPopup!),
                queueCount: _popupQueue.length,
                onDismiss: _dismissPopup,
              ),
            ),
        ],
      ),
    );
  }
}
