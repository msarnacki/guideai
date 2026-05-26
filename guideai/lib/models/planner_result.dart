import 'war_place.dart';
import 'route_result.dart';

class PlannerResult {
  final List<WarPlace> selectedPlaces;
  final RouteResult route;

  const PlannerResult({
    required this.selectedPlaces,
    required this.route,
  });
}
