import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_times_codec.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:adhan/src/data/malaysia_zones_data.dart';

import 'border_simplify.dart';
import 'csv.dart';
import 'geometry.dart';
import 'gzip_input.dart';
import 'malaysia_manifest.dart';
import 'malaysia_states.dart';
import 'osm_extract.dart';
import 'osm_snapshot.dart';
import 'stitch_borders.dart';

const geoBoundariesRelease = '9469f09';
const geoBoundariesRetrieved = '2026-11-03';
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

class ZoneCheck {
  final List<String> lines;
  final bool failed;

  ZoneCheck(this.lines, this.failed);
}

ZoneCheck checkZones(Directory root, File zonesFile) {
  final tool = '${root.path}/tool/malaysia';
  final errors = <String>[];
  final layers = _Layers.read(tool, errors);
  final dates = _readCatalogDates(tool, errors);
  final snapshot = layers.snapshot;
  if (errors.isNotEmpty || snapshot == null) return ZoneCheck(errors, true);
  final ShippedZoneMap shipped;
  try {
    shipped = ShippedZoneMap.parse(zonesFile.readAsStringSync());
  } on FileSystemException catch (error) {
    return ZoneCheck([
      '${zonesFile.path} cannot be read '
          '(${error.osError?.message ?? error.message})'
    ], true);
  } on FormatException catch (error) {
    return ZoneCheck(
        ['${zonesFile.path} is not a zones file (${error.message})'], true);
  } on ArgumentError catch (error) {
    return ZoneCheck(['${zonesFile.path} is not a zones file ($error)'], true);
  }
  final report = _ZoneReport(shipped, layers, snapshot,
      BorderFeatures(layers.border, snapshot, dates), dates);
  return ZoneCheck([
    ...report.lines,
    '${zonesFile.path}: ${report.summary}',
  ], report.failed);
}

List<DateComponents> _readCatalogDates(String tool, List<String> errors) {
  final file = '$tool/zones.csv';
  final List<Map<String, String>> zones;
  try {
    zones = readCsv(File(file), columns: const ['valid_from', 'valid_to']);
  } on FormatException catch (error) {
    errors.add(error.message);
    return const [];
  }
  try {
    return catalogDates(zones);
  } on FormatException catch (error) {
    errors.add('$file has a malformed date (${error.message})');
  } on ArgumentError catch (error) {
    errors.add('$file has a malformed date ($error)');
  }
  return const [];
}

class _ZoneReport {
  late final List<MismatchArea> areas;
  late final List<MismatchArea> offMap;
  late final List<BorderPoint> borderWrong;
  late final List<String> stale;
  final OsmSnapshot snapshot;
  final BorderFeatures border;

  _ZoneReport(ShippedZoneMap shipped, _Layers layers, this.snapshot,
      this.border, List<DateComponents> dates) {
    areas = findStateMismatches(
        shipped: shipped, snapshot: snapshot, land: layers.land, dates: dates);
    offMap = offMapWithoutZone(shipped.map, layers.offMap, snapshot, dates);
    stale = applyNoZoneExceptions(offMap, layers.noZoneAreas);
    borderWrong = border.wrongPoints(shipped.map);
  }

  List<String> get _failing => [
        ...border.failures(borderWrong),
        for (final area in [...areas, ...offMap])
          if (area.fails) '${_label(area)} ${area.describe()}',
      ];

  bool get failed => _failing.isNotEmpty;

  List<String> get lines => [
        ...border.failures(borderWrong),
        for (final area in [...areas, ...offMap])
          '${_label(area)} ${area.describe()}',
        ...stale,
      ];

  List<String> get failures => [..._failing, ...stale];

  String get summary {
    final known = offMap.where((area) => area.exception != null);
    return '${border.describe(borderWrong)}, '
        '${describeStateCheck(snapshot, areas)}, '
        '${offMap.fold<int>(0, (sum, area) => sum + area.points)} '
        'OpenStreetMap features off the map in ${offMap.length} areas with no '
        'zone, ${known.length} of them named in $noZoneAreasFile';
  }
}

String _label(MismatchArea area) => area.noZone
    ? 'no zone'
    : area.snappedOnly
        ? 'snap only'
        : 'state mismatch';

DataBuild buildZones(Directory root, List<MalaysiaZoneYear> zoneYears) {
  final tool = '${root.path}/tool/malaysia';
  final errors = <String>[];
  List<Map<String, String>> read(String name) {
    try {
      return readCsv(File('$tool/$name'));
    } on FormatException catch (error) {
      errors.add(error.message);
      return const [];
    }
  }

  final zones = read('zones.csv');
  final districts = read('districts.csv');
  final specialAreas = read('special_areas.csv');
  final islands = read('islands.csv');
  final fixtures = read('town_fixtures.csv');
  if (errors.isNotEmpty) return DataBuild('', errors, [], 'zones: not built');
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

  final layers = _Layers.read(tool, errors);
  final adm2 = layers.adm2;
  final snapshot = layers.snapshot;
  if (errors.isNotEmpty || snapshot == null) {
    return DataBuild('', errors, [], 'zones: not built');
  }
  final shapes = <String, Shape>{...adm2};
  final osmShapeIds = <String>[];
  final shapeIdsByDistrict = <String, String>{};
  final rowsByShape = <String, List<String>>{};
  for (final row in districts) {
    final district = 'districts.csv ${row['district']}';
    if (!zoneCodes.contains(row['zone'])) {
      errors.add('$district: unknown zone ${row['zone']}');
    }
    var shape = adm2[row['shape_id']];
    if (shape == null) {
      shape = osmShape(snapshot, row['shape_id']!, row['district']!, errors);
      if (shape != null) osmShapeIds.add(shape.id);
    }
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

  final zoneStates = {for (final zone in zones) zone['code']!: zone['state']!};
  final shapeStates = {
    for (final id in rowsByShape.keys)
      id: zoneStates[rowsByShape[id]!.first.split(':').first]!
  };
  final crossingsBefore = _crossingsOf(shapes, districts, rowsByShape,
      parentShapeIds.whereType<String>().toSet());
  cutOsmShapes(
      shapes: shapes,
      shapeStates: shapeStates,
      osmShapeIds: osmShapeIds,
      errors: errors);
  if (errors.isNotEmpty) return DataBuild('', errors, [], 'zones: not built');
  stitchStateBorders(
      shapes: shapes,
      shapeStates: shapeStates,
      snapshot: snapshot,
      errors: errors);
  if (errors.isNotEmpty) return DataBuild('', errors, [], 'zones: not built');
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
  final rawArcs = _buildArcs(regions, points);
  errors.addAll(_arcCrossings(rawArcs.vertices)
      .where((crossing) => !crossingsBefore.contains(crossing))
      .map((crossing) => 'stitching the state borders made $crossing'));
  final tolerances = _arcTolerances(rawArcs, regions, zoneStates, specialAreas,
      parentShapeIds, differingZonePairs(zoneYears));
  final fixtureAnchors = [
    for (final fixture in fixtures)
      [
        MalaysiaZoneMap.quantize(double.parse(fixture['lat']!)),
        MalaysiaZoneMap.quantize(double.parse(fixture['lon']!)),
      ]
  ];
  final border = BorderFeatures(layers.border, snapshot, catalogDates(zones));
  final anchors = AnchorIndex(fixtureAnchors);
  final refiner = ArcRefiner(rawArcs.vertices, [
    for (var a = 0; a < rawArcs.vertices.length; a++)
      if (rawArcs.users[a].length == 2 &&
          shapeStates[regions[rawArcs.users[a][0]].shapeIds.first] !=
              shapeStates[regions[rawArcs.users[a][1]].shapeIds.first])
        a
  ]);
  late List<List<int>> arcs;
  late String output;
  late MalaysiaZoneMap map;
  while (true) {
    final kept = [
      for (var a = 0; a < rawArcs.vertices.length; a++)
        keptVertices(
            rawArcs.vertices[a], tolerances[a], anchors, refiner.forced[a])
    ];
    arcs = [
      for (var a = 0; a < rawArcs.vertices.length; a++)
        [
          for (final i in kept[a]) ...[
            rawArcs.vertices[a][i * 2],
            rawArcs.vertices[a][i * 2 + 1]
          ]
        ]
    ];
    output = _encodeZones(zones, specialAreas, regions, parentShapeIds, arcs);
    map = MalaysiaZoneMap.parse(output);
    if (!refiner.refine(border.wrongPoints(map), kept)) break;
  }
  final resolved = _verifyMap(map, regions, fixtures, shapes, rowsByShape,
      zoneStates, parentShapeIds.whereType<String>().toList(), errors);
  final report = _ZoneReport(ShippedZoneMap.parse(output), layers, snapshot,
      border, catalogDates(zones));
  errors.addAll(report.failures);

  final summary = '${zones.length} zones, ${shapes.length} districts in '
      '${regions.length} regions, ${specialAreas.length} special areas, '
      '${islands.length} island areas, ${arcs.length} arcs, '
      '$resolved fixtures resolved, '
      '${refiner.forcedCount} arc vertices kept for border features, '
      '${report.summary}';
  return DataBuild(output, errors, layers.sources, summary);
}

class _Layers {
  final Map<String, Shape> adm2;
  final PolygonIndex land;
  final OsmSnapshot? snapshot;
  final List<OsmFeature> border;
  final List<OsmFeature> offMap;
  final List<Map<String, String>> noZoneAreas;
  final List<ManifestEntry> sources;

  _Layers(this.adm2, this.land, this.snapshot, this.border, this.offMap,
      this.noZoneAreas, this.sources);

  static _Layers read(String tool, List<String> errors) {
    final sources = <ManifestEntry>[];
    List<int>? readRaw(String name) {
      final file = File('$tool/raw/$name');
      try {
        return readGzipInput(file);
      } on FileSystemException catch (error) {
        errors.add('${file.path} cannot be read '
            '(${error.osError?.message ?? error.message})');
        return null;
      } on FormatException catch (error) {
        errors.add('${file.path} is ${error.message}');
        return null;
      }
    }

    var adm2 = <String, Shape>{};
    final adm2Bytes = readRaw('${_geoBoundariesFile('ADM2')}.gz');
    if (adm2Bytes != null) {
      sources.add(ManifestEntry(
          'geoboundaries',
          'MYS ADM2 simplified $geoBoundariesRelease',
          geoBoundariesRetrieved,
          _geoBoundariesUrl('ADM2'),
          sha256Hex(adm2Bytes),
          method: 'GET'));
      try {
        adm2 = readShapes(utf8.decode(adm2Bytes));
      } on FormatException catch (error) {
        errors.add('$tool/raw/${_geoBoundariesFile('ADM2')}.gz is not geoJSON '
            '(${error.message})');
      } on TypeError catch (error) {
        errors.add('$tool/raw/${_geoBoundariesFile('ADM2')}.gz is not geoJSON '
            '($error)');
      }
    }
    OsmSnapshot? snapshot;
    List<StateLineException>? exceptions;
    try {
      exceptions = readStateLineExceptions(tool);
    } on FormatException catch (error) {
      errors.add(error.message);
    }
    final osmBytes = readRaw(osmSnapshotFile);
    if (osmBytes != null && exceptions != null) {
      sources.add(ManifestEntry(
          'openstreetmap',
          'MYS admin_level=4 $osmSnapshotDate',
          osmSnapshotDate.substring(0, 10),
          overpassEndpoints.first,
          sha256Hex(osmBytes),
          method: 'POST',
          form: 'data=${overpassQuery(osmSnapshotDate)}'));
      try {
        snapshot =
            OsmSnapshot.parse(utf8.decode(osmBytes), exceptions: exceptions);
      } on StateLineExceptionError catch (error) {
        errors.add(error.message);
      } on FormatException catch (error) {
        errors.add('$tool/raw/$osmSnapshotFile is not a usable OpenStreetMap '
            'snapshot (${error.message})');
      }
    }
    sources.add(ManifestEntry(
        'geofabrik',
        'malaysia-singapore-brunei $osmExtractTimestamp',
        osmExtractTimestamp.substring(0, 10),
        osmExtractUrl,
        osmExtractSha256,
        method: 'GET'));
    List<OsmFeature> readFeatures(String file, String name, String pinned) {
      final bytes = readRaw(file);
      if (bytes == null) return const [];
      final digest = sha256Hex(bytes);
      if (digest != pinned) {
        errors.add('$tool/raw/$file has SHA-256 $digest, not the pinned '
            '$pinned that import-osm-extract writes from $osmExtractUrl');
        return const [];
      }
      sources.add(ManifestEntry('openstreetmap', '$name $osmExtractTimestamp',
          osmExtractTimestamp.substring(0, 10), osmExtractUrl, sha256Hex(bytes),
          method: 'osmium',
          form: 'tags-filter ${osmExtractFilters.join(' ')}'));
      try {
        return readOsmFeatures(bytes);
      } on FormatException catch (error) {
        errors.add('$tool/raw/$file is not an OpenStreetMap feature extract '
            '(${error.message})');
        return const [];
      }
    }

    final border = readFeatures(
        osmBorderFeaturesFile,
        'MYS features within ${osmExtractReachMetres.round()} m of a state line',
        osmBorderFeaturesSha256);
    final offMap = readFeatures(
        osmOffMapFeaturesFile,
        'MYS features more than ${osmOffMapMetres.round()} m outside every district',
        osmOffMapFeaturesSha256);
    var noZoneAreas = const <Map<String, String>>[];
    try {
      noZoneAreas = readCsv(File('$tool/$noZoneAreasFile'),
          columns: const ['name', 'territory', 'osm_ids', 'reason']);
    } on FormatException catch (error) {
      errors.add(error.message);
    }
    return _Layers(
        adm2,
        PolygonIndex([for (final shape in adm2.values) ...shape.rings]),
        snapshot,
        border,
        offMap,
        noZoneAreas,
        sources);
  }
}

String _encodeZones(
    List<Map<String, String>> zones,
    List<Map<String, String>> specialAreas,
    List<_Region> regions,
    List<String?> parentShapeIds,
    List<List<int>> arcs) {
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

  return output.toString();
}

int _verifyMap(
    MalaysiaZoneMap map,
    List<_Region> regions,
    List<Map<String, String>> fixtures,
    Map<String, Shape> shapes,
    Map<String, List<String>> rowsByShape,
    Map<String, String> zoneStates,
    List<String> parentShapeIds,
    List<String> errors) {
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
  String stateOfShape(String id) =>
      zoneStates[rowsByShape[id]!.first.split(':').first]!;
  for (var i = 0; i < map.specialAreas.length; i++) {
    final parentState = stateOfShape(parentShapeIds[i]);
    errors.addAll(_specialAreaReach(map, map.specialAreas[i], parentShapeIds[i],
        shapes.values.where((shape) => stateOfShape(shape.id) == parentState)));
  }

  return resolved;
}

String describeStateCheck(OsmSnapshot snapshot, List<MismatchArea> areas) {
  final snapped = areas.where((area) => area.snappedOnly).toList();
  String km2(Iterable<MismatchArea> some) => some
      .fold<double>(0, (sum, area) => sum + area.squareKilometres)
      .toStringAsFixed(2);
  return 'state check against OpenStreetMap $osmSnapshotDate at '
      '${stateCheckToleranceMetres.round()} m: '
      '${areas.length - snapped.length} areas on land (${km2(areas.where((a) => !a.snappedOnly))} km2), '
      '${snapped.length} areas reached only by the '
      '${MalaysiaZoneMap.boundaryToleranceMetres} m snap outside every '
      'district polygon (${km2(snapped)} km2)';
}

Set<String> _crossingsOf(
    Map<String, Shape> shapes,
    List<Map<String, String>> districts,
    Map<String, List<String>> rowsByShape,
    Set<String> separateShapeIds) {
  final copies = {
    for (final shape in shapes.values)
      shape.id: Shape(shape.id, shape.name, [
        for (final ring in shape.rings) [...ring]
      ])
  };
  final points = _Points();
  final regions =
      _mergeRegions(districts, rowsByShape, copies, separateShapeIds, points);
  return _arcCrossings(_buildArcs(regions, points).vertices).toSet();
}

List<DateComponents> catalogDates(List<Map<String, String>> zones) => [
      for (final iso in {
        for (final zone in zones) ...[zone['valid_from']!, zone['valid_to']!]
      }.where((iso) => iso.isNotEmpty))
        DateComponents(int.parse(iso.substring(0, 4)),
            int.parse(iso.substring(5, 7)), int.parse(iso.substring(8, 10)))
    ];

String _normalizeRule(String rule) {
  final compact = rule.replaceAll(' ', '');
  if (compact.isEmpty) return '';
  final pattern = RegExp(r'^(lat|lon)(<=|>=|<|>)(-?\d+(\.\d+)?)$');
  for (final part in compact.split('&')) {
    if (!pattern.hasMatch(part)) throw FormatException('malformed rule $rule');
  }
  return compact;
}

List<int> _octagon(double latitude, double longitude, double radiusMetres) {
  final lonMetres =
      metresPerDegreeLongitudeAtEquator * math.cos(latitude * math.pi / 180);
  return [
    for (var k = 0; k < 8; k++) ...[
      MalaysiaZoneMap.quantize(latitude +
          radiusMetres * math.cos(k * math.pi / 4) / metresPerDegreeLatitude),
      MalaysiaZoneMap.quantize(
          longitude + radiusMetres * math.sin(k * math.pi / 4) / lonMetres),
    ],
  ];
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

  int id(int lat, int lon) => _ids.putIfAbsent(vertexKey(lat, lon), () {
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
    Map<String, Shape> shapes,
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

class _Arcs {
  final List<List<int>> vertices = [];
  final List<List<int>> users = [];
}

_Arcs _buildArcs(List<_Region> regions, _Points points) {
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

  final arcs = _Arcs();
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
      regions[r].arcIndices.add(arcs.vertices.length);
    }
    arcs.vertices.add(vertices);
    arcs.users.add(usersBySegment[start]!);
  }
  return arcs;
}

List<List<double>> _arcTolerances(
    _Arcs rawArcs,
    List<_Region> regions,
    Map<String, String> zoneStates,
    List<Map<String, String>> specialAreas,
    List<String?> parentShapeIds,
    Set<String> differing) {
  final specialsByRegion = <int, List<Map<String, String>>>{};
  for (var i = 0; i < specialAreas.length; i++) {
    final region = regions
        .indexWhere((region) => region.shapeIds.contains(parentShapeIds[i]));
    specialsByRegion.putIfAbsent(region, () => []).add(specialAreas[i]);
  }
  Set<String> zonesAt(int region, int lat, int lon) => {
        for (final row in regions[region].rows)
          if (rowMatches(row, lat, lon)) zoneOfRow(row),
        for (final area in specialsByRegion[region] ?? const [])
          if (metresBetween(
                  lat,
                  lon,
                  MalaysiaZoneMap.quantize(double.parse(area['lat']!)),
                  MalaysiaZoneMap.quantize(double.parse(area['lon']!))) <=
              double.parse(area['radius_m']!) + simplifyToleranceMetres)
            area['zone']!,
      };
  bool differ(Set<String> one, Set<String> other) =>
      one.any((a) => other.any((b) =>
          zoneStates[a] != zoneStates[b] &&
          differing.contains(zonePair(a, b))));
  return [
    for (var a = 0; a < rawArcs.vertices.length; a++)
      [
        for (var i = 0; i < rawArcs.vertices[a].length; i += 2)
          rawArcs.users[a].length == 2 &&
                  differ(
                      zonesAt(rawArcs.users[a][0], rawArcs.vertices[a][i],
                          rawArcs.vertices[a][i + 1]),
                      zonesAt(rawArcs.users[a][1], rawArcs.vertices[a][i],
                          rawArcs.vertices[a][i + 1]))
              ? borderToleranceMetres
              : simplifyToleranceMetres
      ]
  ];
}

List<String> _arcCrossings(List<List<int>> arcs) {
  final boxes = [
    for (final arc in arcs) ringBounds(arc),
  ];
  final found = <String>[];
  for (var a = 0; a < arcs.length; a++) {
    for (var b = a; b < arcs.length; b++) {
      final p = boxes[a];
      final q = boxes[b];
      if (p[1] < q[0] || q[1] < p[0] || p[3] < q[2] || q[3] < p[2]) continue;
      final x = arcs[a];
      final y = arcs[b];
      for (var i = 2; i < x.length; i += 2) {
        for (var j = a == b ? i + 4 : 2; j < y.length; j += 2) {
          final shared = (x[i - 2] == y[j - 2] && x[i - 1] == y[j - 1]) ||
              (x[i - 2] == y[j] && x[i - 1] == y[j + 1]) ||
              (x[i] == y[j - 2] && x[i + 1] == y[j - 1]) ||
              (x[i] == y[j] && x[i + 1] == y[j + 1]);
          if (shared) continue;
          final crossing = segmentIntersection(x[i - 2], x[i - 1], x[i],
              x[i + 1], y[j - 2], y[j - 1], y[j], y[j + 1]);
          final nearVertex = crossing != null &&
              [
                [x[i - 2], x[i - 1]],
                [x[i], x[i + 1]],
                [y[j - 2], y[j - 1]],
                [y[j], y[j + 1]],
              ].any((p) =>
                  (p[0] - crossing[0]).abs() <= 2 &&
                  (p[1] - crossing[1]).abs() <= 2);
          if (!nearVertex &&
              segmentsCross(x[i - 2], x[i - 1], x[i], x[i + 1], y[j - 2],
                  y[j - 1], y[j], y[j + 1])) {
            found.add('two arcs cross: ${x[i - 2] / 100000},'
                '${x[i - 1] / 100000}..${x[i] / 100000},${x[i + 1] / 100000} '
                'and ${y[j - 2] / 100000},${y[j - 1] / 100000}..'
                '${y[j] / 100000},${y[j + 1] / 100000}');
          }
        }
      }
    }
  }
  return found;
}

List<String> _gridOverlaps(MalaysiaZoneMap map, List<_Region> regions) {
  final found = <String, int>{};
  for (var lat = gridMinLatitude;
      lat <= gridMaxLatitude;
      lat += overlapGridStepDegrees) {
    for (var lon = gridMinLongitude;
        lon <= gridMaxLongitude;
        lon += overlapGridStepDegrees) {
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
    String parentShapeId, Iterable<Shape> shapes) {
  final day = math.max(map.zone(area.zone)!.validFromDay, 20000101);
  final date = DateComponents(day ~/ 10000, day ~/ 100 % 100, day % 100);
  final steps = (area.radiusMetres / specialAreaGridStepMetres).ceil();
  final latStep = specialAreaGridStepMetres / metresPerDegreeLatitude;
  final lonStep = specialAreaGridStepMetres /
      (metresPerDegreeLongitudeAtEquator *
          math.cos(area.latitude * math.pi / 180));
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
