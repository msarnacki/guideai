import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/interest_point.dart';

/// Pobiera do 100 punktów zainteresowania w obszarze wyznaczonym
/// przez [startPoint] i opcjonalny [endPoint].
///
/// Gdy podany jest tylko [startPoint], stosuje okrąg o promieniu 1 km.
/// Gdy podane są oba punkty, używa bounding boxa okalającego obydwa punkty
/// z 15% paddingiem po każdej stronie.
Future<List<InterestPoint>> fetchInterestPoints(
  LatLng startPoint, {
  LatLng? endPoint,
}) async {
  final query = endPoint != null
      ? _buildBboxQuery(startPoint, endPoint)
      : _buildRadiusQuery(startPoint);

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

  final places = <InterestPoint>[];
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
    places.add(InterestPoint(position: LatLng(elLat, elLon), name: name));
  }

  return places;
}

// ── Budowanie zapytań ─────────────────────────────────────────────────────────

/// Okrąg 1 km wokół jednego punktu.
String _buildRadiusQuery(LatLng point) {
  final lat = point.latitude;
  final lon = point.longitude;
  return '''
[out:json][timeout:30];
(
  node["historic"="memorial"](around:1000,$lat,$lon);
  way["historic"="memorial"](around:1000,$lat,$lon);
);
out center 100;
''';
}

/// Bounding box okalający oba punkty + 15% paddingu z każdej strony.
/// Minimalne rozszerzenie: ~500 m (~0.005°), żeby obszar nie był za mały
/// gdy punkty są blisko siebie.
String _buildBboxQuery(LatLng start, LatLng end) {
  const padding = 0.15; // 15%
  const minPad = 0.005; // ~500 m

  final minLat = min(start.latitude, end.latitude);
  final maxLat = max(start.latitude, end.latitude);
  final minLon = min(start.longitude, end.longitude);
  final maxLon = max(start.longitude, end.longitude);

  final latPad = max((maxLat - minLat) * padding, minPad);
  final lonPad = max((maxLon - minLon) * padding, minPad);

  final south = minLat - latPad;
  final north = maxLat + latPad;
  final west  = minLon - lonPad;
  final east  = maxLon + lonPad;

  return '''
[out:json][timeout:30];
node["historic"="memorial"]($south,$west,$north,$east);
out 100;
''';
}
