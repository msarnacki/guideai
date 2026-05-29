import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../models/interest_point.dart';
import '../models/planner_result.dart';
import '../models/route_result.dart';
import 'routing_service.dart';

// ── Stałe ─────────────────────────────────────────────────────────────────────

/// Współczynnik drogi vs linia prosta. Europejskie centra miast: 1.4–1.6.
const double _roadFactor = 1.5;

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
  final clusterSizes = dedupeResult.clusterSizes;

  // 1b. Filtruj słabo opisane punkty (uwzględnia też gęstość skupiska)
  final rich = deduped.where((p) {
    final densityBonus = ((clusterSizes[p] ?? 1) - 1).clamp(0, 3);
    return _richnessScore(p.tags) + densityBonus >= _minRichnessScore;
  }).toList();

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
  RouteResult route = await fetchRouteMulti(waypoints);

  // 4b. Post-trim: jeśli realna trasa przekracza cel o >10%, usuń
  //     punkt z minimalnym detourem i powtórz zapytanie OSRM.
  while (route.distanceMeters > targetMeters * 1.1 && waypoints.length > 2) {
    int removeIdx = 1;
    double minDetour = double.infinity;
    for (int i = 1; i < waypoints.length - 1; i++) {
      final detour = _haversine(waypoints[i - 1], waypoints[i]) +
          _haversine(waypoints[i], waypoints[i + 1]) -
          _haversine(waypoints[i - 1], waypoints[i + 1]);
      if (detour < minDetour) {
        minDetour = detour;
        removeIdx = i;
      }
    }
    waypoints.removeAt(removeIdx);
    selected.removeAt(removeIdx - 1);
    route = await fetchRouteMulti(waypoints);
  }

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

// ── Gap fillers ────────────────────────────────────────────────────────────────

/// Minimalna odległość między kolejnymi waypointami uznana za "lukę".
const double _gapThresholdMeters = 400.0;

/// Maksymalny dystans punktu pobocznego od polilinii trasy w obrębie luki.
const double _gapMaxRouteDistMeters = 80.0;

/// Minimalna odległość punktu pobocznego od każdego istniejącego punktu/waypointu.
const double _gapExclusionRadius = 200.0;

/// Maks. liczba punktów pobocznych na jedną lukę.
const int _gapMaxPerGap = 3;

/// Wykrywa odcinki trasy dłuższe niż [_gapThresholdMeters] i zwraca
/// najciekawsze punkty z [broadCandidates] leżące bezpośrednio przy tych odcinkach.
/// Punkty już na trasie (w [allExistingPlaces]) są wykluczone.
List<InterestPoint> findGapFillers({
  required LatLng start,
  required LatLng end,
  required List<InterestPoint> selectedPlaces,
  required List<InterestPoint> allExistingPlaces,
  required List<LatLng> routePolyline,
  required List<InterestPoint> broadCandidates,
}) {
  if (routePolyline.length < 2 || broadCandidates.isEmpty) return [];

  final mainWaypoints = [
    start,
    ...selectedPlaces.map((p) => p.position),
    end,
  ];

  final gaps = <(int, int)>[];
  for (int i = 0; i < mainWaypoints.length - 1; i++) {
    if (_haversine(mainWaypoints[i], mainWaypoints[i + 1]) > _gapThresholdMeters) {
      gaps.add((i, i + 1));
    }
  }
  if (gaps.isEmpty) return [];

  // Dołącz start i end — to LatLng, nie InterestPoint, więc wymagają osobnej listy
  final existingPositions = [
    start,
    end,
    ...allExistingPlaces.map((p) => p.position),
  ];
  final addedPositions = <LatLng>{};
  final result = <InterestPoint>[];

  for (final (idxA, idxB) in gaps) {
    final wpA = mainWaypoints[idxA];
    final wpB = mainWaypoints[idxB];

    final segA = _closestSegmentIndex(wpA, routePolyline);
    final segB = _closestSegmentIndex(wpB, routePolyline);
    final fromSeg = min(segA, segB);
    final toSeg = max(segA, segB);
    if (toSeg <= fromSeg) continue;

    final gapPoly = routePolyline.sublist(fromSeg, min(toSeg + 2, routePolyline.length));
    if (gapPoly.length < 2) continue;

    final gapCandidates = broadCandidates.where((p) {
      if (addedPositions.contains(p.position)) return false;
      if (existingPositions.any((pos) => _haversine(p.position, pos) < _gapExclusionRadius)) {
        return false;
      }
      for (int i = 0; i < gapPoly.length - 1; i++) {
        if (_pointToSegmentDist(p.position, gapPoly[i], gapPoly[i + 1]) <= _gapMaxRouteDistMeters) {
          return true;
        }
      }
      return false;
    }).toList();

    gapCandidates.sort((a, b) => _richnessScore(b.tags).compareTo(_richnessScore(a.tags)));

    final top = gapCandidates.take(_gapMaxPerGap).toList();
    for (final p in top) { addedPositions.add(p.position); }
    result.addAll(top);
  }

  return _sortByRouteProgress(result, routePolyline);
}

/// Sortuje listę miejsc wg postępu wzdłuż polilinii trasy (publiczny wrapper).
List<InterestPoint> sortPointsByRoute(
  List<InterestPoint> places,
  List<LatLng> polyline,
) => _sortByRouteProgress(places, polyline);

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
/// Pre-sortuje malejąco po richness + density, więc greedy wybiera najlepszego
/// reprezentanta z każdego skupiska. Zwraca też rozmiary skupisk (do filtru bogactwa).
({
  List<InterestPoint> candidates,
  List<InterestPoint> sidelined,
  Map<InterestPoint, int> clusterSizes,
}) _deduplicate(List<InterestPoint> places) {
  // Pre-sort: najlepszy punkt z klastra trafi jako pierwszy i zostanie reprezentantem
  final scored = [...places]..sort((a, b) {
      final da = _countNeighbors(a, places).clamp(0, 3);
      final db = _countNeighbors(b, places).clamp(0, 3);
      return (_richnessScore(b.tags) + db).compareTo(_richnessScore(a.tags) + da);
    });

  final candidates = <InterestPoint>[];
  final sidelined = <InterestPoint>[];
  final clusterSizes = <InterestPoint, int>{};

  for (final place in scored) {
    final rep = candidates.firstWhere(
      (p) => _haversine(p.position, place.position) < _minPlaceDistMeters,
      orElse: () => place,
    );
    if (rep != place) {
      sidelined.add(place);
      clusterSizes[rep] = (clusterSizes[rep] ?? 1) + 1;
    } else {
      candidates.add(place);
      clusterSizes[place] = 1;
    }
  }
  return (candidates: candidates, sidelined: sidelined, clusterSizes: clusterSizes);
}

/// Liczy sąsiadów punktu [p] w promieniu [_minPlaceDistMeters].
int _countNeighbors(InterestPoint p, List<InterestPoint> all) =>
    all.where((q) => q != p && _haversine(p.position, q.position) < _minPlaceDistMeters).length;

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
