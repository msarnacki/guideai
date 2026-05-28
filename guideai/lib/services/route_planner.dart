import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../models/interest_point.dart';
import '../models/planner_result.dart';
import 'routing_service.dart';

// ── Stałe ─────────────────────────────────────────────────────────────────────

/// Współczynnik drogi vs linia prosta (typowo 1.2–1.4 dla miast).
const double _roadFactor = 1.3;

/// Minimalna odległość między miejscami — bliżej = duplikat/skupisko.
const double _minPlaceDistMeters = 80.0;

/// Minimalny wynik bogactwa opisu — punkty poniżej progu są odrzucane.
const int _minRichnessScore = 2;

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
  required List<InterestPoint> candidates,
  required double targetMeters,
}) async {
  // 1. Deduplikacja — kandydaci do trasy + odsunięte skupiska
  final dedupeResult = _deduplicate(candidates);
  final deduped = dedupeResult.candidates;
  final sidelined = dedupeResult.sidelined;

  // 1b. Filtruj słabo opisane punkty
  final rich = deduped.where((p) => _richnessScore(p.tags) >= _minRichnessScore).toList();

  // 2. Sortuj: im bliżej linii A→B, tym wyższy priorytet
  final sorted = [...rich]
    ..sort((a, b) {
      final dA = _pointToSegmentDist(a.position, start, end);
      final dB = _pointToSegmentDist(b.position, start, end);
      return dA.compareTo(dB);
    });

  // 3. Greedy Best Insertion
  final waypoints = <LatLng>[start, end];
  final selected = <InterestPoint>[];
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

  // Przywróć kolejność miejsc zgodną z kolejnością waypointów na trasie.
  final orderedSelected = <InterestPoint>[];
  for (int i = 1; i < waypoints.length - 1; i++) {
    final wp = waypoints[i];
    final match = selected.firstWhere(
      (p) => p.position.latitude == wp.latitude &&
             p.position.longitude == wp.longitude,
      orElse: () => selected.first,
    );
    orderedSelected.add(match);
  }

  // Zdeduplikowane punkty leżące blisko polilinii trasy.
  final nearbyPlaces = _filterNearRoute(sidelined, route.points);

  // Połącz i posortuj wszystkie miejsca wzdłuż trasy.
  final allPlacesOrdered = _sortByRouteProgress(
    [...orderedSelected, ...nearbyPlaces],
    route.points,
  );

  return PlannerResult(
    selectedPlaces: orderedSelected,
    nearbyPlaces: nearbyPlaces,
    allPlacesOrdered: allPlacesOrdered,
    route: route,
  );
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

/// Rozdziela miejsca na kandydatów trasy i odsunięte skupiska (< [_minPlaceDistMeters]).
/// Odsunięte punkty mogą później trafić na mapę jako pobliskie atrakcje.
({List<InterestPoint> candidates, List<InterestPoint> sidelined})
    _deduplicate(List<InterestPoint> places) {
  final candidates = <InterestPoint>[];
  final sidelined = <InterestPoint>[];
  for (final place in places) {
    final tooClose = candidates.any(
      (p) => _haversine(p.position, place.position) < _minPlaceDistMeters,
    );
    if (tooClose) {
      sidelined.add(place);
    } else {
      candidates.add(place);
    }
  }
  return (candidates: candidates, sidelined: sidelined);
}

/// Zwraca punkty z [sidelined] leżące ≤ [maxDistMeters] od polilinii trasy,
/// posortowane wzdłuż trasy.
List<InterestPoint> _filterNearRoute(
  List<InterestPoint> sidelined,
  List<LatLng> polyline, {
  double maxDistMeters = 50.0,
}) {
  if (polyline.length < 2) return [];

  final nearby = <({InterestPoint point, int segIdx})>[];
  for (final place in sidelined) {
    double minDist = double.infinity;
    int closestSeg = 0;
    for (int i = 0; i < polyline.length - 1; i++) {
      final d = _pointToSegmentDist(place.position, polyline[i], polyline[i + 1]);
      if (d < minDist) {
        minDist = d;
        closestSeg = i;
      }
    }
    if (minDist <= maxDistMeters) {
      nearby.add((point: place, segIdx: closestSeg));
    }
  }

  nearby.sort((a, b) => a.segIdx.compareTo(b.segIdx));
  return nearby.map((e) => e.point).toList();
}

/// Sortuje miejsca wg pozycji wzdłuż polilinii trasy.
List<InterestPoint> _sortByRouteProgress(
  List<InterestPoint> places,
  List<LatLng> polyline,
) {
  if (polyline.length < 2) return places;
  return [...places]..sort((a, b) {
      final ia = _closestSegmentIndex(a.position, polyline);
      final ib = _closestSegmentIndex(b.position, polyline);
      return ia.compareTo(ib);
    });
}

int _closestSegmentIndex(LatLng point, List<LatLng> polyline) {
  int best = 0;
  double bestDist = double.infinity;
  for (int i = 0; i < polyline.length - 1; i++) {
    final d = _pointToSegmentDist(point, polyline[i], polyline[i + 1]);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// Ocenia bogactwo opisu punktu na podstawie tagów OSM.
/// Wynik ≥ [_minRichnessScore] = punkt wart uwzględnienia w trasie.
int _richnessScore(Map<String, dynamic> tags) {
  int score = 0;
  if (tags.containsKey('wikidata') || tags.containsKey('wikipedia')) score += 3;
  if (tags.containsKey('description')) score += 2;
  if (tags.containsKey('website') || tags.containsKey('url')) score += 1;
  if (tags.containsKey('image') || tags.containsKey('wikimedia_commons')) score += 1;
  if (tags.containsKey('opening_hours')) score += 1;
  if (tags.length > 5) score += 1;
  return score;
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
