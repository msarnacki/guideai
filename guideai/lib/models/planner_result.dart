import 'interest_point.dart';
import 'route_result.dart';

class PlannerResult {
  /// Miejsca dodane do waypointów trasy.
  final List<InterestPoint> selectedPlaces;

  /// Zdeduplikowane punkty leżące ≤50 m od polilinii (nie jako waypoint).
  final List<InterestPoint> nearbyPlaces;

  /// Wszystkie miejsca w kolejności wzdłuż trasy (do wyświetlenia).
  final List<InterestPoint> allPlacesOrdered;

  final RouteResult route;

  const PlannerResult({
    required this.selectedPlaces,
    required this.nearbyPlaces,
    required this.allPlacesOrdered,
    required this.route,
  });
}
