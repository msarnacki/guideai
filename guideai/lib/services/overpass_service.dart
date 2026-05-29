import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/interest_point.dart';
import '../models/interest_category.dart';

Future<List<InterestPoint>> fetchInterestPoints(
  LatLng startPoint, {
  LatLng? endPoint,
  required List<InterestCategory> categories,
  required double targetDistanceMeters,
}) async {
  final query = endPoint != null
      ? _buildBboxQuery(startPoint, endPoint, categories)
      : _buildRadiusQuery(startPoint, categories, targetDistanceMeters);

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

    final tags = Map<String, dynamic>.from(el['tags'] as Map? ?? {});
    final categoryId = _detectCategoryId(tags, categories);
    final name = tags['name'] ??
        tags['historic'] ??
        tags['tourism'] ??
        tags['amenity'] ??
        'Brak nazwy';

    places.add(InterestPoint(
      position: LatLng(elLat, elLon),
      name: name,
      categoryId: categoryId,
      tags: tags,
    ));
  }

  return places;
}

String _detectCategoryId(
  Map<String, dynamic> tags,
  List<InterestCategory> categories,
) {
  for (final cat in categories) {
    if (cat.matchesTags(tags)) return cat.id;
  }
  return categories.first.id;
}

// ── Budowanie zapytań ─────────────────────────────────────────────────────────

String _conditionLines(String area, List<InterestCategory> categories) {
  final lines = <String>[];
  for (final cat in categories) {
    for (final cond in cat.overpassConditions) {
      lines.add('  node[$cond]($area);');
      lines.add('  way[$cond]($area);');
    }
  }
  return lines.join('\n');
}

/// Okrąg wokół jednego punktu — radius = 30% docelowego dystansu, min. 500 m, max. 10 km.
String _buildRadiusQuery(LatLng point, List<InterestCategory> categories, double targetDistanceMeters) {
  final radius = (targetDistanceMeters * 0.3).clamp(500, 10000).toInt();
  final lat = point.latitude;
  final lon = point.longitude;
  final conditions = _conditionLines('around:$radius,$lat,$lon', categories);
  return '''
[out:json][timeout:45];
(
$conditions
);
out center 100;
''';
}

/// Pobiera punkty ze wszystkich kategorii których user NIE wybrał — do zapełnienia luk.
Future<List<InterestPoint>> fetchBroadInterestPoints(
  LatLng start,
  LatLng end, {
  required List<InterestCategory> selectedCategories,
}) async {
  final remaining = kInterestCategories
      .where((cat) => !selectedCategories.any((s) => s.id == cat.id))
      .toList();
  if (remaining.isEmpty) return [];

  final query = _buildBboxQuery(start, end, remaining);
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

    final tags = Map<String, dynamic>.from(el['tags'] as Map? ?? {});
    final categoryId = _detectCategoryId(tags, remaining);
    final name = tags['name'] ??
        tags['historic'] ??
        tags['tourism'] ??
        tags['amenity'] ??
        tags['leisure'] ??
        'Brak nazwy';

    places.add(InterestPoint(
      position: LatLng(elLat, elLon),
      name: name,
      categoryId: categoryId,
      tags: tags,
      isSidePoint: true,
    ));
  }

  return places;
}

/// Bounding box okalający oba punkty + 15% paddingu z każdej strony.
String _buildBboxQuery(
  LatLng start,
  LatLng end,
  List<InterestCategory> categories,
) {
  const padding = 0.15;
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

  final conditions = _conditionLines('$south,$west,$north,$east', categories);
  return '''
[out:json][timeout:45];
(
$conditions
);
out center 100;
''';
}
