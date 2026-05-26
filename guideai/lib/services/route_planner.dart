import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../models/war_place.dart';
import '../models/planner_result.dart';
import 'routing_service.dart';

// ── Stałe ─────────────────────────────────────────────────────────────────────

/// Współczynnik drogi vs linia prosta (typowo 1.2–1.4 dla miast).
const double _roadFactor = 1.3;

/// Minimalna odległość między miejscami — bliżej = duplikat/skupisko.
const double _minPlaceDistMeters = 80.0;

// ── Publiczne API ──────────────────────────────────────────────────────────────

/// Planuje trasę [start] → [wybrane miejsca] → [end] o szacowanym dystansie
/// ~[targetMeters] (±10%).
///
/// Algorytm:
/// 1. Deduplikacja skupisk bliższych niż [_minPlaceDistMeters].
/// 2. Sortowanie kandydatów wg odległości od prostej A→B.
/// 3. Greedy Best Insertion — każde miejsce wstawiane tam, gdzie wydłuża
///    trasę najmniej; kandydat odrzucany gdy przekracza próg.
/// 4. Jedno zapytanie do OSRM z finalnymi waypointami → realny dystans.
Future<PlannerResult> planRoute({
  required LatLng start,
  required LatLng end,
  required List<WarPlace> candidates,
  required double targetMeters,
}) async {
  // 1. Deduplikacja
  final deduped = _deduplicate(candidates);

  // 2. Sortuj: im bliżej linii A→B, tym wyższy priorytet
  final sorted = [...deduped]
    ..sort((a, b) {
      final dA = _pointToSegmentDist(a.position, start, end);
      final dB = _pointToSegmentDist(b.position, start, end);
      return dA.compareTo(dB);
    });

  // 3. Greedy Best Insertion
  final waypoints = <LatLng>[start, end];
  final selected = <WarPlace>[];
  final upperBound = targetMeters * 1.1; // tolerancja +10%

  for (final place in sorted) {
    // Znajdź pozycję z minimalnym detourem
    int bestIdx = 1;
    double bestDetour = double.infinity;

    for (int i = 0; i < waypoints.length - 1; i++) {
      final detour = _haversine(waypoints[i], place.position) +
          _haversine(place.position, waypoints[i + 1]) -
          _haversine(waypoints[i], waypoints[i + 1]);

      if (detour < bestDetour) {
        bestDetour = detour;
        bestIdx = i + 1;
      }
    }

    // Sprawdź szacowany dystans po wstawieniu
    final newWaypoints = [...waypoints]..insert(bestIdx, place.position);
    final estimated = _estimateDistance(newWaypoints);

    if (estimated <= upperBound) {
      waypoints.insert(bestIdx, place.position);
      selected.add(place);
    }
  }

  // 4. Zapytanie do OSRM z finalną listą waypointów → realny dystans
  final route = await fetchRouteMulti(waypoints);

  return PlannerResult(selectedPlaces: selected, route: route);
}

// ── Funkcje pomocnicze ─────────────────────────────────────────────────────────

/// Odległość haversine w metrach między dwoma punktami.
double haversineMeters(LatLng a, LatLng b) => _haversine(a, b);

double _haversine(LatLng a, LatLng b) {
  const R = 6371000.0; // promień Ziemi w metrach
  final phi1 = a.latitude * pi / 180;
  final phi2 = b.latitude * pi / 180;
  final dPhi = (b.latitude - a.latitude) * pi / 180;
  final dLambda = (b.longitude - a.longitude) * pi / 180;

  final sinP = sin(dPhi / 2);
  final sinL = sin(dLambda / 2);
  final aVal = sinP * sinP + cos(phi1) * cos(phi2) * sinL * sinL;

  return R * 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
}

/// Szacowany dystans trasy (suma odcinków haversine × współczynnik drogowy).
double _estimateDistance(List<LatLng> waypoints) {
  double total = 0;
  for (int i = 0; i < waypoints.length - 1; i++) {
    total += _haversine(waypoints[i], waypoints[i + 1]);
  }
  return total * _roadFactor;
}

/// Usuwa miejsca bliższe niż [_minPlaceDistMeters] od już dodanych (skupiska).
List<WarPlace> _deduplicate(List<WarPlace> places) {
  final result = <WarPlace>[];
  for (final place in places) {
    final tooClose = result.any(
      (p) => _haversine(p.position, place.position) < _minPlaceDistMeters,
    );
    if (!tooClose) result.add(place);
  }
  return result;
}

/// Przybliżona odległość punktu [p] od odcinka [a]→[b]
/// (płaskie przybliżenie — wystarczające dla krótkich odcinków w mieście).
double _pointToSegmentDist(LatLng p, LatLng a, LatLng b) {
  final dx = b.longitude - a.longitude;
  final dy = b.latitude - a.latitude;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) return _haversine(p, a);

  final t = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
      lenSq;
  final clamped = t.clamp(0.0, 1.0);

  return _haversine(
    p,
    LatLng(
      a.latitude + clamped * dy,
      a.longitude + clamped * dx,
    ),
  );
}
