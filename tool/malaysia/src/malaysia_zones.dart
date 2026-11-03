import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:adhan/src/data/malaysia_zones_data.dart';

import 'csv.dart';
import 'malaysia_manifest.dart';

const geoBoundariesRelease = '9469f09';
const geoBoundariesRetrieved = '2026-11-03';
const simplifyToleranceMetres = 100.0;
const overlapGridStepDegrees = 0.02;
const specialAreaReachLimitMetres = 500.0;
const specialAreaGridStepMetres = 100.0;

String _geoBoundariesFile(String level) =>
    'geoBoundaries-MYS-${level}_simplified.geojson';

String _geoBoundariesUrl(String level) =>
    'https://github.com/wmgeolab/geoBoundaries/raw/$geoBoundariesRelease/'
    'releaseData/gbOpen/MYS/$level/${_geoBoundariesFile(level)}';

String? lookupZone(double latitude, double longitude, DateComponents date) =>
    MalaysiaZoneMap.parse(malaysiaZonesData).zoneAt(latitude, longitude, date);

DataBuild buildZones(Directory root) {
  final tool = '${root.path}/tool/malaysia';
  final errors = <String>[];
  final zones = readCsv(File('$tool/zones.csv'));
  final districts = readCsv(File('$tool/districts.csv'));
  final specialAreas = readCsv(File('$tool/special_areas.csv'));
  final islands = readCsv(File('$tool/islands.csv'));
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

  final sources = <ManifestEntry>[];
  Map<String, _Shape> readLevel(String level) {
    final bytes = GZipCodec().decode(
        File('$tool/raw/${_geoBoundariesFile(level)}.gz').readAsBytesSync());
    sources.add(ManifestEntry(
        'geoboundaries',
        'MYS $level simplified $geoBoundariesRelease',
        geoBoundariesRetrieved,
        _geoBoundariesUrl(level),
        sha256Hex(bytes)));
    return _readShapes(utf8.decode(bytes));
  }

  final adm2 = readLevel('ADM2');
  final adm1 = readLevel('ADM1');
  final shapes = <String, _Shape>{...adm2};
  final shapeIdsByDistrict = <String, String>{};
  final rowsByShape = <String, List<String>>{};
  for (final row in districts) {
    final district = 'districts.csv ${row['district']}';
    if (!zoneCodes.contains(row['zone'])) {
      errors.add('$district: unknown zone ${row['zone']}');
    }
    final shape = adm2[row['shape_id']] ?? adm1[row['shape_id']];
    if (shape == null) {
      errors.add('$district: unknown shape ${row['shape_id']}');
      continue;
    }
    shapes[shape.id] = shape;
    shapeIdsByDistrict[row['district']!] = shape.id;
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
  for (final shape in adm2.values) {
    if (!rowsByShape.containsKey(shape.id)) {
      errors.add('districts.csv: no row for shape ${shape.id} ${shape.name}');
    }
  }
  String? shapeIdOf(String file, String name, String district) {
    final id = shapeIdsByDistrict[district];
    if (id == null) errors.add('$file $name: unknown district $district');
    return id;
  }

  final parentShapeIds = [
    for (final area in specialAreas)
      shapeIdOf('special_areas.csv', area['name']!, area['district']!),
  ];
  final islandShapeIds = [
    for (final island in islands)
      shapeIdOf('islands.csv', island['name']!, island['district']!),
  ];
  if (errors.isNotEmpty) return DataBuild('', errors, [], 'zones: not built');

  for (final enclave in adm1.values.where((s) => shapes.containsKey(s.id))) {
    final hosts = adm2.values.where((host) => enclave.liesInside(host));
    if (hosts.length != 1) {
      errors.add('${enclave.name} lies inside ${hosts.length} ADM2 shapes; '
          'an ADM1 shape must lie inside exactly one');
      continue;
    }
    hosts.single.rings.addAll(enclave.rings);
  }
  for (var i = 0; i < islands.length; i++) {
    final island = islands[i];
    final ring = _octagon(double.parse(island['lat']!),
        double.parse(island['lon']!), double.parse(island['radius_m']!));
    final touching = shapes.values.where((shape) => shape.touches(ring));
    if (touching.isNotEmpty) {
      errors.add('islands.csv ${island['name']}: the area touches '
          '${touching.map((shape) => shape.name).join(', ')}');
      continue;
    }
    shapes[islandShapeIds[i]]!.rings.add(ring);
  }
  if (errors.isNotEmpty) return DataBuild('', errors, [], 'zones: not built');

  final points = _Points();
  final regions = _mergeRegions(districts, rowsByShape, shapes,
      parentShapeIds.whereType<String>().toSet(), points);
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
  for (var i = 0; i < specialAreas.length; i++) {
    final area = specialAreas[i];
    output.writeln([
      'S',
      area['zone'],
      area['name'],
      area['lat'],
      area['lon'],
      area['radius_m'],
      regions
          .indexWhere((region) => region.shapeIds.contains(parentShapeIds[i])),
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
  for (var i = 0; i < map.specialAreas.length; i++) {
    errors.addAll(_specialAreaReach(
        map, map.specialAreas[i], parentShapeIds[i]!, shapes.values));
  }

  final summary = '${zones.length} zones, ${shapes.length} districts in '
      '${regions.length} regions, ${specialAreas.length} special areas, '
      '${islands.length} island areas, ${arcs.length} arcs, '
      '$resolved fixtures resolved';
  return DataBuild(output.toString(), errors, sources, summary);
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

  bool contains(int lat, int lon) {
    var inside = false;
    for (final ring in rings) {
      if (_ringContains(ring, lat, lon)) inside = !inside;
    }
    return inside;
  }

  bool liesInside(_Shape host) => rings.every((ring) =>
      host.contains(ring[0], ring[1]) &&
      !host.rings.any((hostRing) => _ringsCross(ring, hostRing)));

  bool touches(List<int> ring) =>
      contains(ring[0], ring[1]) ||
      rings.any((own) =>
          _ringsCross(own, ring) || _ringContains(ring, own[0], own[1]));

  double depthMetres(int lat, int lon) {
    var best = double.infinity;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
        best = math.min(
            best,
            _pointSegmentMetres(
                lat, lon, ring[j], ring[j + 1], ring[i], ring[i + 1]));
      }
    }
    return best;
  }

  List<int> get bounds {
    final box = [1 << 40, -(1 << 40), 1 << 40, -(1 << 40)];
    for (final ring in rings) {
      for (var i = 0; i < ring.length; i += 2) {
        box[0] = math.min(box[0], ring[i]);
        box[1] = math.max(box[1], ring[i]);
        box[2] = math.min(box[2], ring[i + 1]);
        box[3] = math.max(box[3], ring[i + 1]);
      }
    }
    return box;
  }
}

bool _ringContains(List<int> ring, int lat, int lon) {
  var inside = false;
  for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
    final lat1 = ring[j];
    final lat2 = ring[i];
    if ((lat1 > lat) == (lat2 > lat)) continue;
    final lon1 = ring[j + 1];
    final crossing = lon1 + (lat - lat1) * (ring[i + 1] - lon1) / (lat2 - lat1);
    if (lon < crossing) inside = !inside;
  }
  return inside;
}

bool _ringsCross(List<int> a, List<int> b) {
  for (var i = 0, j = a.length - 2; i < a.length; j = i, i += 2) {
    final aMinLat = math.min(a[i], a[j]);
    final aMaxLat = math.max(a[i], a[j]);
    final aMinLon = math.min(a[i + 1], a[j + 1]);
    final aMaxLon = math.max(a[i + 1], a[j + 1]);
    for (var k = 0, l = b.length - 2; k < b.length; l = k, k += 2) {
      if (math.max(b[k], b[l]) < aMinLat ||
          math.min(b[k], b[l]) > aMaxLat ||
          math.max(b[k + 1], b[l + 1]) < aMinLon ||
          math.min(b[k + 1], b[l + 1]) > aMaxLon) {
        continue;
      }
      if (_segmentsIntersect(
          a[j], a[j + 1], a[i], a[i + 1], b[l], b[l + 1], b[k], b[k + 1])) {
        return true;
      }
    }
  }
  return false;
}

int _turn(int ay, int ax, int by, int bx, int cy, int cx) =>
    ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)).sign;

bool _segmentsIntersect(
    int ay, int ax, int by, int bx, int cy, int cx, int dy, int dx) {
  final abc = _turn(ay, ax, by, bx, cy, cx);
  final abd = _turn(ay, ax, by, bx, dy, dx);
  final cda = _turn(cy, cx, dy, dx, ay, ax);
  final cdb = _turn(cy, cx, dy, dx, by, bx);
  if (abc * abd < 0 && cda * cdb < 0) return true;
  bool onSegment(int py, int px, int qy, int qx, int ry, int rx) =>
      math.min(py, qy) <= ry &&
      ry <= math.max(py, qy) &&
      math.min(px, qx) <= rx &&
      rx <= math.max(px, qx);
  return (abc == 0 && onSegment(ay, ax, by, bx, cy, cx)) ||
      (abd == 0 && onSegment(ay, ax, by, bx, dy, dx)) ||
      (cda == 0 && onSegment(cy, cx, dy, dx, ay, ax)) ||
      (cdb == 0 && onSegment(cy, cx, dy, dx, by, bx));
}

double _pointSegmentMetres(
    int lat, int lon, int lat1, int lon1, int lat2, int lon2) {
  final lonScale = 111320 * math.cos(lat / 100000 * math.pi / 180) / 100000;
  final x1 = (lon1 - lon) * lonScale;
  final y1 = (lat1 - lat) * _latScale;
  final dx = (lon2 - lon1) * lonScale;
  final dy = (lat2 - lat1) * _latScale;
  final lengthSquared = dx * dx + dy * dy;
  var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared;
  t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  final px = x1 + t * dx;
  final py = y1 + t * dy;
  return math.sqrt(px * px + py * py);
}

List<int> _octagon(double latitude, double longitude, double radiusMetres) {
  final lonMetres = 111320 * math.cos(latitude * math.pi / 180);
  return [
    for (var k = 0; k < 8; k++) ...[
      MalaysiaZoneMap.quantize(
          latitude + radiusMetres * math.cos(k * math.pi / 4) / 110574),
      MalaysiaZoneMap.quantize(
          longitude + radiusMetres * math.sin(k * math.pi / 4) / lonMetres),
    ],
  ];
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
  final List<String> shapeIds = [];
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
    Set<String> separateShapeIds,
    _Points points) {
  final regionsByKey = <String, _Region>{};
  final regions = <_Region>[];
  final seen = <String>{};
  for (final row in districts) {
    final shapeId = row['shape_id']!;
    if (!seen.add(shapeId)) continue;
    final rows = rowsByShape[shapeId]!;
    final key = separateShapeIds.contains(shapeId)
        ? '${rows.join(' ')} $shapeId'
        : rows.join(' ');
    final region = regionsByKey.putIfAbsent(key, () {
      final created = _Region(rows);
      regions.add(created);
      return created;
    });
    final shape = shapes[shapeId]!;
    region.shapeIds.add(shapeId);
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

List<String> _specialAreaReach(MalaysiaZoneMap map, MalaysiaSpecialArea area,
    String parentShapeId, Iterable<_Shape> shapes) {
  final day = math.max(map.zone(area.zone)!.validFromDay, 20000101);
  final date = DateComponents(day ~/ 10000, day ~/ 100 % 100, day % 100);
  final steps = (area.radiusMetres / specialAreaGridStepMetres).ceil();
  final latStep = specialAreaGridStepMetres / 110574;
  final lonStep = specialAreaGridStepMetres /
      (111320 * math.cos(area.latitude * math.pi / 180));
  final margin =
      MalaysiaZoneMap.quantize((steps + 1) * math.max(latStep, lonStep));
  final lat0 = MalaysiaZoneMap.quantize(area.latitude);
  final lon0 = MalaysiaZoneMap.quantize(area.longitude);
  final neighbours = shapes.where((shape) {
    if (shape.id == parentShapeId) return false;
    final box = shape.bounds;
    return box[0] <= lat0 + margin &&
        box[1] >= lat0 - margin &&
        box[2] <= lon0 + margin &&
        box[3] >= lon0 - margin;
  }).toList();
  final deepest = <String, double>{};
  for (var y = -steps; y <= steps; y++) {
    for (var x = -steps; x <= steps; x++) {
      if (x * x + y * y > steps * steps) continue;
      final latitude = area.latitude + y * latStep;
      final longitude = area.longitude + x * lonStep;
      if (map.zoneAt(latitude, longitude, date) != area.zone) continue;
      final lat = MalaysiaZoneMap.quantize(latitude);
      final lon = MalaysiaZoneMap.quantize(longitude);
      for (final shape in neighbours) {
        if (!shape.contains(lat, lon)) continue;
        final depth = shape.depthMetres(lat, lon);
        if (depth > (deepest[shape.name] ?? specialAreaReachLimitMetres)) {
          deepest[shape.name] = depth;
        }
      }
    }
  }
  return [
    for (final entry in deepest.entries)
      'special area ${area.zone} ${area.name} reaches '
          '${entry.value.round()} m into ${entry.key}',
  ];
}
