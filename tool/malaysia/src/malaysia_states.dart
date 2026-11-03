import 'dart:math' as math;

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';

const stateCheckGridStepDegrees = 0.002;
const stateCheckToleranceMetres = 150.0;
const stateBorderSearchMetres = 5000.0;
const stateBorderMinimumShare = 0.8;
const gridMinLatitude = 0.8;
const gridMaxLatitude = 7.5;
const gridMinLongitude = 99.5;
const gridMaxLongitude = 119.5;

class StatePolygon {
  final String state;
  final List<List<int>> rings;

  StatePolygon(this.state, this.rings);
}

class StateBox {
  final String pair;
  final int minLat;
  final int maxLat;
  final int minLon;
  final int maxLon;

  StateBox(String stateA, String stateB, double minLat, double maxLat,
      double minLon, double maxLon)
      : pair = _pair(stateA, stateB),
        minLat = MalaysiaZoneMap.quantize(minLat),
        maxLat = MalaysiaZoneMap.quantize(maxLat),
        minLon = MalaysiaZoneMap.quantize(minLon),
        maxLon = MalaysiaZoneMap.quantize(maxLon);

  bool contains(int lat, int lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  bool explains(MismatchArea area) =>
      _pair(area.adm1State, area.zoneState) == pair &&
      contains(area.minLat, area.minLon) &&
      contains(area.maxLat, area.maxLon);
}

class MismatchArea {
  final String adm1State;
  final String zoneState;
  final Set<String> zones = {};
  double squareKilometres = 0;
  double depthMetres = 0;
  int deepestLat = 0;
  int deepestLon = 0;
  int minLat = 1 << 40;
  int maxLat = -(1 << 40);
  int minLon = 1 << 40;
  int maxLon = -(1 << 40);

  MismatchArea(this.adm1State, this.zoneState);

  String describe() => '${zones.join('/')} ($zoneState) inside ADM1 '
      '$adm1State, ${squareKilometres.toStringAsFixed(2)} km2, '
      '${depthMetres.round()} m deep at ${_degrees(deepestLat)},'
      '${_degrees(deepestLon)}, box ${_degrees(minLat)}..${_degrees(maxLat)} '
      '${_degrees(minLon)}..${_degrees(maxLon)}';
}

String _degrees(int quantized) => (quantized / 100000).toStringAsFixed(5);

String _pair(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

int _key(int lat, int lon) => (lat + 10000000) * (1 << 26) + lon;

int _latOf(int key) => key ~/ (1 << 26) - 10000000;

int _lonOf(int key) => key % (1 << 26);

List<List<int>> followStateBorders({
  required List<List<int>> arcs,
  required List<List<int>> arcUsers,
  required List<String?> regionStates,
  required List<StatePolygon> states,
  required List<StateBox> followBoxes,
  required List<String> errors,
}) {
  final ringsByState = <String, List<List<int>>>{};
  for (final polygon in states) {
    ringsByState.putIfAbsent(polygon.state, () => []).addAll(polygon.rings);
  }
  final statesByVertex = <int, Set<String>>{};
  final positions = <String, Map<int, List<int>>>{};
  ringsByState.forEach((state, rings) {
    final byVertex = positions[state] = {};
    for (var r = 0; r < rings.length; r++) {
      final ring = rings[r];
      for (var i = 0; i < ring.length; i += 2) {
        final key = _key(ring[i], ring[i + 1]);
        statesByVertex.putIfAbsent(key, () => {}).add(state);
        byVertex.putIfAbsent(key, () => [r, i ~/ 2]);
      }
    }
  });
  final borderVertices = <String, List<int>>{};
  statesByVertex.forEach((key, owners) {
    final sorted = owners.toList()..sort();
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        borderVertices
            .putIfAbsent('${sorted[i]}|${sorted[j]}', () => [])
            .add(key);
      }
    }
  });

  final borderEnds = <String, List<int>>{};
  borderVertices.forEach((pair, vertices) {
    final members = vertices.toSet();
    final state = pair.split('|').first;
    final rings = ringsByState[state]!;
    for (final key in vertices) {
      final position = positions[state]![key]!;
      final ring = rings[position[0]];
      final count = ring.length ~/ 2;
      bool member(int i) =>
          members.contains(_key(ring[i % count * 2], ring[i % count * 2 + 1]));
      if (!member(position[1] + count - 1) || !member(position[1] + 1)) {
        borderEnds.putIfAbsent(pair, () => []).add(key);
      }
    }
  });

  String? pairOf(int arc) {
    final users = arcUsers[arc];
    if (users.length != 2) return null;
    final a = regionStates[users[0]];
    final b = regionStates[users[1]];
    if (a == null || b == null || a == b) return null;
    return _pair(a, b);
  }

  bool follows(String pair, int lat, int lon) =>
      followBoxes.any((box) => box.pair == pair && box.contains(lat, lon));

  int? nearest(Iterable<int> candidates, int lat, int lon) {
    int? best;
    var bestMetres = stateBorderSearchMetres;
    for (final key in candidates) {
      final metres = _metres(lat, lon, _latOf(key), _lonOf(key));
      if (metres <= bestMetres) {
        best = key;
        bestMetres = metres;
      }
    }
    return best;
  }

  bool closed(List<int> arc) =>
      arc[0] == arc[arc.length - 2] && arc[1] == arc[arc.length - 1];

  final pairsAtJunction = <int, Set<String>>{};
  for (var a = 0; a < arcs.length; a++) {
    final pair = pairOf(a);
    final arc = arcs[a];
    if (pair == null || closed(arc)) continue;
    for (final end in [0, arc.length - 2]) {
      if (!follows(pair, arc[end], arc[end + 1])) continue;
      pairsAtJunction
          .putIfAbsent(_key(arc[end], arc[end + 1]), () => {})
          .add(pair);
    }
  }
  final work = [for (final arc in arcs) arc];
  final outerAt = <int, List<int>>{};
  for (var a = 0; a < arcs.length; a++) {
    if (arcUsers[a].length != 1 || closed(arcs[a])) continue;
    for (final end in [0, arcs[a].length - 2]) {
      outerAt
          .putIfAbsent(_key(arcs[a][end], arcs[a][end + 1]), () => [])
          .add(a);
    }
  }
  final moves = <int, int>{};
  final anchors = <int, int>{};
  pairsAtJunction.forEach((junction, pairs) {
    final lat = _latOf(junction);
    final lon = _lonOf(junction);
    final shared = pairs
        .map((pair) => (borderVertices[pair] ?? const <int>[]).toSet())
        .reduce((a, b) => a.intersection(b));
    final outer = outerAt[junction] ?? const <int>[];
    final target = outer.isNotEmpty
        ? nearest(
            pairs.expand((pair) => borderEnds[pair] ?? const <int>[]), lat, lon)
        : nearest(shared, lat, lon) ??
            nearest(
                pairs.expand((pair) => borderVertices[pair] ?? const <int>[]),
                lat,
                lon);
    if (target == null) {
      errors.add('no ADM1 border for ${pairs.join(', ')} within '
          '${stateBorderSearchMetres.round()} m of the junction at '
          '${_degrees(lat)},${_degrees(lon)}');
      return;
    }
    final slid = outer.length == 2 &&
            outer.any((a) => _inside(arcs, arcUsers, arcUsers[a].single,
                _latOf(target), _lonOf(target)))
        ? _slide(work[outer[0]], work[outer[1]], junction, target)
        : null;
    final moved =
        slid == null ? target : _key(slid[0][slid[0].length - 2], slid[0].last);
    if (slid != null) {
      work[outer[0]] = slid[0];
      work[outer[1]] = slid[1];
    }
    moves[junction] = moved;
    anchors[moved] = target;
  });

  List<int>? ringPath(String pair, int from, int to) {
    final owners = pair.split('|');
    for (final state in owners) {
      final start = positions[state]![from];
      final end = positions[state]![to];
      if (start == null || end == null || start[0] != end[0]) continue;
      final ring = ringsByState[state]![start[0]];
      final count = ring.length ~/ 2;
      List<int> walk(int step) {
        final path = <int>[start[1]];
        while (path.last != end[1]) {
          path.add((path.last + step + count) % count);
        }
        return path;
      }

      double share(List<int> path) =>
          path.where((i) {
            final key = _key(ring[i * 2], ring[i * 2 + 1]);
            return statesByVertex[key]!.containsAll(owners);
          }).length /
          path.length;
      final forward = walk(1);
      final backward = walk(-1);
      final forwardShare = share(forward);
      final backwardShare = share(backward);
      final path = forwardShare > backwardShare ||
              (forwardShare == backwardShare &&
                  forward.length <= backward.length)
          ? forward
          : backward;
      if (math.max(forwardShare, backwardShare) < stateBorderMinimumShare) {
        return null;
      }
      return [
        for (final i in path) ...[ring[i * 2], ring[i * 2 + 1]]
      ];
    }
    return null;
  }

  final result = <List<int>>[];
  for (var a = 0; a < arcs.length; a++) {
    final arc = [...work[a]];
    for (final end in [0, arc.length - 2]) {
      final target = moves[_key(arc[end], arc[end + 1])];
      if (target != null) {
        arc[end] = _latOf(target);
        arc[end + 1] = _lonOf(target);
      }
    }
    final pair = pairOf(a);
    if (pair == null || closed(arcs[a])) {
      result.add(arc);
      continue;
    }
    final last = arc.length ~/ 2 - 1;
    bool fixed(int i) =>
        i == 0 || i == last || !follows(pair, arc[i * 2], arc[i * 2 + 1]);
    bool movedEnd(int i) =>
        (i == 0 || i == last) &&
        anchors.containsKey(_key(arc[i * 2], arc[i * 2 + 1]));
    final out = <int>[arc[0], arc[1]];
    var k = 0;
    while (k < last) {
      var m = k + 1;
      while (!fixed(m)) {
        m++;
      }
      if (m > k + 1 || (movedEnd(k) && movedEnd(m))) {
        int? anchor(int i) =>
            anchors[_key(arc[i * 2], arc[i * 2 + 1])] ??
            nearest(
                borderVertices[pair] ?? const [], arc[i * 2], arc[i * 2 + 1]);
        final from = anchor(k);
        final to = anchor(m);
        final path =
            from == null || to == null ? null : ringPath(pair, from, to);
        if (path == null) {
          errors.add('no ADM1 $pair border between ${_degrees(arc[k * 2])},'
              '${_degrees(arc[k * 2 + 1])} and ${_degrees(arc[m * 2])},'
              '${_degrees(arc[m * 2 + 1])}');
          for (var i = k + 1; i <= m; i++) {
            out
              ..add(arc[i * 2])
              ..add(arc[i * 2 + 1]);
          }
          k = m;
          continue;
        }
        for (var i = 0; i < path.length; i += 2) {
          if (path[i] != out[out.length - 2] ||
              path[i + 1] != out[out.length - 1]) {
            out
              ..add(path[i])
              ..add(path[i + 1]);
          }
        }
      }
      if (arc[m * 2] != out[out.length - 2] ||
          arc[m * 2 + 1] != out[out.length - 1]) {
        out
          ..add(arc[m * 2])
          ..add(arc[m * 2 + 1]);
      }
      k = m;
    }
    result.add(out);
  }
  for (final junction in moves.keys) {
    if (outerAt.containsKey(junction)) continue;
    _untangle(result, moves[junction]!, pairOf);
  }
  return result;
}

void _untangle(
    List<List<int>> arcs, int junction, String? Function(int) pairOf) {
  final internal = <int>[];
  final borders = <int>[];
  for (var a = 0; a < arcs.length; a++) {
    final arc = arcs[a];
    if (_key(arc[0], arc[1]) != junction &&
        _key(arc[arc.length - 2], arc.last) == junction) {
      arcs[a] = _reversed(arc);
    }
  }
  for (var a = 0; a < arcs.length; a++) {
    if (_key(arcs[a][0], arcs[a][1]) != junction) continue;
    (pairOf(a) == null ? internal : borders).add(a);
  }
  if (internal.length != 1 || borders.length != 2) return;
  final inner = arcs[internal.single];
  for (var i = 2; i < inner.length; i += 2) {
    for (var b = 0; b < 2; b++) {
      final border = arcs[borders[b]];
      for (var j = 2; j < border.length; j += 2) {
        if (i == 2 && j == 2) continue;
        final crossing = _intersection(
            inner[i - 2],
            inner[i - 1],
            inner[i],
            inner[i + 1],
            border[j - 2],
            border[j - 1],
            border[j],
            border[j + 1]);
        if (crossing == null) continue;
        final other = arcs[borders[1 - b]];
        arcs[borders[b]] = [...crossing, ...border.sublist(j)];
        arcs[borders[1 - b]] = [
          ...crossing,
          ..._reversed(border.sublist(2, j)),
          ...other,
        ];
        arcs[internal.single] = [...crossing, ...inner.sublist(i)];
        return;
      }
    }
  }
}

List<int>? _intersection(
    int ay, int ax, int by, int bx, int cy, int cx, int dy, int dx) {
  final denominator = (bx - ax) * (dy - cy) - (by - ay) * (dx - cx);
  if (denominator == 0) return null;
  final t = ((cx - ax) * (dy - cy) - (cy - ay) * (dx - cx)) / denominator;
  final u = ((cx - ax) * (by - ay) - (cy - ay) * (bx - ax)) / denominator;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return [(ay + t * (by - ay)).round(), (ax + t * (bx - ax)).round()];
}

bool _inside(List<List<int>> arcs, List<List<int>> arcUsers, int region,
    int lat, int lon) {
  var inside = false;
  for (var a = 0; a < arcs.length; a++) {
    if (!arcUsers[a].contains(region)) continue;
    final arc = arcs[a];
    for (var i = 2; i < arc.length; i += 2) {
      final lat1 = arc[i - 2];
      final lat2 = arc[i];
      if ((lat1 > lat) == (lat2 > lat)) continue;
      final lon1 = arc[i - 1];
      if (lon < lon1 + (lat - lat1) * (arc[i + 1] - lon1) / (lat2 - lat1)) {
        inside = !inside;
      }
    }
  }
  return inside;
}

List<int> _reversed(List<int> arc) => [
      for (var i = arc.length - 2; i >= 0; i -= 2) ...[arc[i], arc[i + 1]]
    ];

List<List<int>>? _slide(List<int> a, List<int> b, int junction, int target) {
  List<int>? endingAt(List<int> arc) {
    if (_key(arc[arc.length - 2], arc.last) == junction) return arc;
    if (_key(arc[0], arc[1]) == junction) return _reversed(arc);
    return null;
  }

  final first = endingAt(a);
  final second = endingAt(b);
  if (first == null || second == null) return null;
  final path = [...first, ..._reversed(second).sublist(2)];
  final lat = _latOf(target);
  final lon = _lonOf(target);
  final lonScale = math.cos(lat / 100000 * math.pi / 180) * 111320 / 110574;
  var bestSegment = -1;
  var bestDistance = double.infinity;
  var bestLat = 0;
  var bestLon = 0;
  for (var i = 0; i + 3 < path.length; i += 2) {
    final x1 = (path[i + 1] - lon) * lonScale;
    final y1 = (path[i] - lat).toDouble();
    final dx = (path[i + 3] - path[i + 1]) * lonScale;
    final dy = (path[i + 2] - path[i]).toDouble();
    final lengthSquared = dx * dx + dy * dy;
    var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared;
    t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
    final px = x1 + t * dx;
    final py = y1 + t * dy;
    final distance = px * px + py * py;
    if (distance < bestDistance) {
      bestDistance = distance;
      bestSegment = i;
      bestLat = (path[i] + t * (path[i + 2] - path[i])).round();
      bestLon = (path[i + 1] + t * (path[i + 3] - path[i + 1])).round();
    }
  }
  final head = path.sublist(0, bestSegment + 2);
  final tail = path.sublist(bestSegment + 2);
  if (head[head.length - 2] != bestLat || head.last != bestLon) {
    head
      ..add(bestLat)
      ..add(bestLon);
  }
  if (tail[0] != bestLat || tail[1] != bestLon) {
    tail.insertAll(0, [bestLat, bestLon]);
  }
  if (head.length < 4 || tail.length < 4) return null;
  return [head, tail];
}

List<MismatchArea> findStateMismatches({
  required MalaysiaZoneMap map,
  required List<List<int>> arcs,
  required List<List<int>> regionArcs,
  required List<String?> regionStates,
  required List<StatePolygon> states,
  required List<DateComponents> dates,
}) {
  final zoneStates = {for (final zone in map.zones) zone.code: zone.state};
  final regionsByArc = List.generate(arcs.length, (_) => <int>[]);
  for (var r = 0; r < regionArcs.length; r++) {
    for (final a in regionArcs[r]) {
      regionsByArc[a].add(r);
    }
  }

  final step = MalaysiaZoneMap.quantize(stateCheckGridStepDegrees);
  final minLat = MalaysiaZoneMap.quantize(gridMinLatitude);
  final maxLat = MalaysiaZoneMap.quantize(gridMaxLatitude);
  final minLon = MalaysiaZoneMap.quantize(gridMinLongitude);
  final maxLon = MalaysiaZoneMap.quantize(gridMaxLongitude);
  final columns = (maxLon - minLon) ~/ step + 1;

  final mismatchState = <int, String>{};
  final mismatchZones = <int, Set<String>>{};
  final mismatchDepth = <int, double>{};
  for (var row = 0; minLat + row * step <= maxLat; row++) {
    final lat = minLat + row * step;
    final stateAt = _scanline(lat, minLon, step, columns,
        [for (final s in states) s.rings], (index) => [index]);
    final regionAt = _scanline(
        lat,
        minLon,
        step,
        columns,
        [
          for (final arc in arcs) [arc]
        ],
        (index) => regionsByArc[index],
        open: true);
    for (var column = 0; column < columns; column++) {
      final stateIndex = stateAt[column];
      if (stateIndex < 0) continue;
      final state = states[stateIndex].state;
      final region = regionAt[column];
      if (region >= 0 && regionStates[region] == state) continue;
      final lon = minLon + column * step;
      final zones = <String>{};
      for (final date in dates) {
        final zone = map.zoneAt(lat / 100000, lon / 100000, date);
        if (zone != null && zoneStates[zone] != state) zones.add(zone);
      }
      if (zones.isEmpty) continue;
      final depth = _depthMetres(states[stateIndex].rings, lat, lon);
      if (depth <= stateCheckToleranceMetres) continue;
      final key = row * columns + column;
      mismatchState[key] = state;
      mismatchZones[key] = zones;
      mismatchDepth[key] = depth;
    }
  }

  final parent = <int, int>{for (final key in mismatchState.keys) key: key};
  int find(int key) {
    while (parent[key] != key) {
      parent[key] = parent[parent[key]!]!;
      key = parent[key]!;
    }
    return key;
  }

  for (final key in mismatchState.keys) {
    for (final neighbour in [
      key - columns - 1,
      key - columns,
      key - columns + 1,
      key - 1,
    ]) {
      if (mismatchState[neighbour] == mismatchState[key]) {
        parent[find(neighbour)] = find(key);
      }
    }
  }

  final areas = <int, MismatchArea>{};
  for (final key in mismatchState.keys) {
    final lat = minLat + key ~/ columns * step;
    final lon = minLon + key % columns * step;
    final zones = mismatchZones[key]!;
    final area = areas.putIfAbsent(find(key),
        () => MismatchArea(mismatchState[key]!, zoneStates[zones.first]!));
    area.zones.addAll(zones);
    area.squareKilometres += stateCheckGridStepDegrees *
        stateCheckGridStepDegrees *
        110.574 *
        111.320 *
        math.cos(lat / 100000 * math.pi / 180);
    final depth = mismatchDepth[key]!;
    if (depth > area.depthMetres) {
      area.depthMetres = depth;
      area.deepestLat = lat;
      area.deepestLon = lon;
    }
    area.minLat = math.min(area.minLat, lat);
    area.maxLat = math.max(area.maxLat, lat);
    area.minLon = math.min(area.minLon, lon);
    area.maxLon = math.max(area.maxLon, lon);
  }
  return areas.values.toList()
    ..sort((a, b) => b.depthMetres.compareTo(a.depthMetres));
}

List<int> _scanline(int lat, int minLon, int step, int columns,
    List<List<List<int>>> owners, List<int> Function(int owner) targets,
    {bool open = false}) {
  final crossings = <double>[];
  final crossingOwners = <int>[];
  for (var owner = 0; owner < owners.length; owner++) {
    for (final ring in owners[owner]) {
      for (var i = open ? 2 : 0; i < ring.length; i += 2) {
        final j = i == 0 ? ring.length - 2 : i - 2;
        final lat1 = ring[j];
        final lat2 = ring[i];
        if ((lat1 > lat) == (lat2 > lat)) continue;
        final lon1 = ring[j + 1];
        crossings
            .add(lon1 + (lat - lat1) * (ring[i + 1] - lon1) / (lat2 - lat1));
        crossingOwners.add(owner);
      }
    }
  }
  final order = List.generate(crossings.length, (i) => i)
    ..sort((a, b) => crossings[a].compareTo(crossings[b]));
  final result = List.filled(columns, -1);
  final inside = <int>{};
  var next = 0;
  for (var column = 0; column < columns; column++) {
    final lon = minLon + column * step;
    while (next < order.length && crossings[order[next]] <= lon) {
      for (final target in targets(crossingOwners[order[next]])) {
        if (!inside.remove(target)) inside.add(target);
      }
      next++;
    }
    if (inside.isNotEmpty) result[column] = inside.first;
  }
  return result;
}

double _metres(int lat1, int lon1, int lat2, int lon2) {
  final dy = (lat2 - lat1) * 110574 / 100000;
  final dx = (lon2 - lon1) *
      111320 *
      math.cos((lat1 + lat2) / 200000 * math.pi / 180) /
      100000;
  return math.sqrt(dx * dx + dy * dy);
}

double _depthMetres(List<List<int>> rings, int lat, int lon) {
  final lonScale = 111320 * math.cos(lat / 100000 * math.pi / 180) / 100000;
  const latScale = 110574 / 100000;
  var best = double.infinity;
  for (final ring in rings) {
    for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
      final x1 = (ring[j + 1] - lon) * lonScale;
      final y1 = (ring[j] - lat) * latScale;
      final dx = (ring[i + 1] - ring[j + 1]) * lonScale;
      final dy = (ring[i] - ring[j]) * latScale;
      final lengthSquared = dx * dx + dy * dy;
      var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared;
      t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
      final px = x1 + t * dx;
      final py = y1 + t * dy;
      best = math.min(best, px * px + py * py);
    }
  }
  return math.sqrt(best);
}
