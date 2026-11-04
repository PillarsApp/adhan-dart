import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:adhan/src/data/malaysia_zone_map.dart';

import 'csv.dart';
import 'geometry.dart';

const osmSnapshotDate = '2026-11-04T00:00:00Z';
const osmSnapshotFile = 'openstreetmap-MYS-ADM4.json.gz';
const overpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

String overpassQuery(String date) =>
    '[out:json][timeout:900][maxsize:1073741824][date:"$date"];'
    'relation["boundary"="administrative"]["admin_level"="4"]'
    '["ISO3166-2"~"^MY-"];out geom;';

const osmStateNames = {
  'MY-01': 'Johor',
  'MY-02': 'Kedah',
  'MY-03': 'Kelantan',
  'MY-04': 'Melaka',
  'MY-05': 'Negeri Sembilan',
  'MY-06': 'Pahang',
  'MY-07': 'Pulau Pinang',
  'MY-08': 'Perak',
  'MY-09': 'Perlis',
  'MY-10': 'Selangor',
  'MY-11': 'Terengganu',
  'MY-12': 'Sabah',
  'MY-13': 'Sarawak',
  'MY-14': 'Wilayah Persekutuan',
  'MY-15': 'Wilayah Persekutuan',
  'MY-16': 'Wilayah Persekutuan',
};

const osmTerritoryNames = {
  'MY-14': 'Kuala Lumpur',
  'MY-15': 'Labuan',
  'MY-16': 'Putrajaya',
};

class OsmRing {
  final String iso;
  final String state;
  final bool inner;
  final List<int> points;

  OsmRing(this.iso, this.state, this.inner, this.points);

  String get territory => osmTerritoryNames[iso] ?? state;

  bool contains(int lat, int lon) => ringContains(points, lat, lon);
}

class OsmSnapshot {
  final String timestamp;
  final List<OsmRing> rings;
  final Map<int, int> _vertexIds = {};
  final Map<int, Set<String>> _statesByVertex = {};
  final Map<int, Set<String>> _statesBySegment = {};
  final Map<String, Set<int>> _ringsByState = {};
  final Map<String, Set<int>> _ringsByTerritory = {};
  final SegmentIndex _index = SegmentIndex();

  OsmSnapshot._(this.timestamp, this.rings) {
    for (var r = 0; r < rings.length; r++) {
      final ring = rings[r];
      _index.addRing(ring.points, r);
      _ringsByState.putIfAbsent(ring.state, () => {}).add(r);
      _ringsByTerritory.putIfAbsent(ring.territory, () => {}).add(r);
      final points = ring.points;
      for (var i = 0, j = points.length - 2; i < points.length; j = i, i += 2) {
        _statesByVertex
            .putIfAbsent(vertexKey(points[i], points[i + 1]), () => {})
            .add(ring.state);
        _statesBySegment
            .putIfAbsent(
                _segmentKey(points[j], points[j + 1], points[i], points[i + 1]),
                () => {})
            .add(ring.state);
      }
    }
  }

  int _vertexId(int lat, int lon) =>
      _vertexIds.putIfAbsent(vertexKey(lat, lon), () => _vertexIds.length);

  int _segmentKey(int lat1, int lon1, int lat2, int lon2) {
    final a = _vertexId(lat1, lon1);
    final b = _vertexId(lat2, lon2);
    return a < b ? a * (1 << 24) + b : b * (1 << 24) + a;
  }

  static OsmSnapshot parse(String json,
      {List<StateLineException> exceptions = const []}) {
    try {
      return _parse(json, exceptions);
    } on TypeError catch (error) {
      throw FormatException('not an Overpass response ($error)');
    }
  }

  static OsmSnapshot _parse(String json, List<StateLineException> exceptions) {
    final document = jsonDecode(json) as Map;
    if (document.containsKey('remark')) {
      throw FormatException('Overpass remark: ${document['remark']}');
    }
    final timestamp =
        (document['osm3s'] as Map)['timestamp_osm_base'] as String;
    final rings = <OsmRing>[];
    final seen = <String>{};
    for (final element in document['elements'] as List) {
      if (element['type'] != 'relation') continue;
      final iso = (element['tags'] as Map)['ISO3166-2'] as String;
      final state = osmStateNames[iso];
      if (state == null) {
        throw FormatException('unexpected OpenStreetMap relation $iso');
      }
      seen.add(iso);
      for (final role in const ['outer', 'inner']) {
        final ways = <List<int>>[];
        for (final member in element['members'] as List) {
          if (member['type'] != 'way' || member['role'] != role) continue;
          if (member['geometry'] == null) {
            throw FormatException('OpenStreetMap $iso $role way '
                '${member['ref']} has no geometry');
          }
          final way = _quantize(member['geometry'] as List);
          if (way.length >= 4) ways.add(way);
        }
        for (final ring in _assembleRings(ways, iso)) {
          rings.add(OsmRing(iso, state, role == 'inner', ring));
        }
      }
    }
    final missing = osmStateNames.keys.where((iso) => !seen.contains(iso));
    if (missing.isNotEmpty) {
      throw FormatException(
          'OpenStreetMap snapshot lacks ${missing.join(', ')}');
    }
    for (final exception in exceptions) {
      exception.applyTo(rings);
    }
    return OsmSnapshot._(timestamp, rings);
  }

  static List<int> _quantize(List geometry) {
    final points = <int>[];
    for (final node in geometry) {
      final lat = MalaysiaZoneMap.quantize((node['lat'] as num).toDouble());
      final lon = MalaysiaZoneMap.quantize((node['lon'] as num).toDouble());
      final n = points.length;
      if (n >= 2 && points[n - 2] == lat && points[n - 1] == lon) continue;
      points
        ..add(lat)
        ..add(lon);
    }
    return points;
  }

  static List<List<int>> _assembleRings(List<List<int>> ways, String iso) {
    final rings = <List<int>>[];
    final open = [...ways];
    while (open.isNotEmpty) {
      final ring = [...open.removeAt(0)];
      var extended = true;
      while (extended && !_closed(ring)) {
        extended = false;
        for (var i = 0; i < open.length; i++) {
          final way = open[i];
          if (way[0] == ring[ring.length - 2] && way[1] == ring.last) {
            ring.addAll(way.sublist(2));
          } else if (way[way.length - 2] == ring[ring.length - 2] &&
              way.last == ring.last) {
            ring.addAll(reversedLine(way).sublist(2));
          } else {
            continue;
          }
          open.removeAt(i);
          extended = true;
          break;
        }
      }
      if (!_closed(ring)) {
        throw FormatException('OpenStreetMap $iso has an unclosed ring at '
            '${degrees(ring[0])},${degrees(ring[1])}');
      }
      ring.removeRange(ring.length - 2, ring.length);
      if (ring.length >= 6) rings.add(ring);
    }
    return rings;
  }

  static bool _closed(List<int> ring) =>
      ring.length >= 4 &&
      ring[0] == ring[ring.length - 2] &&
      ring[1] == ring.last;

  Iterable<String> get states => osmStateNames.values.toSet();

  Iterable<String> get territories => _ringsByTerritory.keys;

  SegmentIndex stateLines() {
    final index = SegmentIndex();
    for (final ring in rings) {
      final points = ring.points;
      for (var i = 0, j = points.length - 2; i < points.length; j = i, i += 2) {
        if (isShared(points[j], points[j + 1], points[i], points[i + 1])) {
          index.addPolyline(
              [points[j], points[j + 1], points[i], points[i + 1]], 0);
        }
      }
    }
    return index;
  }

  late final Map<String, PolygonIndex> _territoryIndex = {
    for (final territory in territories)
      territory: PolygonIndex(
          [for (final r in _ringsByTerritory[territory]!) rings[r].points])
  };

  String? territoryAt(int lat, int lon) {
    final found = [
      for (final entry in _territoryIndex.entries)
        if (entry.value.contains(lat, lon)) entry.key
    ];
    return found.length == 1 ? found.single : null;
  }

  List<int> get bounds {
    final box = [1 << 40, -(1 << 40), 1 << 40, -(1 << 40)];
    for (final ring in rings) {
      final b = ringBounds(ring.points);
      box[0] = math.min(box[0], b[0]);
      box[1] = math.max(box[1], b[1]);
      box[2] = math.min(box[2], b[2]);
      box[3] = math.max(box[3], b[3]);
    }
    return box;
  }

  Iterable<List<int>> segmentsNear(int lat, int lon, double metres) =>
      _index.near(lat, lon, metres);

  bool crossesState(
      Set<String> states, int lat1, int lon1, int lat2, int lon2) {
    final metres = metresBetween(lat1, lon1, lat2, lon2);
    for (final s in _index.near(lat1, lon1, metres + 10)) {
      if (!states.contains(rings[s[4]].state)) continue;
      if (segmentsCross(lat1, lon1, lat2, lon2, s[0], s[1], s[2], s[3])) {
        return true;
      }
    }
    return false;
  }

  static String canonicalSegment(int lat1, int lon1, int lat2, int lon2) {
    final a = vertexKey(lat1, lon1);
    final b = vertexKey(lat2, lon2);
    return a < b ? '$a:$b' : '$b:$a';
  }

  List<OsmRing> ringsOf(String state) =>
      [for (final r in _ringsByState[state] ?? const <int>{}) rings[r]];

  String? stateAt(int lat, int lon) {
    String? found;
    for (final state in states) {
      var inside = false;
      for (final ring in ringsOf(state)) {
        if (ring.contains(lat, lon)) inside = !inside;
      }
      if (inside) {
        if (found != null) return null;
        found = state;
      }
    }
    return found;
  }

  Set<String> statesOfSegment(int lat1, int lon1, int lat2, int lon2) =>
      _statesBySegment[_segmentKey(lat1, lon1, lat2, lon2)] ?? const {};

  Set<String> statesOfVertex(int lat, int lon) =>
      _statesByVertex[vertexKey(lat, lon)] ?? const {};

  bool isShared(int lat1, int lon1, int lat2, int lon2) =>
      statesOfSegment(lat1, lon1, lat2, lon2).length >= 2;

  double depthMetres(String territory, int lat, int lon) {
    final owners = _ringsByTerritory[territory] ?? const <int>{};
    var best = double.infinity;
    var radius = 2000.0;
    while (best == double.infinity && radius < 3000000) {
      for (final s in _index.near(lat, lon, radius)) {
        if (!owners.contains(s[4])) continue;
        final d = pointSegmentMetres(lat, lon, s[0], s[1], s[2], s[3]);
        if (d < best) best = d;
      }
      radius *= 2;
    }
    return best;
  }
}

const stateLineExceptionsFile = 'state_line_exceptions.csv';
const stateLinePathEndMetres = 2.0;

List<StateLineException> readStateLineExceptions(String tool) => [
      for (final row in readCsv(File('$tool/$stateLineExceptionsFile')))
        StateLineException.parse(row)
    ];

class StateLineException {
  final String name;
  final String from;
  final String to;
  final List<int> path;

  StateLineException(this.name, this.from, this.to, this.path);

  static StateLineException parse(Map<String, String> row) {
    final path = <int>[];
    for (final point in row['path']!.split(';')) {
      final parts = point.trim().split(' ');
      if (parts.length != 2) {
        throw FormatException(
            'state_line_exceptions.csv ${row['name']}: bad point $point');
      }
      path
        ..add(MalaysiaZoneMap.quantize(double.parse(parts[0])))
        ..add(MalaysiaZoneMap.quantize(double.parse(parts[1])));
    }
    if (path.length < 6) {
      throw FormatException('state_line_exceptions.csv ${row['name']}: '
          'the path needs two ends and a point between');
    }
    return StateLineException(row['name']!, row['from']!, row['to']!, path);
  }

  void applyTo(List<OsmRing> rings) {
    final runs = <List<int>>[];
    for (final territory in [from, to]) {
      final matches = <OsmRing>[];
      for (final ring in rings) {
        if (ring.territory != territory) continue;
        final points = ring.points;
        final start = _insertNear(points, path[0], path[1]);
        final end = _insertNear(points, path[path.length - 2], path.last);
        if (start == null || end == null) continue;
        matches.add(ring);
        final run = _shorterRun(points, start, end);
        runs.add(run);
        _replaceRun(points, start, end, run);
      }
      if (matches.length != 1) {
        throw FormatException('state_line_exceptions.csv $name: '
            '${matches.length} $territory rings hold both ends of the path');
      }
    }
    final fromRun = {
      for (var i = 0; i < runs[0].length; i += 2)
        vertexKey(runs[0][i], runs[0][i + 1])
    };
    final toRun = {
      for (var i = 0; i < runs[1].length; i += 2)
        vertexKey(runs[1][i], runs[1][i + 1])
    };
    if (fromRun.length != toRun.length || !fromRun.containsAll(toRun)) {
      throw FormatException('state_line_exceptions.csv $name: the path does '
          'not replace a stretch of the line between $from and $to');
    }
  }

  int? _insertNear(List<int> points, int lat, int lon) {
    for (var i = 0; i < points.length; i += 2) {
      if (points[i] == lat && points[i + 1] == lon) return i;
    }
    for (var i = 0; i < points.length; i += 2) {
      final j = (i + 2) % points.length;
      if (pointSegmentMetres(
              lat, lon, points[i], points[i + 1], points[j], points[j + 1]) <=
          stateLinePathEndMetres) {
        points.insertAll(i + 2, [lat, lon]);
        return i + 2;
      }
    }
    return null;
  }

  List<int> _shorterRun(List<int> points, int start, int end) {
    List<int> walk(int from, int to) {
      final run = <int>[];
      for (var i = from; i != to; i = (i + 2) % points.length) {
        run
          ..add(points[i])
          ..add(points[i + 1]);
      }
      return run..addAll([points[to], points[to + 1]]);
    }

    double length(List<int> run) {
      var total = 0.0;
      for (var i = 2; i < run.length; i += 2) {
        total += metresBetween(run[i - 2], run[i - 1], run[i], run[i + 1]);
      }
      return total;
    }

    final forward = walk(start, end);
    final backward = walk(end, start);
    return length(forward) <= length(backward) ? forward : backward;
  }

  void _replaceRun(List<int> points, int start, int end, List<int> run) {
    final forward = run[0] == points[start] && run[1] == points[start + 1];
    final interior = path.sublist(2, path.length - 2);
    final replacement = forward ? interior : reversedLine(interior);
    final first = forward ? start : end;
    final removed = run.length ~/ 2 - 2;
    final rotated = [
      ...points.sublist(first),
      ...points.sublist(0, first),
    ];
    final rebuilt = [
      ...rotated.sublist(0, 2),
      ...replacement,
      ...rotated.sublist(2 + removed * 2),
    ];
    points
      ..clear()
      ..addAll(rebuilt);
  }
}
