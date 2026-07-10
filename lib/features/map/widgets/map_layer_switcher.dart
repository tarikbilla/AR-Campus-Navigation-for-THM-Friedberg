import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../map_styles.dart';

/// A compact map-layer switcher: a floating "layers" button that expands into a
/// list of base-map moods (Standard, Cycle, Satellite, Dark). Tapping the main
/// button while collapsed quickly **cycles** to the next layer; tapping it while
/// expanded (or picking an item) selects a specific one.
class MapLayerSwitcher extends StatefulWidget {
  const MapLayerSwitcher({
    super.key,
    required this.styles,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<MapStyle> styles;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  State<MapLayerSwitcher> createState() => _MapLayerSwitcherState();
}

class _MapLayerSwitcherState extends State<MapLayerSwitcher> {
  bool _open = false;

  void _select(int index) {
    HapticFeedback.selectionClick();
    widget.onSelected(index);
    setState(() => _open = false);
  }

  void _cycle() {
    HapticFeedback.selectionClick();
    final next = (widget.currentIndex + 1) % widget.styles.length;
    widget.onSelected(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = widget.styles[widget.currentIndex];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomRight,
          child: _open
              ? _panel(scheme)
              : const SizedBox(width: 0, height: 0),
        ),
        const SizedBox(height: 10),
        _mainButton(scheme, current),
      ],
    );
  }

  Widget _mainButton(ColorScheme scheme, MapStyle current) {
    return Material(
      elevation: 4,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _open ? () => setState(() => _open = false) : _cycle,
        onLongPress: () => setState(() => _open = !_open),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.layers_outlined, color: scheme.primary, size: 26),
              Positioned(
                right: 6,
                bottom: 6,
                child: Icon(current.icon, size: 13, color: scheme.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < widget.styles.length; i++)
            _tile(scheme, i, widget.styles[i]),
        ],
      ),
    );
  }

  Widget _tile(ColorScheme scheme, int index, MapStyle style) {
    final bool selected = index == widget.currentIndex;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _select(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              style.icon,
              size: 19,
              color: selected ? scheme.onPrimaryContainer : scheme.primary,
            ),
            const SizedBox(width: 10),
            Text(
              style.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            if (selected)
              Icon(Icons.check, size: 16, color: scheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}
