import 'dart:math' as math;

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';

import 'geometry.dart';
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
  final List<String?> regionStates;

  ShippedZoneMap(this.map, this.arcs, this.regionArcs, this.regionStates);

  static ShippedZoneMap parse(String text) {
    final map = MalaysiaZoneMap.parse(text);
    final zoneStates = {for (final zone in map.zones) zone.code: zone.state};
    final arcs = <List<int>>[];
    final regionArcs = <List<int>>[];
    final regionStates = <String?>[];
    for (final line in text.split('\n')) {
      final fields = line.split('\t');
      if (fields[0] == 'A') {
        arcs.add(MalaysiaZoneMap.decodePolyline(fields[1]));
      } else if (fields[0] == 'R') {
        regionArcs.add(fields[1].split(' ').map(int.parse).toList());
        final states = {
          for (final row in fields[2].split(' '))
            zoneStates[row.split(':').first]
        };
        regionStates.add(states.length == 1 ? states.single : null);
      }
    }
    return ShippedZoneMap(map, arcs, regionArcs, regionStates);
  }
}

class MismatchArea {
  final String osmState;
  final String zoneState;
  final Set<String> zones = {};
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

  MismatchArea(this.osmState, this.zoneState);

  bool get snappedOnly => snappedPoints == points;

  String describe() => '${zones.join('/')} ($zoneState) inside OpenStreetMap '
      '$osmState, ${squareKilometres.toStringAsFixed(2)} km2, '
      '${depthMetres.round()} m deep at ${degrees(deepestLat)},'
      '${degrees(deepestLon)}, box ${degrees(minLat)}..${degrees(maxLat)} '
      '${degrees(minLon)}..${degrees(maxLon)}'
      '${snappedPoints == 0 ? '' : ', $snappedPoints of $points points outside every district polygon (${MalaysiaZoneMap.boundaryToleranceMetres} m snap)'}';
}

List<MismatchArea> findStateMismatches({
  required ShippedZoneMap shipped,
  required OsmSnapshot snapshot,
  required List<DateComponents> dates,
}) {
  final map = shipped.map;
  final zoneStates = {for (final zone in map.zones) zone.code: zone.state};
  final regionsByArc = List.generate(shipped.arcs.length, (_) => <int>[]);
  for (var r = 0; r < shipped.regionArcs.length; r++) {
    for (final a in shipped.regionArcs[r]) {
      regionsByArc[a].add(r);
    }
  }
  final states = snapshot.states.toList();
  final ringsByState = [for (final state in states) snapshot.ringsOf(state)];

  final step = MalaysiaZoneMap.quantize(stateCheckGridStepDegrees);
  final minLat = MalaysiaZoneMap.quantize(gridMinLatitude);
  final maxLat = MalaysiaZoneMap.quantize(gridMaxLatitude);
  final minLon = MalaysiaZoneMap.quantize(gridMinLongitude);
  final maxLon = MalaysiaZoneMap.quantize(gridMaxLongitude);
  final columns = (maxLon - minLon) ~/ step + 1;

  final arcIndex = SegmentIndex();
  for (var a = 0; a < shipped.arcs.length; a++) {
    arcIndex.addPolyline(shipped.arcs[a], a);
  }
  final snap = MalaysiaZoneMap.boundaryToleranceMetres.toDouble();
  bool nearAnArc(int lat, int lon) => arcIndex
      .near(lat, lon, snap)
      .any((s) => pointSegmentMetres(lat, lon, s[0], s[1], s[2], s[3]) <= snap);
  final stateScan = _Scanline([
    for (final rings in ringsByState) [for (final r in rings) r.points]
  ]);
  final regionScan = _Scanline([
    for (final arc in shipped.arcs) [arc]
  ], open: true);
  final mismatchState = <int, String>{};
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
      final state = states[span.owner];
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
        if (region >= 0 && shipped.regionStates[region] == state) continue;
        if (region < 0 && !nearAnArc(lat, lon)) continue;
        final zones = <String>{};
        for (final date in dates) {
          final zone = map.zoneAt(lat / 100000, lon / 100000, date);
          if (zone != null && zoneStates[zone] != state) zones.add(zone);
        }
        if (zones.isEmpty) continue;
        final depth = snapshot.depthMetres(state, lat, lon);
        if (depth <= stateCheckToleranceMetres) continue;
        final key = row * columns + column;
        mismatchState[key] = state;
        mismatchZones[key] = zones;
        mismatchDepth[key] = depth;
        if (region < 0) mismatchSnapped.add(key);
      }
    }
  }
  return _groupAreas(mismatchState, mismatchZones, mismatchDepth,
      mismatchSnapped, zoneStates, columns, minLat, minLon, step);
}

List<MismatchArea> _groupAreas(
    Map<int, String> mismatchState,
    Map<int, Set<String>> mismatchZones,
    Map<int, double> mismatchDepth,
    Set<int> mismatchSnapped,
    Map<String, String> zoneStates,
    int columns,
    int minLat,
    int minLon,
    int step) {
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
