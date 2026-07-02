import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/utils/geo_utils.dart';
import '../data/campus_data.dart';
import '../data/models/campus_building.dart';
import 'building_tile.dart';

/// A searchable, distance-sorted list of campus buildings presented as a modal
/// bottom sheet. Returns the chosen [CampusBuilding] via [Navigator.pop].
class BuildingListSheet extends StatefulWidget {
  const BuildingListSheet({
    super.key,
    this.userLocation,
    this.selectedId,
    this.title = 'Choose a building',
  });

  final LatLng? userLocation;
  final String? selectedId;
  final String title;

  static Future<CampusBuilding?> show(
    BuildContext context, {
    LatLng? userLocation,
    String? selectedId,
    String title = 'Choose a building',
  }) {
    return showModalBottomSheet<CampusBuilding>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BuildingListSheet(
        userLocation: userLocation,
        selectedId: selectedId,
        title: title,
      ),
    );
  }

  @override
  State<BuildingListSheet> createState() => _BuildingListSheetState();
}

class _BuildingListSheetState extends State<BuildingListSheet> {
  String _query = '';

  List<CampusBuilding> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = CampusData.buildings.where((b) {
      if (q.isEmpty) return true;
      return b.name.toLowerCase().contains(q) ||
          b.code.toLowerCase().contains(q) ||
          b.category.label.toLowerCase().contains(q);
    }).toList();

    final user = widget.userLocation;
    if (user != null) {
      list.sort((a, b) => GeoUtils.distanceMeters(user, a.location)
          .compareTo(GeoUtils.distanceMeters(user, b.location)));
    } else {
      list.sort((a, b) => a.code.compareTo(b.code));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.userLocation;
    final items = _filtered;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, controller) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.title,
                      style: theme.textTheme.titleLarge),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search buildings…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text('No buildings match "$_query"',
                            style: theme.textTheme.bodyMedium),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 2),
                        itemBuilder: (context, i) {
                          final b = items[i];
                          return BuildingTile(
                            building: b,
                            selected: b.id == widget.selectedId,
                            distanceMeters: user == null
                                ? null
                                : GeoUtils.distanceMeters(user, b.location),
                            onTap: () => Navigator.of(context).pop(b),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
