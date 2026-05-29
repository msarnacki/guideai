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
    // Pre-oblicz numery tylko dla głównych miejsc
    int mainNum = 0;
    final numbered = places.map((p) {
      return (place: p, number: p.isSidePoint ? null : ++mainNum);
    }).toList();

    final mainCount = mainNum;
    final sideCount = places.where((p) => p.isSidePoint).length;

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
                        isOrdered
                            ? 'Trasa — kolejność odwiedzin'
                            : 'Znalezione miejsca',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$mainCount ${_placesLabel(mainCount)}'
                        '${sideCount > 0 ? ' · $sideCount pobocznych' : ''}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                    itemCount: numbered.length,
                    separatorBuilder: (_, i) {
                      final isSide = numbered[i].place.isSidePoint;
                      return Divider(
                        height: 1,
                        indent: isSide ? 52 : 72,
                        color: isSide ? Colors.grey[200] : null,
                      );
                    },
                    itemBuilder: (ctx, index) {
                      final (:place, :number) = numbered[index];
                      final category = _categoryFor(place);
                      final color = category?.color ?? Colors.grey;

                      if (place.isSidePoint) {
                        return _buildSideItem(ctx, place, category);
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: color,
                          child: Text(
                            '$number',
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
                                    style:
                                        TextStyle(fontSize: 12, color: color),
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

  Widget _buildSideItem(
      BuildContext context, InterestPoint place, InterestCategory? category) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(28, 0, 8, 0),
      leading: Icon(
        Icons.fiber_manual_record,
        size: 10,
        color: Colors.grey[400],
      ),
      title: Text(
        place.name,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[700],
        ),
      ),
      subtitle: Text(
        category != null ? category.label : 'Punkt poboczny',
        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
      ),
      trailing: IconButton(
        icon: Icon(Icons.info_outline, size: 16, color: Colors.grey[400]),
        tooltip: 'Szczegóły',
        onPressed: () => _openDetails(context, place),
      ),
    );
  }

  String _placesLabel(int n) {
    if (n == 1) return 'miejsce';
    if (n >= 2 && n <= 4) return 'miejsca';
    return 'miejsc';
  }
}
