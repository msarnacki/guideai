import 'interest_point.dart';
import 'route_result.dart';

class PlannerResult {
  final List<InterestPoint> selectedPlaces;
  final RouteResult route;

  const PlannerResult({
    required this.selectedPlaces,
    required this.route,
  });
}
