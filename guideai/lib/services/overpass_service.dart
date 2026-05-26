import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/war_place.dart';

/// Pobiera do 5 miejsc historycznych (memoriały) w promieniu 1 km od [startPoint].
Future<List<WarPlace>> fetchWarPlaces(LatLng startPoint) async {
  final lat = startPoint.latitude;
  final lon = startPoint.longitude;

  final query = '''
[out:json][timeout:25];
node["historic"="memorial"](around:1000,$lat,$lon);
out 5;
''';

  final encoded = Uri.encodeComponent(query);
  final url = 'https://overpass-api.de/api/interpreter?data=$encoded';

  final response = await http.get(
    Uri.parse(url),
    headers: {'User-Agent': 'GuideAI/1.0 (test@test.com)'},
  );

  if (response.statusCode != 200) {
    throw Exception('Błąd HTTP: ${response.statusCode}');
  }

  final data = json.decode(response.body);
  final elements = data['elements'] as List;

  final places = <WarPlace>[];
  for (final el in elements) {
    double? elLat, elLon;
    if (el['type'] == 'node') {
      elLat = el['lat']?.toDouble();
      elLon = el['lon']?.toDouble();
    } else if (el['center'] != null) {
      elLat = el['center']['lat']?.toDouble();
      elLon = el['center']['lon']?.toDouble();
    }
    if (elLat == null || elLon == null) continue;

    final name = el['tags']?['name'] ?? el['tags']?['historic'] ?? 'Brak nazwy';
    places.add(WarPlace(position: LatLng(elLat, elLon), name: name));
  }

  return places;
}
