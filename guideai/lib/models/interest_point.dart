import 'package:latlong2/latlong.dart';

class InterestPoint {
  final LatLng position;
  final String name;
  final String categoryId;
  final Map<String, dynamic> tags;

  InterestPoint({
    required this.position,
    required this.name,
    required this.categoryId,
    required this.tags,
  });
}
