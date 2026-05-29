import 'dart:async';
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import '../models/interest_point.dart';

class NavigationUpdate {
  final LatLng snappedPosition;
  final double bearing; // 0 = N, 90 = E, clockwise
  final bool isOffRoute;

  const NavigationUpdate({
    required this.snappedPosition,
    required this.bearing,
    required this.isOffRoute,
  });
}

class ProximityEvent {
  final InterestPoint point;
  final int index;

  const ProximityEvent({required this.point, required this.index});
}

class NavigationService {
  final List<LatLng> polyline;
  final List<InterestPoint> orderedPoints;

  static const _proximityMeters = 50.0;
  static const _offRouteMeters = 30.0;
  static const _passedSegBuffer = 5;

  final _updateCtrl = StreamController<NavigationUpdate>.broadcast();
  final _proximityCtrl = StreamController<ProximityEvent>.broadcast();

  Stream<NavigationUpdate> get updates => _updateCtrl.stream;
  Stream<ProximityEvent> get proximityEvents => _proximityCtrl.stream;

  StreamSubscription<LocationData>? _sub;
  int _nextTriggerIdx = 0;
  LatLng? _lastRaw;
  double _lastBearing = 0;
  late final List<int> _pointSegments;

  NavigationService({required this.polyline, required this.orderedPoints}) {
    _pointSegments =
        orderedPoints.map((p) => _closestSegIdx(p.position)).toList();
  }

  Future<bool> start() async {
    final loc = Location();

    bool svc = await loc.serviceEnabled();
    if (!svc) svc = await loc.requestService();
    if (!svc) return false;

    PermissionStatus perm = await loc.hasPermission();
    if (perm == PermissionStatus.denied) {
      perm = await loc.requestPermission();
      if (perm != PermissionStatus.granted) return false;
    }

    await loc.changeSettings(
      accuracy: LocationAccuracy.navigation,
      interval: 1000,
      distanceFilter: 5,
    );

    _sub = loc.onLocationChanged.listen(_onLocation);
    return true;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
    if (!_updateCtrl.isClosed) _updateCtrl.close();
    if (!_proximityCtrl.isClosed) _proximityCtrl.close();
  }

  void _onLocation(LocationData data) {
    if (data.latitude == null || data.longitude == null) return;
    final raw = LatLng(data.latitude!, data.longitude!);

    final snap = _snapToPolyline(raw);

    double bearing = _lastBearing;
    if (data.heading != null && data.heading! >= 0) {
      bearing = data.heading!;
    } else if (_lastRaw != null && _haversine(raw, _lastRaw!) > 2) {
      bearing = _bearingBetween(_lastRaw!, raw);
    }
    _lastRaw = raw;
    _lastBearing = bearing;

    if (!_updateCtrl.isClosed) {
      _updateCtrl.add(NavigationUpdate(
        snappedPosition: snap.point,
        bearing: bearing,
        isOffRoute: snap.distFromPolyline > _offRouteMeters,
      ));
    }

    _checkProximity(raw, snap.segIdx);
  }

  void _checkProximity(LatLng position, int currentSeg) {
    // Skip points the user has already passed without triggering
    while (_nextTriggerIdx < orderedPoints.length) {
      if (currentSeg > _pointSegments[_nextTriggerIdx] + _passedSegBuffer) {
        _nextTriggerIdx++;
      } else {
        break;
      }
    }
    if (_nextTriggerIdx >= orderedPoints.length) return;

    final dist =
        _haversine(position, orderedPoints[_nextTriggerIdx].position);
    if (dist <= _proximityMeters) {
      final idx = _nextTriggerIdx;
      _nextTriggerIdx++;
      if (!_proximityCtrl.isClosed) {
        _proximityCtrl
            .add(ProximityEvent(point: orderedPoints[idx], index: idx));
      }
    }
  }

  // ── Geometry ──────────────────────────────────────────────────────────────

  _SnapResult _snapToPolyline(LatLng p) {
    if (polyline.length < 2) {
      return _SnapResult(point: p, segIdx: 0, distFromPolyline: 0);
    }
    double minDist = double.infinity;
    LatLng best = polyline[0];
    int bestSeg = 0;
    for (int i = 0; i < polyline.length - 1; i++) {
      final proj = _projectOnSeg(p, polyline[i], polyline[i + 1]);
      final d = _haversine(p, proj);
      if (d < minDist) {
        minDist = d;
        best = proj;
        bestSeg = i;
      }
    }
    return _SnapResult(point: best, segIdx: bestSeg, distFromPolyline: minDist);
  }

  int _closestSegIdx(LatLng p) {
    if (polyline.length < 2) return 0;
    double best = double.infinity;
    int bestI = 0;
    for (int i = 0; i < polyline.length - 1; i++) {
      final d = _haversine(p, _projectOnSeg(p, polyline[i], polyline[i + 1]));
      if (d < best) {
        best = d;
        bestI = i;
      }
    }
    return bestI;
  }

  LatLng _projectOnSeg(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    if (dx == 0 && dy == 0) return a;
    final t = ((p.longitude - a.longitude) * dx +
            (p.latitude - a.latitude) * dy) /
        (dx * dx + dy * dy);
    final tc = t.clamp(0.0, 1.0);
    return LatLng(a.latitude + tc * dy, a.longitude + tc * dx);
  }

  double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * R * asin(sqrt(h));
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) * pi / 180;
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x =
        cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }
}

class _SnapResult {
  final LatLng point;
  final int segIdx;
  final double distFromPolyline;

  const _SnapResult({
    required this.point,
    required this.segIdx,
    required this.distFromPolyline,
  });
}
