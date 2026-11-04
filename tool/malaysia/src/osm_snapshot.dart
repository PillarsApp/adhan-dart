import 'dart:convert';

import 'package:adhan/src/data/malaysia_zone_map.dart';

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

class OsmRing {
  final String iso;
  final String state;
  final bool inner;
  final List<int> points;

  OsmRing(this.iso, this.state, this.inner, this.points);

  bool contains(int lat, int lon) => ringContains(points, lat, lon);
}

class OsmSnapshot {
  final String timestamp;
  final List<OsmRing> rings;
  final Map<int, int> _vertexIds = {};
  final Map<int, Set<String>> _statesByVertex = {};
  final Map<int, Set<String>> _statesBySegment = {};
  final Map<String, Set<int>> _ringsByState = {};
  final SegmentIndex _index = SegmentIndex();

  OsmSnapshot._(this.timestamp, this.rings) {
    for (var r = 0; r < rings.length; r++) {
      final ring = rings[r];
      _index.addRing(ring.points, r);
      _ringsByState.putIfAbsent(ring.state, () => {}).add(r);
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

  static OsmSnapshot parse(String json) {
    final document = jsonDecode(json) as Map;
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
          if (member['type'] != 'way' ||
              member['role'] != role ||
              member['geometry'] == null) {
            continue;
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

  double depthMetres(String state, int lat, int lon) {
    final owners = _ringsByState[state] ?? const <int>{};
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
