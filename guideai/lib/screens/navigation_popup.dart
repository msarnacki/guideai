import 'package:flutter/material.dart';

import '../models/interest_category.dart';
import '../models/interest_point.dart';

class NavigationPopup extends StatelessWidget {
  final InterestPoint place;
  final InterestCategory? category;
  final int queueCount;
  final VoidCallback onDismiss;

  const NavigationPopup({
    super.key,
    required this.place,
    required this.category,
    required this.queueCount,
    required this.onDismiss,
  });

  static const _tagLabels = <String, String>{
    'description': 'Opis',
    'description:pl': 'Opis',
    'opening_hours': 'Godziny otwarcia',
    'website': 'Strona',
    'contact:website': 'Strona',
    'url': 'Strona',
    'phone': 'Telefon',
    'contact:phone': 'Telefon',
    'architect': 'Architekt',
    'start_date': 'Data powstania',
    'operator': 'Operator',
    'fee': 'Wstęp',
    'access': 'Dostęp',
    'wikipedia': 'Wikipedia',
    'heritage': 'Dziedzictwo',
    'note': 'Notatka',
  };

  @override
  Widget build(BuildContext context) {
    final color = category?.color ?? Colors.grey;
    final tags = place.tags;
    final address = _address(tags);
    final osmType =
        (tags['historic'] ?? tags['tourism'] ?? tags['amenity'] ?? tags['leisure'])
            as String?;

    final detailRows = <Widget>[
      if (address != null) _row(Icons.location_on_outlined, 'Adres', address),
      ..._tagLabels.entries.map((e) {
        final value = tags[e.key] as String?;
        if (value == null || value.isEmpty) return const SizedBox.shrink();
        final isDuplicate =
            e.key.contains(':') && tags[e.key.split(':').first] != null;
        if (isDuplicate) return const SizedBox.shrink();
        return _row(_iconFor(e.key), e.value, value);
      }),
    ];

    return Material(
      borderRadius: BorderRadius.circular(16),
      elevation: 10,
      shadowColor: Colors.black38,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(category!.icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category != null)
                        Text(
                          category!.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w600),
                        ),
                      Text(
                        place.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (osmType != null)
                        Text(osmType,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                  color: Colors.grey[500],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable details
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: detailRows.every((w) => w is SizedBox)
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Brak dodatkowych informacji.',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: detailRows,
                  ),
          ),
          // Queue indicator
          if (queueCount > 0)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Text(
                'Jeszcze $queueCount ${_queueLabel(queueCount)} w kolejce',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey[500])),
                const SizedBox(height: 1),
                Text(value, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _address(Map<String, dynamic> tags) {
    final street = tags['addr:street'] as String?;
    final number = tags['addr:housenumber'] as String?;
    final city = tags['addr:city'] as String?;
    if (street == null && city == null) return null;
    return <String>[
      if (street != null) [street, if (number != null) number].join(' '),
      if (city != null) city,
    ].join(', ');
  }

  String _queueLabel(int n) {
    if (n == 1) return 'miejsce';
    if (n >= 2 && n <= 4) return 'miejsca';
    return 'miejsc';
  }

  IconData _iconFor(String key) {
    return switch (key) {
      'opening_hours' => Icons.access_time,
      'website' || 'contact:website' || 'url' => Icons.language,
      'phone' || 'contact:phone' => Icons.phone,
      'architect' => Icons.engineering,
      'start_date' => Icons.calendar_today,
      'operator' => Icons.business,
      'fee' => Icons.monetization_on_outlined,
      'wikipedia' => Icons.article_outlined,
      'heritage' => Icons.stars,
      _ => Icons.info_outline,
    };
  }
}
