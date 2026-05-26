import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';

/// Wyznacza pieszą trasę między [start] a [end] używając publicznego serwera
/// OSRM (OpenStreetMap.de) z profilem pieszym.
///
/// Zwraca [RouteResult] z listą punktów trasy, dystansem w metrach
/// i szacowanym czasem przejścia w sekundach.
Future<RouteResult> fetchRoute(LatLng start, LatLng end) async {
  final url = Uri.parse(
    'https://routing.openstreetmap.de/routed-foot/route/v1/foot/'
    '${start.longitude},${start.latitude};'
    '${end.longitude},${end.latitude}'
    '?overview=full&geometries=geojson',
  );

  final response = await http.get(
    url,
    headers: {'User-Agent': 'GuideAI/1.0 (test@test.com)'},
  );

  if (response.statusCode != 200) {
    throw Exception('Błąd HTTP: ${response.statusCode}');
  }

  final data = json.decode(response.body);

  if (data['code'] != 'Ok') {
    throw Exception('Routing niedostępny: ${data['code']}');
  }

  final route = data['routes'][0];
  final double distanceMeters = (route['distance'] as num).toDouble();
  final double durationSeconds = (route['duration'] as num).toDouble();

  // GeoJSON zwraca współrzędne jako [lon, lat]
  final coords = route['geometry']['coordinates'] as List;
  final points = coords
      .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList();

  return RouteResult(
    points: points,
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
  );
}
