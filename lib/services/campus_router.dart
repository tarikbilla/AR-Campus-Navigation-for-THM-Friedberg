import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/utils/geo_utils.dart';
import '../data/campus_paths.dart';
import '../data/models/walking_route.dart';

/// Where an arbitrary point projects onto the campus lane network: the closest
/// point on the nearest lane segment, the two endpoint node indices of that
/// segment, and the distances involved.
class _Snap {
  const _Snap({
    required this.point,
    required this.nodeA,
    required this.nodeB,
    required this.distToA,
    required this.distToB,
    required this.offset,
    required this.t,
    required this.edgeLen,
  });

  final LatLng point;
  final int nodeA;
  final int nodeB;
  final double distToA;
  final double distToB;

  /// Straight-line distance from the query point to [point] (metres).
  final double offset;

  /// Parametric position along nodeA→nodeB (0..1), and the segment length.
  final double t;
  final double edgeLen;

  int get edgeKey => nodeA <= nodeB ? nodeA * 1000003 + nodeB : nodeB * 1000003 + nodeA;
}

/// Routes over the real OpenStreetMap campus footpath graph ([CampusPaths]) with
/// Dijkstra's algorithm, so walking directions follow the actual lanes drawn on
/// the map instead of the main road. Both the origin (live GPS) and the
/// destination (a building) are snapped onto the nearest lane, and the whole
/// graph is restricted to the largest connected component so routes never
/// dead-end on an isolated fragment.
///
/// Returns `null` when either end is too far from any lane or no path exists, so
/// [RoutingService] can fall back to online routing.
class CampusRouter {
  const CampusRouter();

  static const double _walkingSpeedMps = 1.35; // ~4.9 km/h

  /// Max distance (m) a point may be from the network to still snap onto it.
  static const double _maxSnap = 60.0;

  WalkingRoute? route(LatLng origin, LatLng destination) {
    final nodes = CampusPaths.nodes;
    final adjacency = CampusPaths.adjacency;
    final edges = CampusPaths.edges;
    if (nodes.isEmpty || edges.isEmpty) return null;

    final snapO = _snap(origin, nodes, edges);
    final snapD = _snap(destination, nodes, edges);
    if (snapO == null || snapD == null) return null;

    // Dijkstra seeded from the origin edge's two endpoints. Snap offsets are
    // constant end-caps, so they don't influence the chosen path — added later.
    final dist = <int, double>{};
    final prev = <int, int>{};
    final settled = <int>{};
    final queue = HeapPriorityQueue<_QEntry>((a, b) => a.cost.compareTo(b.cost));

    void seed(int id, double cost) {
      if (cost < (dist[id] ?? double.infinity)) {
        dist[id] = cost;
        queue.add(_QEntry(id, cost));
      }
    }

    seed(snapO.nodeA, snapO.distToA);
    seed(snapO.nodeB, snapO.distToB);

    while (queue.isNotEmpty) {
      final entry = queue.removeFirst();
      final id = entry.id;
      if (!settled.add(id)) continue;
      // Stop once both destination endpoints are finalised.
      if (settled.contains(snapD.nodeA) && settled.contains(snapD.nodeB)) break;

      final here = nodes[id];
      for (final nId in adjacency[id] ?? const <int>[]) {
        if (settled.contains(nId)) continue;
        final cost = dist[id]! + GeoUtils.distanceMeters(here, nodes[nId]);
        if (cost < (dist[nId] ?? double.infinity)) {
          dist[nId] = cost;
          prev[nId] = id;
          queue.add(_QEntry(nId, cost));
        }
      }
    }

    // Best destination endpoint (cost through the graph to the dest snap point).
    int? endpoint;
    double bestGraph = double.infinity;
    if (dist[snapD.nodeA] != null && dist[snapD.nodeA]! + snapD.distToA < bestGraph) {
      bestGraph = dist[snapD.nodeA]! + snapD.distToA;
      endpoint = snapD.nodeA;
    }
    if (dist[snapD.nodeB] != null && dist[snapD.nodeB]! + snapD.distToB < bestGraph) {
      bestGraph = dist[snapD.nodeB]! + snapD.distToB;
      endpoint = snapD.nodeB;
    }

    // If both snaps landed on the same lane segment, walking straight along it
    // may be shorter than going out to a node and back.
    final bool sameEdge = snapO.edgeKey == snapD.edgeKey;
    final double directCost =
        sameEdge ? (snapO.t - snapD.t).abs() * snapO.edgeLen : double.infinity;

    List<LatLng> mid;
    if (directCost <= bestGraph) {
      if (directCost.isInfinite) return null; // unreachable and not same-edge
      mid = const [];
    } else {
      // Reconstruct the node path from the chosen dest endpoint back to a seed.
      final path = <int>[];
      int? cursor = endpoint;
      while (cursor != null) {
        path.add(cursor);
        cursor = prev[cursor];
      }
      mid = [for (final id in path.reversed) nodes[id]];
    }

    final points = <LatLng>[origin, snapO.point, ...mid, snapD.point, destination];
    final cleaned = _dedupe(points);
    if (cleaned.length < 2) return null;

    double meters = 0;
    for (int i = 1; i < cleaned.length; i++) {
      meters += GeoUtils.distanceMeters(cleaned[i - 1], cleaned[i]);
    }

    return WalkingRoute(
      points: cleaned,
      distanceMeters: meters,
      durationSeconds: meters / _walkingSpeedMps,
      isFallback: false,
    );
  }

  /// Projects [p] onto the nearest lane segment (giant component only).
  _Snap? _snap(LatLng p, List<LatLng> nodes, List<List<int>> edges) {
    final double mPerLat = 111320.0;
    final double mPerLng = 111320.0 * math.cos(p.latitude * math.pi / 180.0);
    double px(LatLng q) => (q.longitude - p.longitude) * mPerLng;
    double py(LatLng q) => (q.latitude - p.latitude) * mPerLat;
    LatLng toLatLng(double x, double y) =>
        LatLng(p.latitude + y / mPerLat, p.longitude + x / mPerLng);

    _Snap? best;
    double bestOffset = double.infinity;

    for (final e in edges) {
      final a = nodes[e[0]];
      final b = nodes[e[1]];
      final ax = px(a), ay = py(a);
      final dx = px(b) - ax, dy = py(b) - ay;
      final segLen2 = dx * dx + dy * dy;
      double t = 0;
      if (segLen2 > 0) {
        t = ((-ax) * dx + (-ay) * dy) / segLen2;
        t = t.clamp(0.0, 1.0);
      }
      final sx = ax + dx * t, sy = ay + dy * t;
      final offset = math.sqrt(sx * sx + sy * sy);
      if (offset < bestOffset) {
        bestOffset = offset;
        final edgeLen = GeoUtils.distanceMeters(a, b);
        best = _Snap(
          point: toLatLng(sx, sy),
          nodeA: e[0],
          nodeB: e[1],
          distToA: edgeLen * t,
          distToB: edgeLen * (1 - t),
          offset: offset,
          t: t,
          edgeLen: edgeLen,
        );
      }
    }
    if (best == null || best.offset > _maxSnap) return null;
    return best;
  }

  List<LatLng> _dedupe(List<LatLng> pts) {
    final out = <LatLng>[];
    for (final p in pts) {
      if (out.isEmpty || GeoUtils.distanceMeters(out.last, p) > 0.5) {
        out.add(p);
      }
    }
    return out;
  }
}

class _QEntry {
  const _QEntry(this.id, this.cost);
  final int id;
  final double cost;
}

/// Minimal binary-heap priority queue (avoids adding a package dependency).
class HeapPriorityQueue<E> {
  HeapPriorityQueue(this._compare);

  final int Function(E a, E b) _compare;
  final List<E> _items = <E>[];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(E value) {
    _items.add(value);
    int child = _items.length - 1;
    while (child > 0) {
      final parent = (child - 1) >> 1;
      if (_compare(_items[child], _items[parent]) >= 0) break;
      _swap(child, parent);
      child = parent;
    }
  }

  E removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      _bubbleDown(0);
    }
    return first;
  }

  void _bubbleDown(int index) {
    final n = _items.length;
    int i = index;
    while (true) {
      final left = 2 * i + 1;
      final right = 2 * i + 2;
      int smallest = i;
      if (left < n && _compare(_items[left], _items[smallest]) < 0) {
        smallest = left;
      }
      if (right < n && _compare(_items[right], _items[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == i) break;
      _swap(i, smallest);
      i = smallest;
    }
  }

  void _swap(int a, int b) {
    final tmp = _items[a];
    _items[a] = _items[b];
    _items[b] = tmp;
  }
}
