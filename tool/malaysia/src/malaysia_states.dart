import 'dart:math' as math;

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';

import 'geometry.dart';
import 'osm_extract.dart';
import 'osm_snapshot.dart';

const stateCheckGridStepDegrees = 0.001;
const stateCheckToleranceMetres = 110.0;
const gridMinLatitude = 0.8;
const gridMaxLatitude = 7.5;
const gridMinLongitude = 99.5;
const gridMaxLongitude = 119.5;

class ShippedZoneMap {
  final MalaysiaZoneMap map;
  final List<List<int>> arcs;
  final List<List<int>> regionArcs;
  final List<List<String>> regionRows;
  final List<Set<String>> regionZones;

  ShippedZoneMap(
      this.map, this.arcs, this.regionArcs, this.regionRows, this.regionZones);

  static ShippedZoneMap parse(String text) {
    final map = MalaysiaZoneMap.parse(text);
    final arcs = <List<int>>[];
    final regionArcs = <List<int>>[];
    final regionRows = <List<String>>[];
    for (final line in text.split('\n')) {
      final fields = line.split('\t');
      if (fields[0] == 'A') {
        arcs.add(MalaysiaZoneMap.decodePolyline(fields[1]));
      } else if (fields[0] == 'R') {
        regionArcs.add(fields[1].split(' ').map(int.parse).toList());
        regionRows.add(fields[2].split(' '));
      }
    }
    final regionZones = [
      for (final rows in regionRows) {for (final row in rows) zoneOfRow(row)}
    ];
    for (final area in map.specialAreas) {
      if (area.region < 0 || area.region >= regionZones.length) {
        throw FormatException(
            'special area ${area.name} names region ${area.region}');
      }
      regionZones[area.region].add(area.zone);
    }
    for (final zones in regionZones) {
      for (final zone in zones) {
        if (map.zone(zone) == null) {
          throw FormatException('unknown zone $zone');
        }
      }
    }
    return ShippedZoneMap(map, arcs, regionArcs, regionRows, regionZones);
  }
}

String zoneOfRow(String row) => row.split(':').first;

bool rowMatches(String row, int lat, int lon) {
  final colon = row.indexOf(':');
  if (colon < 0) return true;
  for (final part in row.substring(colon + 1).split('&')) {
    final match = _rulePart.firstMatch(part)!;
    final subject = (match.group(1) == 'lat' ? lat : lon) / 100000;
    final value = double.parse(match.group(3)!);
    final operator = match.group(2);
    final holds = operator == '<'
        ? subject < value
        : operator == '<='
            ? subject <= value
            : operator == '>'
                ? subject > value
                : subject >= value;
    if (!holds) return false;
  }
  return true;
}

final _rulePart = RegExp(r'^(lat|lon)(<=|>=|<|>)(-?\d+(?:\.\d+)?)$');

Map<String, Set<String>> zoneTerritories(Iterable<MalaysiaZone> zones) {
  final federal = {
    for (final iso in osmTerritoryNames.keys) osmStateNames[iso],
  };
  return {
    for (final zone in zones)
      zone.code: federal.contains(zone.state)
          ? osmTerritoryNames.values.where(zone.areas.contains).toSet()
          : {zone.state},
  };
}

class MismatchArea {
  final String territory;
  final String? zoneState;
  final Set<String> zones = {};
  String? exception;
  int points = 0;
  int snappedPoints = 0;
  double squareKilometres = 0;
  double depthMetres = 0;
  int deepestLat = 0;
  int deepestLon = 0;
  int minLat = 1 << 40;
  int maxLat = -(1 << 40);
  int minLon = 1 << 40;
  int maxLon = -(1 << 40);

  final List<String> features = [];
  final List<String> featureIds = [];
  int unlisted = 0;

  MismatchArea(this.territory, this.zoneState);

  bool get noZone => zoneState == null;

  bool get snappedOnly => !noZone && snappedPoints == points;

  bool get fails => !snappedOnly && exception == null;

  String describe() {
    final box = 'box ${degrees(minLat)}..${degrees(maxLat)} '
        '${degrees(minLon)}..${degrees(maxLon)}';
    final known = exception == null ? '' : ', known: $exception';
    if (features.isNotEmpty) {
      final named = features.where((name) => name.isNotEmpty).take(3);
      return 'at $points OpenStreetMap features inside OpenStreetMap '
          '$territory${named.isEmpty ? '' : ' (${named.join(', ')})'}, '
          '$box$known'
          '${unlisted == 0 ? '' : ', $unlisted not named in $noZoneAreasFile'}';
    }
    return '${noZone ? '' : '${zones.join('/')} ($zoneState) '}'
        'inside OpenStreetMap $territory, '
        '${squareKilometres.toStringAsFixed(2)} km2, '
        '${depthMetres.round()} m deep at ${degrees(deepestLat)},'
        '${degrees(deepestLon)}, $box'
        '${snappedPoints == 0 || noZone ? '' : ', $snappedPoints of $points points outside every district polygon (${MalaysiaZoneMap.boundaryToleranceMetres} m snap)'}'
        '$known';
  }
}

List<String> applyNoZoneExceptions(
    List<MismatchArea> areas, List<Map<String, String>> rows) {
  final rowOf = <String, Map<String, String>>{};
  for (final row in rows) {
    for (final id in row['osm_ids']!.split(' ')) {
      if (id.isNotEmpty) rowOf[id] = row;
    }
  }
  final listed = <String>{};
  for (final area in areas) {
    if (!area.noZone || area.featureIds.isEmpty) continue;
    final names = <String>{};
    for (final id in area.featureIds) {
      final row = rowOf[id];
      if (row != null && row['territory'] == area.territory) {
        listed.add(id);
        names.add(row['name']!);
      }
    }
    area.unlisted = area.featureIds.where((id) => !listed.contains(id)).length;
    if (area.unlisted == 0) area.exception = names.join('; ');
  }
  return [
    for (final id in rowOf.keys)
      if (!listed.contains(id))
        '$noZoneAreasFile ${rowOf[id]!['name']} names $id, which is not an '
            'OpenStreetMap feature off the map with no zone'
  ];
}

const noZoneAreasFile = 'no_zone_areas.csv';

List<MismatchArea> findStateMismatches({
  required ShippedZoneMap shipped,
  required OsmSnapshot snapshot,
  required PolygonIndex land,
  required List<DateComponents> dates,
}) {
  final map = shipped.map;
  final zoneStates = {for (final zone in map.zones) zone.code: zone.state};
  final allowed = zoneTerritories(map.zones);
  final days = [
    for (final date in dates) date.year * 10000 + date.month * 100 + date.day
  ];
  final regionsByArc = List.generate(shipped.arcs.length, (_) => <int>[]);
  for (var r = 0; r < shipped.regionArcs.length; r++) {
    for (final a in shipped.regionArcs[r]) {
      regionsByArc[a].add(r);
    }
  }
  final territories = snapshot.territories.toList();
  final ringsByTerritory = [
    for (final territory in territories)
      [
        for (final ring in snapshot.rings)
          if (ring.territory == territory) ring.points
      ]
  ];
  final regionTerritories = [
    for (final zones in shipped.regionZones)
      territories
          .where((territory) =>
              zones.every((zone) => allowed[zone]!.contains(territory)))
          .toSet()
  ];
  final regionRules = [
    for (final rows in shipped.regionRows)
      days.every((day) => rows.any((row) =>
              !row.contains(':') && map.zone(zoneOfRow(row))!.inForce(day)))
          ? const <String>[]
          : rows
  ];
  bool resolvesEveryDay(List<String> rows, int lat, int lon) =>
      rows.isEmpty ||
      days.every((day) => rows.any((row) =>
          map.zone(zoneOfRow(row))!.inForce(day) && rowMatches(row, lat, lon)));

  final step = MalaysiaZoneMap.quantize(stateCheckGridStepDegrees);
  final bounds = snapshot.bounds;
  final minLat = (bounds[0] ~/ step) * step;
  final maxLat = bounds[1];
  final minLon = (bounds[2] ~/ step) * step;
  final maxLon = bounds[3];
  final columns = (maxLon - minLon) ~/ step + 1;

  final arcIndex = SegmentIndex();
  for (var a = 0; a < shipped.arcs.length; a++) {
    arcIndex.addPolyline(shipped.arcs[a], a);
  }
  final snap = MalaysiaZoneMap.boundaryToleranceMetres.toDouble();
  bool nearAnArc(int lat, int lon) => arcIndex
      .near(lat, lon, snap)
      .any((s) => pointSegmentMetres(lat, lon, s[0], s[1], s[2], s[3]) <= snap);
  final stateScan = _Scanline(ringsByTerritory);
  final regionScan = _Scanline([
    for (final arc in shipped.arcs) [arc]
  ], open: true);
  final mismatchLabel = <int, String>{};
  final mismatchZones = <int, Set<String>>{};
  final mismatchDepth = <int, double>{};
  final mismatchSnapped = <int>{};
  for (var row = 0; minLat + row * step <= maxLat; row++) {
    final lat = minLat + row * step;
    final stateSpans = stateScan.spans(lat, (index) => [index]);
    if (stateSpans.isEmpty) continue;
    final regionSpans = regionScan.spans(lat, (index) => regionsByArc[index]);
    var regionSpan = 0;
    for (final span in stateSpans) {
      final territory = territories[span.owner];
      final firstColumn = ((span.fromLon - minLon) / step).ceil();
      final lastColumn = ((span.toLon - minLon) / step).floor();
      for (var column = firstColumn; column <= lastColumn; column++) {
        final lon = minLon + column * step;
        while (regionSpan < regionSpans.length &&
            regionSpans[regionSpan].toLon < lon) {
          regionSpan++;
        }
        final region = regionSpan < regionSpans.length &&
                regionSpans[regionSpan].fromLon <= lon
            ? regionSpans[regionSpan].owner
            : -1;
        if (region >= 0 &&
            regionTerritories[region].contains(territory) &&
            resolvesEveryDay(regionRules[region], lat, lon)) {
          continue;
        }
        final zones = <String>{};
        var none = region < 0 && !nearAnArc(lat, lon);
        if (none && !land.contains(lat, lon)) continue;
        if (!none) {
          for (final date in dates) {
            final zone = map.zoneAt(lat / 100000, lon / 100000, date);
            if (zone == null) {
              none = true;
            } else if (!allowed[zone]!.contains(territory)) {
              zones.add(zone);
            }
          }
        }
        if (zones.isEmpty && !none) continue;
        final depth = snapshot.depthMetres(territory, lat, lon);
        if (depth <= stateCheckToleranceMetres) continue;
        final key = row * columns + column;
        mismatchLabel[key] = zones.isEmpty ? '$territory|' : '$territory|zone';
        mismatchZones[key] = zones;
        mismatchDepth[key] = depth;
        if (region < 0) mismatchSnapped.add(key);
      }
    }
  }
  return _groupAreas(mismatchLabel, mismatchZones, mismatchDepth,
      mismatchSnapped, zoneStates, columns, minLat, minLon, step);
}

List<MismatchArea> _groupAreas(
    Map<int, String> mismatchLabel,
    Map<int, Set<String>> mismatchZones,
    Map<int, double> mismatchDepth,
    Set<int> mismatchSnapped,
    Map<String, String> zoneStates,
    int columns,
    int minLat,
    int minLon,
    int step) {
  final parent = <int, int>{for (final key in mismatchLabel.keys) key: key};
  int find(int key) {
    while (parent[key] != key) {
      parent[key] = parent[parent[key]!]!;
      key = parent[key]!;
    }
    return key;
  }

  for (final key in mismatchLabel.keys) {
    for (final neighbour in [
      key - columns - 1,
      key - columns,
      key - columns + 1,
      key - 1,
    ]) {
      if (mismatchLabel[neighbour] == mismatchLabel[key]) {
        parent[find(neighbour)] = find(key);
      }
    }
  }

  final areas = <int, MismatchArea>{};
  for (final key in mismatchLabel.keys) {
    final lat = minLat + key ~/ columns * step;
    final lon = minLon + key % columns * step;
    final zones = mismatchZones[key]!;
    final area = areas.putIfAbsent(
        find(key),
        () => MismatchArea(mismatchLabel[key]!.split('|').first,
            zones.isEmpty ? null : zoneStates[zones.first]!));
    area.zones.addAll(zones);
    area.points++;
    if (mismatchSnapped.contains(key)) area.snappedPoints++;
    area.squareKilometres += stateCheckGridStepDegrees *
        stateCheckGridStepDegrees *
        metresPerDegreeLatitude /
        1000 *
        metresPerDegreeLongitudeAtEquator /
        1000 *
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

class _Span {
  final double fromLon;
  final double toLon;
  final int owner;

  _Span(this.fromLon, this.toLon, this.owner);
}

class _Scanline {
  static const int bandSize = 1000;
  final List<List<int>> _segments = [];
  final Map<int, List<int>> _bands = {};

  _Scanline(List<List<List<int>>> owners, {bool open = false}) {
    for (var owner = 0; owner < owners.length; owner++) {
      for (final ring in owners[owner]) {
        for (var i = open ? 2 : 0; i < ring.length; i += 2) {
          final j = i == 0 ? ring.length - 2 : i - 2;
          if (ring[j] == ring[i]) continue;
          final index = _segments.length;
          _segments.add([ring[j], ring[j + 1], ring[i], ring[i + 1], owner]);
          final low = math.min(ring[j], ring[i]) ~/ bandSize;
          final high = math.max(ring[j], ring[i]) ~/ bandSize;
          for (var band = low; band <= high; band++) {
            _bands.putIfAbsent(band, () => []).add(index);
          }
        }
      }
    }
  }

  List<_Span> spans(int lat, List<int> Function(int owner) targets) {
    final crossings = <double>[];
    final crossingOwners = <int>[];
    for (final index in _bands[lat ~/ bandSize] ?? const <int>[]) {
      final s = _segments[index];
      final lat1 = s[0];
      final lat2 = s[2];
      if ((lat1 > lat) == (lat2 > lat)) continue;
      crossings.add(s[1] + (lat - lat1) * (s[3] - s[1]) / (lat2 - lat1));
      crossingOwners.add(s[4]);
    }
    final order = List.generate(crossings.length, (i) => i)
      ..sort((a, b) => crossings[a].compareTo(crossings[b]));
    final spans = <_Span>[];
    final inside = <int>{};
    for (var k = 0; k < order.length; k++) {
      for (final target in targets(crossingOwners[order[k]])) {
        if (!inside.remove(target)) inside.add(target);
      }
      if (inside.isEmpty || k + 1 == order.length) continue;
      spans.add(
          _Span(crossings[order[k]], crossings[order[k + 1]], inside.first));
    }
    return spans;
  }
}

List<MismatchArea> offMapWithoutZone(
    MalaysiaZoneMap map,
    List<OsmFeature> features,
    OsmSnapshot snapshot,
    List<DateComponents> dates) {
  const cell = 1000;
  final byCell = <String, List<OsmFeature>>{};
  final territoryOf = <String, String>{};
  for (final feature in features) {
    final territory = snapshot.territoryAt(feature.lat, feature.lon);
    if (territory == null ||
        dates.every((date) =>
            map.zoneAt(feature.lat / 100000, feature.lon / 100000, date) !=
            null)) {
      continue;
    }
    territoryOf[feature.id] = territory;
    byCell
        .putIfAbsent('$territory ${feature.lat ~/ cell} ${feature.lon ~/ cell}',
            () => [])
        .add(feature);
  }
  final parent = {for (final key in byCell.keys) key: key};
  String find(String key) {
    while (parent[key] != key) {
      key = parent[key] = parent[parent[key]!]!;
    }
    return key;
  }

  for (final key in byCell.keys) {
    final parts = key.split(' ');
    final territory = parts.sublist(0, parts.length - 2).join(' ');
    final row = int.parse(parts[parts.length - 2]);
    final column = int.parse(parts.last);
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final neighbour = '$territory ${row + dy} ${column + dx}';
        if (parent.containsKey(neighbour)) parent[find(neighbour)] = find(key);
      }
    }
  }
  final areas = <String, MismatchArea>{};
  for (final key in byCell.keys) {
    for (final feature in byCell[key]!) {
      final area = areas.putIfAbsent(
          find(key), () => MismatchArea(territoryOf[feature.id]!, null));
      area.points++;
      area.features.add(feature.name);
      area.featureIds.add(feature.id);
      area.minLat = math.min(area.minLat, feature.lat);
      area.maxLat = math.max(area.maxLat, feature.lat);
      area.minLon = math.min(area.minLon, feature.lon);
      area.maxLon = math.max(area.maxLon, feature.lon);
    }
  }
  return areas.values.toList()..sort((a, b) => b.points.compareTo(a.points));
}
