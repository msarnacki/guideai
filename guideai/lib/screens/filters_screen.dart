import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/interest_category.dart';
import 'route_picker_screen.dart';
import 'map_screen.dart';

class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  LatLng? _startPoint;
  String? _startLabel;

  LatLng? _endPoint;
  String? _endLabel;
  bool _isLoop = false;

  double _distanceKm = 5.0;

  final Set<String> _selectedCategories = {};
  static const int _maxCategories = 3;

  Future<void> _pickRoute() async {
    final result = await Navigator.push<RouteSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePickerScreen(
          initialStart: _startPoint,
          initialStartLabel: _startLabel,
          initialEnd: _endPoint,
          initialEndLabel: _endLabel,
          initialLoop: _isLoop,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _startPoint = result.start;
        _startLabel = result.startLabel;
        _isLoop = result.isLoop;
        _endPoint = _isLoop ? null : result.end;
        _endLabel = _isLoop ? null : result.endLabel;
      });
    }
  }

  void _onGenerate() {
    if (_startPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz punkt startowy')),
      );
      return;
    }
    if (_selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz co najmniej jedną kategorię')),
      );
      return;
    }

    final categories = kInterestCategories
        .where((c) => _selectedCategories.contains(c.id))
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          startPoint: _startPoint!,
          endPoint: _isLoop ? _startPoint : _endPoint,
          targetDistanceMeters: _distanceKm * 1000,
          categories: categories,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );

  Widget _routeSection() {
    final hasRoute = _startPoint != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('Trasa'),
            const Spacer(),
            if (hasRoute)
              TextButton.icon(
                onPressed: _pickRoute,
                icon: const Icon(Icons.edit_location_alt, size: 18),
                label: const Text('Zmień'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!hasRoute)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickRoute,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Ustaw punkt startowy i końcowy'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: _pickRoute,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  children: [
                    _routeRow(
                      Icons.trip_origin,
                      Colors.green,
                      'Start',
                      _startLabel ?? '',
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 9),
                      child: SizedBox(
                        height: 10,
                        child: VerticalDivider(thickness: 1.5, width: 2),
                      ),
                    ),
                    _routeRow(
                      _isLoop ? Icons.loop : Icons.location_on,
                      _isLoop ? Colors.orange : (_endPoint != null ? Colors.red : Colors.grey),
                      'Koniec',
                      _isLoop
                          ? 'Pętla (= punkt startowy)'
                          : (_endLabel ?? 'Nie ustawiono — trasa otwarta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _routeRow(IconData icon, Color color, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          '$title: ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _categoriesSection() {
    final atLimit = _selectedCategories.length >= _maxCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Co cię interesuje?'),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text(
              'Wybierz do $_maxCategories kategorii',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            if (_selectedCategories.isNotEmpty)
              Text(
                '(wybrano: ${_selectedCategories.length}/$_maxCategories)',
                style: TextStyle(
                  fontSize: 12,
                  color: atLimit ? Colors.orange : Colors.grey,
                  fontWeight: atLimit ? FontWeight.bold : FontWeight.normal,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: kInterestCategories.map((cat) {
            final isSelected = _selectedCategories.contains(cat.id);
            final isDisabled = !isSelected && atLimit;
            return FilterChip(
              avatar: Icon(
                cat.icon,
                size: 16,
                color: isDisabled ? Colors.grey : null,
              ),
              label: Text(cat.label),
              selected: isSelected,
              onSelected: isDisabled
                  ? null
                  : (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategories.add(cat.id);
                        } else {
                          _selectedCategories.remove(cat.id);
                        }
                      });
                    },
            );
          }).toList(),
        ),
      ],
    );
  }

  bool get _canGenerate =>
      _startPoint != null && _selectedCategories.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guided Walk')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _routeSection(),

                  const SizedBox(height: 28),

                  _categoriesSection(),

                  const SizedBox(height: 28),

                  _sectionTitle('Dystans spaceru'),
                  const SizedBox(height: 4),
                  const Text(
                    'Używany gdy wybrano punkt startowy i końcowy',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('1 km', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Expanded(
                        child: Slider(
                          value: _distanceKm,
                          min: 1,
                          max: 20,
                          divisions: 19,
                          label: '${_distanceKm.round()} km',
                          onChanged: (v) => setState(() => _distanceKm = v),
                        ),
                      ),
                      const Text('20 km', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  Center(
                    child: Text(
                      '${_distanceKm.round()} km',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canGenerate ? _onGenerate : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Generuj trasę', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
