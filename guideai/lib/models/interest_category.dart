import 'package:flutter/material.dart';

class InterestCategory {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final List<String> overpassConditions;

  const InterestCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.overpassConditions,
  });

  /// Sprawdza czy tagi elementu OSM pasują do tej kategorii.
  bool matchesTags(Map<String, dynamic> tags) {
    for (final cond in overpassConditions) {
      if (_conditionMatches(cond, tags)) return true;
    }
    return false;
  }

  // Warunek może mieć formę '"key"="val"' lub '"k1"="v1"]["k2"="v2"'.
  bool _conditionMatches(String condition, Map<String, dynamic> tags) {
    final parts = condition.split('"]["');
    for (final part in parts) {
      final clean = part.replaceAll('"', '');
      final eqIdx = clean.indexOf('=');
      if (eqIdx == -1) return false;
      final key = clean.substring(0, eqIdx);
      final value = clean.substring(eqIdx + 1);
      if (tags[key] != value) return false;
    }
    return true;
  }
}

const List<InterestCategory> kInterestCategories = [
  InterestCategory(
    id: 'castles',
    label: 'Zamki, ruiny i wieże',
    icon: Icons.castle,
    color: Color(0xFF92400E),
    overpassConditions: [
      '"historic"="castle"',
      '"historic"="fort"',
      '"historic"="ruins"',
      '"historic"="tower"',
      '"historic"="archaeological_site"',
    ],
  ),
  InterestCategory(
    id: 'churches',
    label: 'Kościoły i katedry',
    icon: Icons.church,
    color: Color(0xFF6D28D9),
    overpassConditions: [
      '"amenity"="place_of_worship"]["religion"="christian"',
      '"building"="church"',
      '"building"="cathedral"',
      '"building"="chapel"',
    ],
  ),
  InterestCategory(
    id: 'museums',
    label: 'Muzea',
    icon: Icons.museum,
    color: Color(0xFF1D4ED8),
    overpassConditions: [
      '"tourism"="museum"',
    ],
  ),
  InterestCategory(
    id: 'monuments',
    label: 'Pomniki i memoriały',
    icon: Icons.account_balance,
    color: Color(0xFF374151),
    overpassConditions: [
      '"historic"="monument"',
      '"historic"="memorial"',
    ],
  ),
  InterestCategory(
    id: 'viewpoints',
    label: 'Punkty widokowe',
    icon: Icons.landscape,
    color: Color(0xFF0369A1),
    overpassConditions: [
      '"tourism"="viewpoint"',
    ],
  ),
  InterestCategory(
    id: 'parks',
    label: 'Parki miejskie',
    icon: Icons.park,
    color: Color(0xFF15803D),
    overpassConditions: [
      '"leisure"="park"',
    ],
  ),
  InterestCategory(
    id: 'culture',
    label: 'Galerie, teatry i opery',
    icon: Icons.palette,
    color: Color(0xFFBE185D),
    overpassConditions: [
      '"tourism"="gallery"',
      '"amenity"="theatre"',
    ],
  ),
  InterestCategory(
    id: 'streetart',
    label: 'Street art i murale',
    icon: Icons.brush,
    color: Color(0xFFEA580C),
    overpassConditions: [
      '"tourism"="artwork"]["artwork_type"="mural"',
      '"tourism"="artwork"]["artwork_type"="graffiti"',
      '"tourism"="artwork"]["artwork_type"="sculpture"',
    ],
  ),
  InterestCategory(
    id: 'palaces',
    label: 'Pałace i dwory',
    icon: Icons.home_work,
    color: Color(0xFFB45309),
    overpassConditions: [
      '"historic"="manor"',
      '"historic"="palace"',
      '"historic"="country_house"',
    ],
  ),
  InterestCategory(
    id: 'markets',
    label: 'Bazary i targowiska',
    icon: Icons.storefront,
    color: Color(0xFF0F766E),
    overpassConditions: [
      '"amenity"="marketplace"',
    ],
  ),
  InterestCategory(
    id: 'shrines',
    label: 'Kapliczki przydrożne',
    icon: Icons.stars,
    color: Color(0xFF7C3AED),
    overpassConditions: [
      '"historic"="wayside_cross"',
      '"historic"="wayside_shrine"',
    ],
  ),
  InterestCategory(
    id: 'squares',
    label: 'Place i rynki',
    icon: Icons.grid_view,
    color: Color(0xFF475569),
    overpassConditions: [
      '"place"="square"',
    ],
  ),
];
