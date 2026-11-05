import 'dart:math' as math;

import 'geometry.dart';
import 'osm_snapshot.dart';

const stitchSearchMetres = 5000.0;
const outerChainMetres = 10000.0;
const trimClusterMetres = 500.0;

enum _Kind { outer, inner, inter }

class _Vertices {
  final Map<int, int> _ids = {};
  final List<int> lats = [];
  final List<int> lons = [];

  int id(int lat, int lon) => _ids.putIfAbsent(vertexKey(lat, lon), () {
        lats.add(lat);
        lons.add(lon);
        return lats.length - 1;
      });

  int segment(int a, int b) => a < b ? a * (1 << 24) + b : b * (1 << 24) + a;
}

class _Connector {
  final List<int> point;
  final Set<int> dropped;
  final List<int> via;

  _Connector(this.point, {Set<int>? dropped, List<int>? via})
      : dropped = dropped ?? {},
        via = via ?? const [];
}

class _Junction {
  final int vertex;
  final Set<String> states;
  _Connector? shared;
  final Map<String, _Connector> byState = {};

  _Junction(this.vertex, this.states);

  _Connector? connectorFor(String state, {bool borrow = true}) =>
      byState[state] ??
      (borrow && byState.length == 1 ? byState.values.single : null) ??
      (byState.isEmpty ? shared : null);
}

class _Crossing {
  final List<int> point;
  final List<int> segment;
  final double metresFromStart;
  final Set<int> dropped;
  String chainState = '';

  _Crossing(this.point, this.segment, this.metresFromStart, this.dropped);
}

class _NodedRing {
  final OsmRing source;
  final List<int> points;
  final List<Set<String>> segmentStates;

  _NodedRing(this.source, this.points, this.segmentStates);
}

class _Stitcher {
  final Map<String, Shape> shapes;
  final Map<String, String> shapeStates;
  final OsmSnapshot snapshot;
  final List<String> errors;
  final _Vertices vertices = _Vertices();
  final Map<int, List<String>> usersBySegment = {};
  final Map<int, Set<int>> segmentsByVertex = {};
  final Map<int, _Junction> junctions = {};
  final Map<String, List<List<int>>> insertions = {};
  late final List<_NodedRing> noded;
  late final Map<int, List<List<int>>> nodedPositions;
  late final SegmentIndex sharedIndex;
  late final List<List<int>> triVertices;
  late final List<List<int>> sharedEnds;

  _Stitcher(this.shapes, this.shapeStates, this.snapshot, this.errors);

  String stateOf(String shapeId) => shapeStates[shapeId]!;

  void run() {
    _indexSegments();
    _indexSharedSegments();

    for (final shape in shapes.values) {
      for (final ring in shape.rings) {
        _collectJunctions(shape, ring);
      }
    }
    for (final junction in junctions.values) {
      _resolve(junction);
    }
    if (errors.isNotEmpty) return;
    _node();
    for (final shape in shapes.values) {
      final rebuilt = <List<int>>[];
      for (final ring in shape.rings) {
        final result = _rebuild(shape, ring);
        if (result != null && result.length >= 6) rebuilt.add(result);
      }
      shape.rings
        ..clear()
        ..addAll(rebuilt);
    }
    if (errors.isEmpty) _reportUnmatchedRings();
  }

  _Kind kindOf(List<String> users) {
    if (users.length == 1) return _Kind.outer;
    return stateOf(users[0]) == stateOf(users[1]) ? _Kind.inner : _Kind.inter;
  }

  void _indexSegments() {
    for (final shape in shapes.values) {
      for (final ring in shape.rings) {
        for (var i = 0; i < ring.length; i += 2) {
          final j = (i + 2) % ring.length;
          final a = vertices.id(ring[i], ring[i + 1]);
          final b = vertices.id(ring[j], ring[j + 1]);
          final key = vertices.segment(a, b);
          final users = usersBySegment.putIfAbsent(key, () => []);
          if (!users.contains(shape.id)) users.add(shape.id);
          segmentsByVertex.putIfAbsent(a, () => {}).add(key);
          segmentsByVertex.putIfAbsent(b, () => {}).add(key);
        }
      }
    }
    usersBySegment.forEach((key, users) {
      users.sort();
      if (users.length > 2) {
        errors.add('districts ${users.join(', ')} share one border segment at '
            '${degrees(vertices.lats[key ~/ (1 << 24)])},'
            '${degrees(vertices.lons[key ~/ (1 << 24)])}');
      }
    });
  }

  void _indexSharedSegments() {
    sharedIndex = SegmentIndex();
    triVertices = [];
    sharedEnds = [];
    final seen = <int>{};
    final sharedDegree = <int, int>{};
    final pointsByKey = <int, List<int>>{};
    final sharedSeen = <String>{};
    for (var r = 0; r < snapshot.rings.length; r++) {
      final points = snapshot.rings[r].points;
      for (var i = 0, j = points.length - 2; i < points.length; j = i, i += 2) {
        final key = vertexKey(points[i], points[i + 1]);
        pointsByKey[key] = [points[i], points[i + 1]];
        if (snapshot.statesOfVertex(points[i], points[i + 1]).length >= 3 &&
            seen.add(key)) {
          triVertices.add([points[i], points[i + 1]]);
        }
        if (!snapshot.isShared(
            points[j], points[j + 1], points[i], points[i + 1])) {
          continue;
        }
        final segmentKey = OsmSnapshot.canonicalSegment(
            points[j], points[j + 1], points[i], points[i + 1]);
        if (!sharedSeen.add(segmentKey)) continue;
        sharedIndex.addPolyline(
            [points[j], points[j + 1], points[i], points[i + 1]], r);
        for (final k in [key, vertexKey(points[j], points[j + 1])]) {
          sharedDegree[k] = (sharedDegree[k] ?? 0) + 1;
        }
        pointsByKey[vertexKey(points[j], points[j + 1])] = [
          points[j],
          points[j + 1]
        ];
      }
    }
    sharedDegree.forEach((key, degree) {
      if (degree != 2) sharedEnds.add(pointsByKey[key]!);
    });
  }

  List<String> _users(List<int> ring, int i) {
    final j = (i + 2) % ring.length;
    return usersBySegment[vertices.segment(
        vertices.id(ring[i], ring[i + 1]), vertices.id(ring[j], ring[j + 1]))]!;
  }

  bool _isJunction(List<int> ring, int i) {
    final previous = _users(ring, (i - 2 + ring.length) % ring.length);
    final current = _users(ring, i);
    return previous.join('|') != current.join('|');
  }

  void _collectJunctions(Shape shape, List<int> ring) {
    for (var i = 0; i < ring.length; i += 2) {
      if (!_isJunction(ring, i)) continue;
      final previous = _users(ring, (i - 2 + ring.length) % ring.length);
      final current = _users(ring, i);
      if (kindOf(previous) != _Kind.inter && kindOf(current) != _Kind.inter) {
        continue;
      }
      final v = vertices.id(ring[i], ring[i + 1]);
      junctions.putIfAbsent(v, () {
        final states = <String>{};
        for (final key in segmentsByVertex[v]!) {
          states.addAll(usersBySegment[key]!.map(stateOf));
        }
        return _Junction(v, states);
      });
    }
  }

  void _resolve(_Junction junction) {
    final v = junction.vertex;
    final lat = vertices.lats[v];
    final lon = vertices.lons[v];
    if (junction.states.length >= 3) {
      final tri = _nearestTriVertex(lat, lon, junction.states);
      if (tri == null) {
        errors.add('no OpenStreetMap point where ${junction.states.join(', ')} '
            'meet within ${stitchSearchMetres.round()} m of '
            '${degrees(lat)},${degrees(lon)}');
        return;
      }
      junction.shared = _Connector(tri);
      return;
    }
    final innerPairs = <String, List<String>>{};
    for (final key in segmentsByVertex[v]!) {
      final users = usersBySegment[key]!;
      if (kindOf(users) == _Kind.inner) innerPairs[stateOf(users[0])] = users;
    }
    for (final entry in innerPairs.entries) {
      final connector = _innerConnector(junction, entry.key, entry.value);
      if (connector != null) junction.byState[entry.key] = connector;
    }
    if (junction.byState.isNotEmpty) return;
    if (_outerCrossing(junction)) return;
    final nearest = _nearestSharedPoint(lat, lon, junction.states);
    if (nearest == null) {
      errors.add('no OpenStreetMap border between '
          '${junction.states.join(' and ')} within '
          '${stitchSearchMetres.round()} m of ${degrees(lat)},${degrees(lon)}');
      return;
    }
    junction.shared = _Connector(nearest);
  }

  bool _outerCrossing(_Junction junction) {
    final v = junction.vertex;
    final lat = vertices.lats[v], lon = vertices.lons[v];
    final chains = <List<int>>[];
    _Crossing? best;
    for (final key in segmentsByVertex[v]!) {
      final users = usersBySegment[key]!;
      if (kindOf(users) != _Kind.outer) continue;
      final chain = _chain(v, users, budget: outerChainMetres);
      chains.add(chain);
      for (final crossing in _crossings(chain, sharedIndex, junction.states)) {
        if (best == null || crossing.metresFromStart < best.metresFromStart) {
          best = crossing..chainState = stateOf(users.single);
        }
      }
    }
    if (best != null) {
      _cutChain(junction, best, _onSegment(best.point, best.segment), const []);
      return true;
    }
    final end = _nearestSharedEnd(lat, lon, junction.states);
    if (end == null) return false;
    if (_cleanStraight([lat, lon], end, junction.states, chains)) {
      junction.shared = _Connector(end);
      return true;
    }
    final clean = _cleanConnectorPoint(chains, end, junction.states) ??
        _nearestChainPoint(chains, end, v);
    if (clean == null) {
      junction.shared = _Connector(end);
      return true;
    }
    _cutChain(junction, clean, end, clean.point);
    return true;
  }

  bool _cleanStraight(List<int> from, List<int> to, Set<String> states,
      List<List<int>> chains) {
    final midLat = (from[0] + to[0]) ~/ 2;
    final midLon = (from[1] + to[1]) ~/ 2;
    if (snapshot.stateAt(midLat, midLon) != null) return false;
    if (snapshot.crossesState(states, from[0], from[1], to[0], to[1])) {
      return false;
    }
    for (final chain in chains) {
      for (var k = 0; k + 1 < chain.length; k++) {
        final a = chain[k], b = chain[k + 1];
        if (segmentsCross(from[0], from[1], to[0], to[1], vertices.lats[a],
            vertices.lons[a], vertices.lats[b], vertices.lons[b])) {
          return false;
        }
      }
    }
    return true;
  }

  void _cutChain(
      _Junction junction, _Crossing cut, List<int> point, List<int> ownVia) {
    final v = junction.vertex;
    final chainVia = <int>[];
    for (final id in cut.dropped) {
      if (id == v) continue;
      chainVia
        ..add(vertices.lats[id])
        ..add(vertices.lons[id]);
    }
    for (final state in junction.states) {
      junction.byState[state] = state == cut.chainState
          ? _Connector(point, dropped: cut.dropped, via: ownVia)
          : _Connector(point, via: [...chainVia, ...ownVia]);
    }
  }

  _Crossing? _cleanConnectorPoint(
      List<List<int>> chains, List<int> target, Set<String> states) {
    _Crossing? best;
    for (final chain in chains) {
      final dropped = <int>{};
      var metres = 0.0;
      for (var k = 0; k + 1 < chain.length; k++) {
        final a = chain[k];
        final b = chain[k + 1];
        final ay = vertices.lats[a], ax = vertices.lons[a];
        final by = vertices.lats[b], bx = vertices.lons[b];
        dropped.add(a);
        final candidates = <List<int>>[];
        for (final s in snapshot.segmentsNear(
            ay, ax, metresBetween(ay, ax, by, bx) + 10)) {
          if (!states.contains(snapshot.rings[s[4]].state)) continue;
          final crossing =
              segmentIntersection(ay, ax, by, bx, s[0], s[1], s[2], s[3]);
          if (crossing != null) candidates.add(crossing);
        }
        candidates.sort((p, q) => metresBetween(ay, ax, p[0], p[1])
            .compareTo(metresBetween(ay, ax, q[0], q[1])));
        candidates.add([by, bx]);
        for (final point in candidates) {
          final along = metres + metresBetween(ay, ax, point[0], point[1]);
          if (best != null && along >= best.metresFromStart) break;
          if (!_cleanStraight(point, target, states, chains)) continue;
          final atVertex = point[0] == by && point[1] == bx;
          best = _Crossing(
              point, const [], along, {...dropped, if (atVertex) b})
            ..chainState = stateOf(
                usersBySegment[vertices.segment(chain[0], chain[1])]!.single);
          break;
        }
        metres += metresBetween(ay, ax, by, bx);
      }
    }
    return best;
  }

  _Crossing? _nearestChainPoint(
      List<List<int>> chains, List<int> target, int v) {
    _Crossing? best;
    var bestMetres =
        metresBetween(vertices.lats[v], vertices.lons[v], target[0], target[1]);
    for (final chain in chains) {
      final dropped = <int>{};
      for (var k = 0; k + 1 < chain.length; k++) {
        final a = chain[k];
        final b = chain[k + 1];
        dropped.add(a);
        final point = nearestPointOnSegment(
            target[0],
            target[1],
            vertices.lats[a],
            vertices.lons[a],
            vertices.lats[b],
            vertices.lons[b]);
        final metres = metresBetween(target[0], target[1], point[0], point[1]);
        if (metres >= bestMetres) continue;
        bestMetres = metres;
        final atEnd =
            point[0] == vertices.lats[b] && point[1] == vertices.lons[b];
        best = _Crossing(point, const [], 0, {...dropped, if (atEnd) b})
          ..chainState = stateOf(
              usersBySegment[vertices.segment(chain[0], chain[1])]!.single);
      }
    }
    return best;
  }

  List<_Crossing> _crossings(
      List<int> chain, SegmentIndex index, Set<String> states) {
    final found = <_Crossing>[];
    final dropped = <int>{};
    var metres = 0.0;
    for (var k = 0; k + 1 < chain.length; k++) {
      final a = chain[k];
      final b = chain[k + 1];
      final ay = vertices.lats[a], ax = vertices.lons[a];
      final by = vertices.lats[b], bx = vertices.lons[b];
      dropped.add(a);
      for (final s in index.near(ay, ax, metresBetween(ay, ax, by, bx) + 10)) {
        if (!snapshot
            .statesOfSegment(s[0], s[1], s[2], s[3])
            .containsAll(states)) {
          continue;
        }
        final crossing =
            segmentIntersection(ay, ax, by, bx, s[0], s[1], s[2], s[3]);
        if (crossing == null) continue;
        found.add(_Crossing(
            crossing,
            s,
            metres + metresBetween(ay, ax, crossing[0], crossing[1]),
            {...dropped}));
      }
      metres += metresBetween(ay, ax, by, bx);
      if (metres > stitchSearchMetres) break;
    }
    return found;
  }

  List<int>? _nearestSharedEnd(int lat, int lon, Set<String> states) {
    List<int>? best;
    var bestMetres = stitchSearchMetres;
    for (final point in sharedEnds) {
      if (!snapshot.statesOfVertex(point[0], point[1]).containsAll(states)) {
        continue;
      }
      final metres = metresBetween(lat, lon, point[0], point[1]);
      if (metres <= bestMetres) {
        best = point;
        bestMetres = metres;
      }
    }
    return best;
  }

  List<int>? _nearestTriVertex(int lat, int lon, Set<String> states) {
    List<int>? best;
    var bestMetres = stitchSearchMetres;
    for (final point in triVertices) {
      if (!snapshot.statesOfVertex(point[0], point[1]).containsAll(states)) {
        continue;
      }
      final metres = metresBetween(lat, lon, point[0], point[1]);
      if (metres <= bestMetres) {
        best = point;
        bestMetres = metres;
      }
    }
    return best;
  }

  Iterable<List<int>> _sharedSegmentsNear(
      int lat, int lon, Set<String> states) sync* {
    for (final s in sharedIndex.near(lat, lon, stitchSearchMetres)) {
      if (snapshot
          .statesOfSegment(s[0], s[1], s[2], s[3])
          .containsAll(states)) {
        yield s;
      }
    }
  }

  List<int>? _nearestSharedPoint(int lat, int lon, Set<String> states) {
    List<int>? best;
    var bestMetres = stitchSearchMetres;
    for (final s in _sharedSegmentsNear(lat, lon, states)) {
      final metres = pointSegmentMetres(lat, lon, s[0], s[1], s[2], s[3]);
      if (metres <= bestMetres) {
        bestMetres = metres;
        best = _onSegment(
            nearestPointOnSegment(lat, lon, s[0], s[1], s[2], s[3]), s);
      }
    }
    return best;
  }

  List<int> _onSegment(List<int> point, List<int> segment) {
    if ((point[0] == segment[0] && point[1] == segment[1]) ||
        (point[0] == segment[2] && point[1] == segment[3])) {
      return point;
    }
    final key = OsmSnapshot.canonicalSegment(
        segment[0], segment[1], segment[2], segment[3]);
    insertions.putIfAbsent(key, () => []).add(point);
    return point;
  }

  List<int> _chain(int start, List<String> users,
      {double budget = stitchSearchMetres}) {
    final chain = <int>[start];
    var previous = -1;
    var current = start;
    var metres = 0.0;
    while (metres < budget) {
      int? next;
      for (final key in segmentsByVertex[current]!) {
        if (usersBySegment[key]!.join('|') != users.join('|')) continue;
        final other =
            key ~/ (1 << 24) == current ? key % (1 << 24) : key ~/ (1 << 24);
        if (other == previous) continue;
        next = other;
      }
      if (next == null) break;
      metres += metresBetween(vertices.lats[current], vertices.lons[current],
          vertices.lats[next], vertices.lons[next]);
      chain.add(next);
      if (segmentsByVertex[next]!.length != 2) break;
      previous = current;
      current = next;
    }
    return chain;
  }

  _Connector? _innerConnector(
      _Junction junction, String state, List<String> pair) {
    final chain = _chain(junction.vertex, pair);
    if (chain.length < 2) return null;
    final v = junction.vertex;
    final lat = vertices.lats[v];
    final lon = vertices.lons[v];
    final trimmed = _trim(chain, {state});
    if (trimmed != null) return trimmed;
    final extended = _extend(chain, state);
    if (extended != null) return extended;
    final nearest = _nearestSharedPoint(lat, lon, {state});
    return nearest == null ? null : _Connector(nearest);
  }

  _Connector? _trim(List<int> chain, Set<String> states) {
    final crossings = _crossings(chain, sharedIndex, states);
    if (crossings.isEmpty) return null;
    crossings.sort((a, b) => a.metresFromStart.compareTo(b.metresFromStart));
    var chosen = crossings.first;
    for (final crossing in crossings.skip(1)) {
      if (crossing.metresFromStart - chosen.metresFromStart >
          trimClusterMetres) {
        break;
      }
      chosen = crossing;
    }
    return _Connector(_onSegment(chosen.point, chosen.segment),
        dropped: chosen.dropped);
  }

  _Connector? _extend(List<int> chain, String state) {
    final v = chain[0];
    final p = chain[1];
    final lat = vertices.lats[v], lon = vertices.lons[v];
    final lonScale = lonScaleAt(lat);
    var dx = (lon - vertices.lons[p]) * lonScale;
    var dy = (lat - vertices.lats[p]) * latScale;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return null;
    dx /= length;
    dy /= length;
    final farLat = (lat + dy * stitchSearchMetres / latScale).round();
    final farLon = (lon + dx * stitchSearchMetres / lonScale).round();
    List<int>? best;
    List<int>? bestSegment;
    var bestMetres = double.infinity;
    for (final s in _sharedSegmentsNear(lat, lon, {state})) {
      final crossing =
          segmentIntersection(lat, lon, farLat, farLon, s[0], s[1], s[2], s[3]);
      if (crossing == null) continue;
      final metres = metresBetween(lat, lon, crossing[0], crossing[1]);
      if (metres < bestMetres) {
        bestMetres = metres;
        best = crossing;
        bestSegment = s;
      }
    }
    return best == null ? null : _Connector(_onSegment(best, bestSegment!));
  }

  void _node() {
    noded = [];
    nodedPositions = {};
    for (final ring in snapshot.rings) {
      final points = <int>[];
      final states = <Set<String>>[];
      final source = ring.points;
      for (var i = 0; i < source.length; i += 2) {
        final j = (i + 2) % source.length;
        final segmentStates = snapshot.statesOfSegment(
            source[i], source[i + 1], source[j], source[j + 1]);
        points
          ..add(source[i])
          ..add(source[i + 1]);
        states.add(segmentStates);
        final key = OsmSnapshot.canonicalSegment(
            source[i], source[i + 1], source[j], source[j + 1]);
        final inserted = insertions[key];
        if (inserted == null) continue;
        final ordered = [...inserted]
          ..sort((a, b) => metresBetween(source[i], source[i + 1], a[0], a[1])
              .compareTo(metresBetween(source[i], source[i + 1], b[0], b[1])));
        for (final point in ordered) {
          if (point[0] == points[points.length - 2] &&
              point[1] == points.last) {
            continue;
          }
          points
            ..add(point[0])
            ..add(point[1]);
          states.add(segmentStates);
        }
      }
      final index = noded.length;
      noded.add(_NodedRing(ring, points, states));
      for (var i = 0; i < points.length; i += 2) {
        nodedPositions
            .putIfAbsent(vertexKey(points[i], points[i + 1]), () => [])
            .add([index, i ~/ 2]);
      }
    }
  }

  List<int>? _path(String state, List<int> from, List<int> to, List<int> hint) {
    if (from[0] == to[0] && from[1] == to[1]) return [from[0], from[1]];
    final starts = nodedPositions[vertexKey(from[0], from[1])] ?? const [];
    final ends = nodedPositions[vertexKey(to[0], to[1])] ?? const [];
    List<int>? best;
    var bestMetres = double.infinity;
    for (final start in starts) {
      if (noded[start[0]].source.state != state) continue;
      for (final end in ends) {
        if (end[0] != start[0]) continue;
        for (final step in [1, -1]) {
          final path = _walk(noded[start[0]], start[1], end[1], step);
          if (path == null) continue;
          final middle = lineMidpoint(path);
          final metres = metresBetween(hint[0], hint[1], middle[0], middle[1]);
          if (metres < bestMetres) {
            bestMetres = metres;
            best = path;
          }
        }
      }
    }
    return best;
  }

  List<int>? _walk(_NodedRing ring, int from, int to, int step) {
    final count = ring.points.length ~/ 2;
    final path = <int>[ring.points[from * 2], ring.points[from * 2 + 1]];
    var i = from;
    while (i != to) {
      final segment = step == 1 ? i : (i - 1 + count) % count;
      if (ring.segmentStates[segment].length < 2) return null;
      i = (i + step + count) % count;
      path
        ..add(ring.points[i * 2])
        ..add(ring.points[i * 2 + 1]);
    }
    return path;
  }

  List<int>? _rebuild(Shape shape, List<int> ring) {
    final state = stateOf(shape.id);
    final count = ring.length ~/ 2;
    final junctionAt = [
      for (var i = 0; i < count; i++)
        if (_isJunction(ring, i * 2) &&
            junctions.containsKey(vertices.id(ring[i * 2], ring[i * 2 + 1])))
          i
    ];
    if (junctionAt.isEmpty) {
      if (kindOf(_users(ring, 0)) != _Kind.inter) return ring;
      return _wholeRing(shape, ring, state);
    }
    final runIsInter = [
      for (final a in junctionAt) kindOf(_users(ring, a * 2)) == _Kind.inter
    ];
    final out = _Output();
    for (var k = 0; k < junctionAt.length; k++) {
      final a = junctionAt[k];
      final b = junctionAt[(k + 1) % junctionAt.length];
      final users = _users(ring, a * 2);
      if (!runIsInter[k]) {
        _emitKept(out, ring, a, b, state,
            afterInter:
                runIsInter[(k - 1 + runIsInter.length) % runIsInter.length],
            beforeInter: runIsInter[(k + 1) % runIsInter.length]);
        continue;
      }
      final from = junctions[vertices.id(ring[a * 2], ring[a * 2 + 1])]!;
      final to = junctions[vertices.id(ring[b * 2], ring[b * 2 + 1])]!;
      final start = from.connectorFor(state);
      final end = to.connectorFor(state);
      if (start == null || end == null) {
        errors.add('${shape.name}: no connector at ${degrees(ring[a * 2])},'
            '${degrees(ring[a * 2 + 1])}');
        return null;
      }
      final path = _path(state, start.point, end.point,
          lineMidpoint(_cyclicSlice(ring, a, b)));
      if (path == null) {
        errors.add('${shape.name}: no OpenStreetMap $state border from '
            '${degrees(start.point[0])},${degrees(start.point[1])} to '
            '${degrees(end.point[0])},${degrees(end.point[1])} (between '
            '${users.join(' and ')})');
        return null;
      }
      out.addAll(start.via);
      out.addAll(path);
      out.addAll(reversedLine(end.via));
    }
    return out.close();
  }

  void _emitKept(_Output out, List<int> ring, int a, int b, String state,
      {required bool afterInter, required bool beforeInter}) {
    final count = ring.length ~/ 2;
    _Junction? junctionAt(int index) =>
        junctions[vertices.id(ring[index * 2], ring[index * 2 + 1])];
    final startConnector =
        junctionAt(a)?.connectorFor(state, borrow: afterInter);
    final endConnector =
        junctionAt(b)?.connectorFor(state, borrow: beforeInter);
    final dropped = <int>{
      ...?startConnector?.dropped,
      ...?endConnector?.dropped,
    };
    void emit(int index) => out.add(ring[index * 2], ring[index * 2 + 1]);
    bool kept(int index) =>
        !dropped.contains(vertices.id(ring[index * 2], ring[index * 2 + 1]));
    if (!afterInter) {
      emit(a);
      if (startConnector != null && startConnector.dropped.isNotEmpty) {
        out.add(startConnector.point[0], startConnector.point[1]);
      }
    } else if (kept(a)) {
      emit(a);
    }
    for (var i = (a + 1) % count; i != b; i = (i + 1) % count) {
      if (kept(i)) emit(i);
    }
    if (a == b) return;
    if (!beforeInter) {
      if (endConnector != null && endConnector.dropped.isNotEmpty) {
        out.add(endConnector.point[0], endConnector.point[1]);
      }
      emit(b);
    } else if (kept(b)) {
      emit(b);
    }
  }

  List<int>? _wholeRing(Shape shape, List<int> ring, String state) {
    final centroid = ringCentroid(ring);
    _NodedRing? best;
    var bestArea = double.infinity;
    for (final candidate in noded) {
      if (candidate.source.state != state ||
          !ringContains(candidate.points, centroid[0], centroid[1])) {
        continue;
      }
      final box = ringBounds(candidate.points);
      final area = (box[1] - box[0]).toDouble() * (box[3] - box[2]);
      if (area < bestArea) {
        bestArea = area;
        best = candidate;
      }
    }
    if (best == null) {
      errors.add('${shape.name}: no OpenStreetMap $state ring around '
          '${degrees(centroid[0])},${degrees(centroid[1])}');
      return null;
    }
    return [...best.points];
  }

  void _reportUnmatchedRings() {
    final touched = <int>{};
    for (final shape in shapes.values) {
      for (final ring in shape.rings) {
        for (var i = 0; i < ring.length; i += 2) {
          touched.add(vertexKey(ring[i], ring[i + 1]));
        }
      }
    }
    for (final ring in snapshot.rings) {
      if (ring.inner) continue;
      final points = ring.points;
      var matched = false;
      for (var i = 0; i < points.length && !matched; i += 2) {
        matched = touched.contains(vertexKey(points[i], points[i + 1]));
      }
      if (matched) continue;
      final centroid = ringCentroid(points);
      for (final shape in shapes.values) {
        if (stateOf(shape.id) == ring.state) continue;
        var inside = shape.contains(centroid[0], centroid[1]);
        for (var i = 0; i < points.length && !inside; i += 2) {
          inside = shape.contains(points[i], points[i + 1]);
        }
        if (!inside) continue;
        errors.add('OpenStreetMap ${ring.state} ring around '
            '${degrees(centroid[0])},${degrees(centroid[1])} lies inside '
            '${shape.name} and no districts.csv row covers it');
      }
    }
  }
}

class _Output {
  final List<int> points = [];

  void add(int lat, int lon) {
    if (points.length >= 2 &&
        points[points.length - 2] == lat &&
        points.last == lon) {
      return;
    }
    points
      ..add(lat)
      ..add(lon);
  }

  void addAll(List<int> line) {
    for (var i = 0; i < line.length; i += 2) {
      add(line[i], line[i + 1]);
    }
  }

  List<int> close() {
    if (points.length >= 4 &&
        points[0] == points[points.length - 2] &&
        points[1] == points.last) {
      points.removeRange(points.length - 2, points.length);
    }
    return points;
  }
}

void stitchStateBorders({
  required Map<String, Shape> shapes,
  required Map<String, String> shapeStates,
  required OsmSnapshot snapshot,
  required List<String> errors,
}) =>
    _Stitcher(shapes, shapeStates, snapshot, errors).run();

Shape? osmShape(
    OsmSnapshot snapshot, String id, String name, List<String> errors) {
  final match = RegExp(r'^(MY-\d\d)@(-?[\d.]+)/(-?[\d.]+)$').firstMatch(id);
  if (match == null) return null;
  final lat = (double.parse(match.group(2)!) * 100000).round();
  final lon = (double.parse(match.group(3)!) * 100000).round();
  final rings = [
    for (final ring in snapshot.rings)
      if (ring.iso == match.group(1) && ring.contains(lat, lon)) ring
  ];
  if (rings.length != 1) {
    errors.add('$name: ${rings.length} OpenStreetMap ${match.group(1)} rings '
        'contain ${match.group(2)},${match.group(3)}');
    return null;
  }
  return Shape(id, name, [
    [...rings.single.points]
  ]);
}

void cutOsmShapes({
  required Map<String, Shape> shapes,
  required Map<String, String> shapeStates,
  required Iterable<String> osmShapeIds,
  required List<String> errors,
}) {
  for (final id in osmShapeIds) {
    final enclave = shapes[id]!;
    final state = shapeStates[id]!;
    for (final host in shapes.values) {
      if (host.id == id) continue;
      final crossings = <List<int>>[];
      for (final ring in enclave.rings) {
        for (final hostRing in host.rings) {
          crossings.addAll(_ringCrossings(ring, hostRing));
        }
      }
      final inside = crossings.isEmpty &&
          host.contains(enclave.rings.first[0], enclave.rings.first[1]);
      if (crossings.isEmpty && !inside) continue;
      if (shapeStates[host.id] == state) {
        errors.add('${enclave.name} overlaps ${host.name} of the same state');
        continue;
      }
      if (inside) {
        host.rings.add([...enclave.rings.first]);
        continue;
      }
      _cutRun(enclave, host, errors);
    }
  }
}

List<List<int>> _ringCrossings(List<int> a, List<int> b) {
  final found = <List<int>>[];
  for (var i = 0, j = a.length - 2; i < a.length; j = i, i += 2) {
    for (var k = 0, l = b.length - 2; k < b.length; l = k, k += 2) {
      final crossing = segmentIntersection(
          a[j], a[j + 1], a[i], a[i + 1], b[l], b[l + 1], b[k], b[k + 1]);
      if (crossing != null) found.add(crossing);
    }
  }
  return found;
}

List<int> _insertCrossings(List<int> ring, List<List<int>> crossings) {
  final out = _Output();
  for (var i = 0; i < ring.length; i += 2) {
    final j = (i + 2) % ring.length;
    out.add(ring[i], ring[i + 1]);
    final onSegment = [
      for (final c in crossings)
        if (pointSegmentMetres(
                c[0], c[1], ring[i], ring[i + 1], ring[j], ring[j + 1]) <
            1.5)
          c
    ]..sort((a, b) => metresBetween(ring[i], ring[i + 1], a[0], a[1])
        .compareTo(metresBetween(ring[i], ring[i + 1], b[0], b[1])));
    for (final c in onSegment) {
      if (c[0] == ring[j] && c[1] == ring[j + 1]) continue;
      out.add(c[0], c[1]);
    }
  }
  return out.close();
}

void _cutRun(Shape enclave, Shape host, List<String> errors) {
  for (var r = 0; r < host.rings.length; r++) {
    final enclaveRing = enclave.rings.single;
    final crossings = _ringCrossings(enclaveRing, host.rings[r]);
    if (crossings.isEmpty) continue;
    if (crossings.length.isOdd) {
      errors.add('${enclave.name} crosses ${host.name} an odd number of times');
      return;
    }
    final nodedEnclave = _insertCrossings(enclaveRing, crossings);
    final nodedHost = _insertCrossings(host.rings[r], crossings);
    enclave.rings[0] = nodedEnclave;
    final crossingKeys = {for (final c in crossings) vertexKey(c[0], c[1])};
    final hostCount = nodedHost.length ~/ 2;
    final hostJunctions = [
      for (var i = 0; i < hostCount; i++)
        if (crossingKeys
            .contains(vertexKey(nodedHost[i * 2], nodedHost[i * 2 + 1])))
          i
    ];
    final out = _Output();
    for (var k = 0; k < hostJunctions.length; k++) {
      final a = hostJunctions[k];
      final b = hostJunctions[(k + 1) % hostJunctions.length];
      final run = _cyclicSlice(nodedHost, a, b);
      final middle = lineMidpoint(run);
      if (!ringContains(nodedEnclave, middle[0], middle[1])) {
        out.addAll(run);
        continue;
      }
      final replacement = _enclavePathInside(nodedEnclave, run, host);
      if (replacement == null) {
        errors.add('${enclave.name}: no path inside ${host.name} between '
            '${degrees(run[0])},${degrees(run[1])} and '
            '${degrees(run[run.length - 2])},${degrees(run.last)}');
        return;
      }
      out.addAll(replacement);
    }
    host.rings[r] = out.close();
  }
}

List<int> _cyclicSlice(List<int> ring, int a, int b) {
  final count = ring.length ~/ 2;
  final out = <int>[];
  var i = a;
  while (true) {
    out
      ..add(ring[i * 2])
      ..add(ring[i * 2 + 1]);
    if (i == b) break;
    i = (i + 1) % count;
  }
  return out;
}

List<int>? _enclavePathInside(List<int> enclave, List<int> run, Shape host) {
  final count = enclave.length ~/ 2;
  int? from;
  int? to;
  for (var i = 0; i < count; i++) {
    if (enclave[i * 2] == run[0] && enclave[i * 2 + 1] == run[1]) from = i;
    if (enclave[i * 2] == run[run.length - 2] &&
        enclave[i * 2 + 1] == run.last) {
      to = i;
    }
  }
  if (from == null || to == null) return null;
  for (final candidate in [
    _cyclicSlice(enclave, from, to),
    reversedLine(_cyclicSlice(enclave, to, from)),
  ]) {
    final middle = lineMidpoint(candidate);
    if (candidate.length >= 6 && host.contains(middle[0], middle[1])) {
      return candidate;
    }
  }
  return null;
}
