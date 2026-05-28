import 'package:flutter/material.dart';
import '../models/interest_point.dart';
import '../models/interest_category.dart';

class PlaceDetailsSheet extends StatelessWidget {
  final InterestPoint place;
  final InterestCategory? category;

  const PlaceDetailsSheet({
    super.key,
    required this.place,
    required this.category,
  });

  static const _tagLabels = <String, String>{
    'description':      'Opis',
    'description:pl':   'Opis',
    'opening_hours':    'Godziny otwarcia',
    'website':          'Strona',
    'contact:website':  'Strona',
    'url':              'Strona',
    'phone':            'Telefon',
    'contact:phone':    'Telefon',
    'architect':        'Architekt',
    'start_date':       'Data powstania',
    'operator':         'Operator',
    'fee':              'Wstęp',
    'access':           'Dostęp',
    'wikipedia':        'Wikipedia',
    'heritage':         'Dziedzictwo',
    'note':             'Notatka',
  };

  String? _address(Map<String, dynamic> tags) {
    final street = tags['addr:street'] as String?;
    final number = tags['addr:housenumber'] as String?;
    final city   = tags['addr:city'] as String?;
    if (street == null && city == null) return null;
    final parts = <String>[
      if (street != null) [street, if (number != null) number].join(' '),
      if (city != null) city,
    ];
    return parts.join(', ');
  }

  String? _osmType(Map<String, dynamic> tags) =>
      (tags['historic'] ?? tags['tourism'] ?? tags['amenity'] ?? tags['leisure'])
          as String?;

  @override
  Widget build(BuildContext context) {
    final tags    = place.tags;
    final color   = category?.color ?? Colors.grey;
    final address = _address(tags);
    final osmType = _osmType(tags);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Nagłówek z kolorem kategorii
          Container(
            width: double.infinity,
            color: color.withOpacity(0.1),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category != null)
                  Row(
                    children: [
                      Icon(category!.icon, size: 14, color: color),
                      const SizedBox(width: 6),
                      Text(
                        category!.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  place.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (osmType != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      osmType,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Lista szczegółów
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (address != null) _infoRow(context, Icons.location_on_outlined, 'Adres', address),
                ..._tagLabels.entries.map((entry) {
                  // Użyj pierwszego znalezionego klucza (np. 'description' przed 'description:pl')
                  final value = tags[entry.key] as String?;
                  if (value == null || value.isEmpty) return const SizedBox.shrink();
                  // Pomiń duplikaty (np. jeśli 'description' już pokazany, pomiń 'description:pl')
                  final alreadyShown = entry.key.contains(':') &&
                      tags[entry.key.split(':').first] != null;
                  if (alreadyShown) return const SizedBox.shrink();
                  return _infoRow(context, _iconForTag(entry.key), entry.value, value);
                }),
                _coordinatesRow(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coordinatesRow(BuildContext context) {
    final lat = place.position.latitude.toStringAsFixed(5);
    final lon = place.position.longitude.toStringAsFixed(5);
    return _infoRow(context, Icons.gps_fixed, 'Współrzędne', '$lat, $lon');
  }

  IconData _iconForTag(String key) {
    return switch (key) {
      'opening_hours'                          => Icons.access_time,
      'website' || 'contact:website' || 'url' => Icons.language,
      'phone' || 'contact:phone'              => Icons.phone,
      'architect'                              => Icons.engineering,
      'start_date'                             => Icons.calendar_today,
      'operator'                               => Icons.business,
      'fee'                                    => Icons.monetization_on_outlined,
      'wikipedia'                              => Icons.article_outlined,
      'heritage'                               => Icons.stars,
      _                                        => Icons.info_outline,
    };
  }
}
