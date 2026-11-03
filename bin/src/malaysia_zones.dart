import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:adhan/src/data/malaysia_zones_data.dart';

import 'csv.dart';
import 'malaysia_manifest.dart';

const geoBoundariesFile = 'geoBoundaries-MYS-ADM2_simplified.geojson.gz';
const geoBoundariesUrl =
    'https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/MYS/ADM2/geoBoundaries-MYS-ADM2_simplified.geojson';
const geoBoundariesRetrieved = '2026-11-03';
const simplifyToleranceMetres = 100.0;
const overlapGridStepDegrees = 0.02;

String? lookupZone(double latitude, double longitude, DateComponents date) =>
    MalaysiaZoneMap.parse(malaysiaZonesData).zoneAt(latitude, longitude, date);

DataBuild buildZones(Directory root) {
  final tool = '${root.path}/tool/malaysia';
  final errors = <String>[];
  final zones = readCsv(File('$tool/zones.csv'));
  final districts = readCsv(File('$tool/districts.csv'));
  final specialAreas = readCsv(File('$tool/special_areas.csv'));
  final fixtures = readCsv(File('$tool/town_fixtures.csv'));
  final zoneCodes = {for (final zone in zones) zone['code']!};

  for (final zone in zones) {
    for (final successor in zone['successors']!.split(' ')) {
      if (successor.isNotEmpty && !zoneCodes.contains(successor)) {
        errors.add('zones.csv ${zone['code']}: unknown successor $successor');
      }
    }
  }
  for (final area in specialAreas) {
    if (!zoneCodes.contains(area['zone'])) {
      errors.add(
          'special_areas.csv ${area['name']}: unknown zone ${area['zone']}');
    }
  }

  final geoJsonBytes = GZipCodec()
      .decode(File('$tool/raw/$geoBoundariesFile').readAsBytesSync());
  final shapes = _readShapes(utf8.decode(geoJsonBytes));
  final rowsByShape = <String, List<String>>{};
  for (final row in districts) {
    final district = 'districts.csv ${row['district']}';
    if (!zoneCodes.contains(row['zone'])) {
      errors.add('$district: unknown zone ${row['zone']}');
    }
    if (!shapes.containsKey(row['shape_id'])) {
      errors.add('$district: unknown shape ${row['shape_id']}');
      continue;
    }
    String rule;
    try {
      rule = _normalizeRule(row['rule']!);
    } on FormatException catch (e) {
      errors.add('$district: ${e.message}');
      continue;
    }
    rowsByShape
        .putIfAbsent(row['shape_id']!, () => [])
        .add(rule.isEmpty ? row['zone']! : '${row['zone']}:$rule');
  }
  for (final shape in shapes.values) {
    if (!rowsByShape.containsKey(shape.id)) {
      errors.add('districts.csv: no row for shape ${shape.id} ${shape.name}');
    }
  }
  if (errors.isNotEmpty) return DataBuild('', errors, [], 'zones: not built');

  final points = _Points();
  final regions = _mergeRegions(districts, rowsByShape, shapes, points);
  final arcs = _buildArcs(regions, points);
  final output = StringBuffer();
  for (final zone in zones) {
    output.writeln([
      'Z',
      zone['code'],
      zone['state'],
      zone['areas'],
      zone['valid_from'],
      zone['valid_to'],
      zone['successors'],
      zone['reference_lat'],
      zone['reference_lon'],
    ].join('\t'));
  }
  for (final area in specialAreas) {
    output.writeln([
      'S',
      area['zone'],
      area['name'],
      area['lat'],
      area['lon'],
      area['radius_m'],
    ].join('\t'));
  }
  for (final arc in arcs) {
    output.writeln('A\t${MalaysiaZoneMap.encodePolyline(arc)}');
  }
  for (final region in regions) {
    output
        .writeln('R\t${region.arcIndices.join(' ')}\t${region.rows.join(' ')}');
  }

  final map = MalaysiaZoneMap.parse(output.toString());
  var resolved = 0;
  for (final fixture in fixtures) {
    final date = fixture['date']!.split('-').map(int.parse).toList();
    final latitude = double.parse(fixture['lat']!);
    final longitude = double.parse(fixture['lon']!);
    final expected = fixture['zone']!.isEmpty ? null : fixture['zone'];
    final actual = map.zoneAt(
        latitude, longitude, DateComponents(date[0], date[1], date[2]));
    if (actual != expected) {
      errors.add('fixture ${fixture['place']} ${fixture['date']} '
          '$latitude,$longitude expected ${expected ?? 'none'}, '
          'got ${actual ?? 'none'}');
    } else {
      resolved++;
    }
    final containing = map.regionsAt(latitude, longitude);
    if (containing.length > 1) {
      errors.add('fixture ${fixture['place']} lies in ${containing.length} '
          'regions: ${containing.map((i) => regions[i].label).join(', ')}');
    }
  }
  errors.addAll(_gridOverlaps(map, regions).map((line) => 'overlap $line'));

  final summary = '${zones.length} zones, ${shapes.length} districts in '
      '${regions.length} regions, ${specialAreas.length} special areas, '
      '${arcs.length} arcs, $resolved fixtures resolved';
  return DataBuild(
      output.toString(),
      errors,
      [
        ManifestEntry('geoboundaries', 'MYS ADM2 simplified 9469f09',
            geoBoundariesRetrieved, geoBoundariesUrl, sha256Hex(geoJsonBytes)),
      ],
      summary);
}

String _normalizeRule(String rule) {
  final compact = rule.replaceAll(' ', '');
  if (compact.isEmpty) return '';
  final pattern = RegExp(r'^(lat|lon)(<=|>=|<|>)(-?\d+(\.\d+)?)$');
  for (final part in compact.split('&')) {
    if (!pattern.hasMatch(part)) throw FormatException('malformed rule $rule');
  }
  return compact;
}

class _Shape {
  final String id;
  final String name;
  final List<List<int>> rings;

  _Shape(this.id, this.name, this.rings);
}

Map<String, _Shape> _readShapes(String geoJson) {
  final features = (json.decode(geoJson) as Map)['features'] as List;
  final shapes = <String, _Shape>{};
  for (final feature in features) {
    final properties = feature['properties'] as Map;
    final geometry = feature['geometry'] as Map;
    final polygons = geometry['type'] == 'MultiPolygon'
        ? geometry['coordinates'] as List
        : [geometry['coordinates']];
    final rings = <List<int>>[];
    for (final polygon in polygons) {
      for (final ring in polygon as List) {
        final quantized = <int>[];
        for (final point in ring as List) {
          final lat = MalaysiaZoneMap.quantize((point[1] as num).toDouble());
          final lon = MalaysiaZoneMap.quantize((point[0] as num).toDouble());
          final n = quantized.length;
          if (n >= 2 && quantized[n - 2] == lat && quantized[n - 1] == lon) {
            continue;
          }
          quantized
            ..add(lat)
            ..add(lon);
        }
        final n = quantized.length;
        if (n >= 4 &&
            quantized[0] == quantized[n - 2] &&
            quantized[1] == quantized[n - 1]) {
          quantized.removeRange(n - 2, n);
        }
        if (quantized.length >= 6) rings.add(quantized);
      }
    }
    final id = properties['shapeID'] as String;
    shapes[id] = _Shape(id, properties['shapeName'] as String, rings);
  }
  return shapes;
}

class _Region {
  final List<String> rows;
  final List<String> shapeNames = [];
  final Set<int> segments = {};
  final List<int> arcIndices = [];

  _Region(this.rows);

  String get label => shapeNames.join('+');
}

const int _idStride = 1 << 22;

class _Points {
  final Map<int, int> _ids = {};
  final List<int> lats = [];
  final List<int> lons = [];

  int id(int lat, int lon) =>
      _ids.putIfAbsent((lat + 10000000) * (1 << 26) + lon, () {
        lats.add(lat);
        lons.add(lon);
        if (lats.length >= _idStride) throw StateError('too many vertices');
        return lats.length - 1;
      });

  int segment(int a, int b) => a < b ? a * _idStride + b : b * _idStride + a;
}

List<_Region> _mergeRegions(
    List<Map<String, String>> districts,
    Map<String, List<String>> rowsByShape,
    Map<String, _Shape> shapes,
    _Points points) {
  final regionsByRows = <String, _Region>{};
  final regions = <_Region>[];
  final seen = <String>{};
  for (final row in districts) {
    final shapeId = row['shape_id']!;
    if (!seen.add(shapeId)) continue;
    final rows = rowsByShape[shapeId]!;
    final region = regionsByRows.putIfAbsent(rows.join(' '), () {
      final created = _Region(rows);
      regions.add(created);
      return created;
    });
    final shape = shapes[shapeId]!;
    region.shapeNames.add(shape.name);
    for (final ring in shape.rings) {
      for (var i = 0; i < ring.length; i += 2) {
        final j = (i + 2) % ring.length;
        final key = points.segment(
            points.id(ring[i], ring[i + 1]), points.id(ring[j], ring[j + 1]));
        if (!region.segments.remove(key)) region.segments.add(key);
      }
    }
  }
  return regions;
}

List<List<int>> _buildArcs(List<_Region> regions, _Points points) {
  final regionsBySegment = <int, String>{};
  final usersBySegment = <int, List<int>>{};
  for (var r = 0; r < regions.length; r++) {
    for (final segment in regions[r].segments) {
      usersBySegment.putIfAbsent(segment, () => []).add(r);
    }
  }
  usersBySegment.forEach((segment, users) {
    regionsBySegment[segment] = users.join(',');
  });
  final segmentsByNode = <int, List<int>>{};
  for (final segment in usersBySegment.keys) {
    segmentsByNode.putIfAbsent(segment ~/ _idStride, () => []).add(segment);
    segmentsByNode.putIfAbsent(segment % _idStride, () => []).add(segment);
  }
  bool isJunction(int node) {
    final incident = segmentsByNode[node]!;
    return incident.length != 2 ||
        regionsBySegment[incident[0]] != regionsBySegment[incident[1]];
  }

  int opposite(int segment, int node) =>
      segment ~/ _idStride == node ? segment % _idStride : segment ~/ _idStride;
  int nextSegment(int node, int segment) {
    final incident = segmentsByNode[node]!;
    return incident[0] == segment ? incident[1] : incident[0];
  }

  final arcs = <List<int>>[];
  final visited = <int>{};
  final orderedSegments = usersBySegment.keys.toList()..sort();
  for (final start in orderedSegments) {
    if (visited.contains(start)) continue;
    var node = start ~/ _idStride;
    var segment = start;
    if (!isJunction(node) && !isJunction(start % _idStride)) {
      var probe = start % _idStride;
      var probeSegment = start;
      while (true) {
        probe = opposite(probeSegment, probe);
        if (isJunction(probe) || probe == start % _idStride) break;
        probeSegment = nextSegment(probe, probeSegment);
      }
      node = probe;
      segment = probeSegment;
    } else if (!isJunction(node)) {
      node = start % _idStride;
    }
    final nodes = <int>[node];
    while (true) {
      visited.add(segment);
      node = opposite(segment, node);
      nodes.add(node);
      if (isJunction(node) || node == nodes.first) break;
      segment = nextSegment(node, segment);
      if (visited.contains(segment)) break;
    }
    final vertices = <int>[];
    for (final n in nodes) {
      vertices
        ..add(points.lats[n])
        ..add(points.lons[n]);
    }
    for (final r in usersBySegment[start]!) {
      regions[r].arcIndices.add(arcs.length);
    }
    arcs.add(_simplify(vertices));
  }
  return arcs;
}

List<int> _simplify(List<int> points) {
  final count = points.length ~/ 2;
  if (count <= 2) return points;
  final closed = points[0] == points[points.length - 2] &&
      points[1] == points[points.length - 1];
  if (closed && count > 3) {
    var farthest = 1;
    var farthestDistance = -1.0;
    for (var i = 1; i < count - 1; i++) {
      final d = _metres(points, 0, i);
      if (d > farthestDistance) {
        farthestDistance = d;
        farthest = i;
      }
    }
    final head = _simplify(points.sublist(0, farthest * 2 + 2));
    final tail = _simplify(points.sublist(farthest * 2));
    return [...head, ...tail.sublist(2)];
  }
  final keep = List<bool>.filled(count, false);
  keep[0] = true;
  keep[count - 1] = true;
  final stack = <List<int>>[
    [0, count - 1]
  ];
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    var worst = -1;
    var worstDistance = simplifyToleranceMetres;
    for (var i = range[0] + 1; i < range[1]; i++) {
      final d = _segmentDistanceMetres(points, range[0], range[1], i);
      if (d > worstDistance) {
        worstDistance = d;
        worst = i;
      }
    }
    if (worst >= 0) {
      keep[worst] = true;
      stack
        ..add([range[0], worst])
        ..add([worst, range[1]]);
    }
  }
  return [
    for (var i = 0; i < count; i++)
      if (keep[i]) ...[points[i * 2], points[i * 2 + 1]]
  ];
}

double _lonScale(List<int> points, int i) =>
    111320 * math.cos(points[i * 2] / 100000 * math.pi / 180) / 100000;

const double _latScale = 110574 / 100000;

double _metres(List<int> points, int i, int j) {
  final dy = (points[j * 2] - points[i * 2]) * _latScale;
  final dx = (points[j * 2 + 1] - points[i * 2 + 1]) * _lonScale(points, i);
  return math.sqrt(dx * dx + dy * dy);
}

double _segmentDistanceMetres(List<int> points, int a, int b, int p) {
  final lonScale = _lonScale(points, a);
  final ax = points[a * 2 + 1] * lonScale;
  final ay = points[a * 2] * _latScale;
  final bx = points[b * 2 + 1] * lonScale;
  final by = points[b * 2] * _latScale;
  final px = points[p * 2 + 1] * lonScale;
  final py = points[p * 2] * _latScale;
  final dx = bx - ax;
  final dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) {
    return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  }
  var t = ((px - ax) * dx + (py - ay) * dy) / lengthSquared;
  t = t < 0 ? 0 : (t > 1 ? 1 : t);
  final qx = ax + t * dx;
  final qy = ay + t * dy;
  return math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
}

List<String> _gridOverlaps(MalaysiaZoneMap map, List<_Region> regions) {
  final found = <String, int>{};
  for (var lat = 0.8; lat <= 7.5; lat += overlapGridStepDegrees) {
    for (var lon = 99.5; lon <= 119.5; lon += overlapGridStepDegrees) {
      final containing = map.regionsAt(lat, lon);
      if (containing.length > 1) {
        final key = containing.map((i) => regions[i].label).join(' & ');
        found[key] = (found[key] ?? 0) + 1;
      }
    }
  }
  final keys = found.keys.toList()..sort();
  return [for (final key in keys) '${found[key]} grid points in $key'];
}
