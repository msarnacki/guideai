import 'package:flutter/material.dart';
import '../models/interest_point.dart';
import '../models/interest_category.dart';
import 'place_details_sheet.dart';

class RouteListSheet extends StatelessWidget {
  final List<InterestPoint> places;
  final List<InterestCategory> categories;
  final bool isOrdered;

  const RouteListSheet({
    super.key,
    required this.places,
    required this.categories,
    required this.isOrdered,
  });

  InterestCategory? _categoryFor(InterestPoint place) {
    try {
      return categories.firstWhere((c) => c.id == place.categoryId);
    } catch (_) {
      return null;
    }
  }

  void _openDetails(BuildContext context, InterestPoint place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PlaceDetailsSheet(
        place: place,
        category: _categoryFor(place),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
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

          // Nagłówek
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.format_list_numbered, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOrdered ? 'Trasa — kolejność odwiedzin' : 'Znalezione miejsca',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${places.length} ${_placesLabel(places.length)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Lista miejsc
          Expanded(
            child: places.isEmpty
                ? const Center(child: Text('Brak miejsc do wyświetlenia'))
                : ListView.separated(
                    controller: controller,
                    itemCount: places.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (ctx, index) {
                      final place    = places[index];
                      final category = _categoryFor(place);
                      final color    = category?.color ?? Colors.grey;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: color,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          place.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: category != null
                            ? Row(
                                children: [
                                  Icon(category.icon, size: 12, color: color),
                                  const SizedBox(width: 4),
                                  Text(
                                    category.label,
                                    style: TextStyle(fontSize: 12, color: color),
                                  ),
                                ],
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.info_outline, size: 20),
                          tooltip: 'Szczegóły',
                          onPressed: () => _openDetails(ctx, place),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _placesLabel(int n) {
    if (n == 1) return 'miejsce';
    if (n >= 2 && n <= 4) return 'miejsca';
    return 'miejsc';
  }
}
