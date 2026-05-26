import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';

/// Wyznacza pieszą trasę przez [waypoints] (minimum 2 punkty) używając
/// publicznego serwera OSRM z profilem pieszym.
Future<RouteResult> fetchRouteMulti(List<LatLng> waypoints) async {
  assert(waypoints.length >= 2, 'Wymagane co najmniej 2 punkty');

  final coords =
      waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');

  final url = Uri.parse(
    'https://routing.openstreetmap.de/routed-foot/route/v1/foot/$coords'
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

  // GeoJSON zwraca [lon, lat]
  final rawCoords = route['geometry']['coordinates'] as List;
  final points = rawCoords
      .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList();

  return RouteResult(
    points: points,
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
  );
}

/// Skrót dla trasy dwupunktowej.
Future<RouteResult> fetchRoute(LatLng start, LatLng end) =>
    fetchRouteMulti([start, end]);
