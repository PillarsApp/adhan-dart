import 'dart:math' as math;

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_times_codec.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';

import 'geometry.dart';
import 'malaysia_states.dart';
import 'osm_extract.dart';
import 'osm_snapshot.dart';

const simplifyToleranceMetres = 100.0;
const borderToleranceMetres = 80.0;
const borderDifferenceMinutes = 2;
const anchorKeepMetres = 150.0;

String zonePair(String a, String b) => a.compareTo(b) < 0 ? '$a $b' : '$b $a';

Set<String> differingZonePairs(List<MalaysiaZoneYear> zoneYears) {
  final byZone = <String, Map<int, List<int>>>{};
  for (final zoneYear in zoneYears) {
    final days = byZone.putIfAbsent(zoneYear.zone, () => {});
    for (var d = 0; d < zoneYear.days.length; d++) {
      days[zoneYear.year * 1000 + d] = zoneYear.days[d];
    }
  }
  final zones = byZone.keys.toList()..sort();
  final pairs = <String>{};
  for (var i = 0; i < zones.length; i++) {
    for (var j = i + 1; j < zones.length; j++) {
      final other = byZone[zones[j]]!;
      final differs = byZone[zones[i]]!.entries.any((day) {
        final times = other[day.key];
        if (times == null) return false;
        for (var f = 0; f < times.length; f++) {
          if ((times[f] - day.value[f]).abs() >= borderDifferenceMinutes) {
            return true;
          }
        }
        return false;
      });
      if (differs) pairs.add(zonePair(zones[i], zones[j]));
    }
  }
  return pairs;
}

class AnchorIndex {
  final SegmentIndex _index = SegmentIndex();

  AnchorIndex(Iterable<List<int>> anchors) {
    for (final anchor in anchors) {
      _index.addPolyline([anchor[0], anchor[1], anchor[0], anchor[1]], 0);
    }
  }

  bool nearSegment(int lat1, int lon1, int lat2, int lon2) {
    final reach =
        anchorKeepMetres + metresBetween(lat1, lon1, lat2, lon2) / 2 + 1;
    return _index.near((lat1 + lat2) ~/ 2, (lon1 + lon2) ~/ 2, reach).any((a) =>
        pointSegmentMetres(a[0], a[1], lat1, lon1, lat2, lon2) <=
        anchorKeepMetres);
  }
}

List<int> simplifyArc(
    List<int> points, List<double> tolerances, AnchorIndex anchors) {
  final count = points.length ~/ 2;
  if (count <= 2) return points;
  final closed = points[0] == points[points.length - 2] &&
      points[1] == points[points.length - 1];
  if (closed && count > 3) {
    var farthest = 1;
    var farthestDistance = -1.0;
    for (var i = 1; i < count - 1; i++) {
      final d =
          metresBetween(points[0], points[1], points[i * 2], points[i * 2 + 1]);
      if (d > farthestDistance) {
        farthestDistance = d;
        farthest = i;
      }
    }
    final head = simplifyArc(points.sublist(0, farthest * 2 + 2),
        tolerances.sublist(0, farthest + 1), anchors);
    final tail = simplifyArc(
        points.sublist(farthest * 2), tolerances.sublist(farthest), anchors);
    return [...head, ...tail.sublist(2)];
  }
  final keep = List<bool>.filled(count, false);
  keep[0] = true;
  keep[count - 1] = true;
  for (var i = 1; i < count; i++) {
    if (anchors.nearSegment(points[i * 2 - 2], points[i * 2 - 1], points[i * 2],
        points[i * 2 + 1])) {
      keep[i - 1] = true;
      keep[i] = true;
    }
  }
  final stack = <List<int>>[];
  var previous = 0;
  for (var i = 1; i < count; i++) {
    if (!keep[i]) continue;
    stack.add([previous, i]);
    previous = i;
  }
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    var worst = -1;
    var worstExcess = 1.0;
    for (var i = range[0] + 1; i < range[1]; i++) {
      final excess = pointSegmentMetres(
              points[i * 2],
              points[i * 2 + 1],
              points[range[0] * 2],
              points[range[0] * 2 + 1],
              points[range[1] * 2],
              points[range[1] * 2 + 1]) /
          tolerances[i];
      if (excess > worstExcess) {
        worstExcess = excess;
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

class BorderFeatures {
  final List<LocatedFeature> features = [];
  final List<DateComponents> dates;

  BorderFeatures(List<OsmFeature> extract, OsmSnapshot snapshot, this.dates) {
    final lines = snapshot.stateLines();
    for (final feature in extract) {
      final territory = snapshot.territoryAt(feature.lat, feature.lon);
      if (territory == null) continue;
      var metres = double.infinity;
      for (final s
          in lines.near(feature.lat, feature.lon, osmExtractReachMetres)) {
        metres = math.min(
            metres,
            pointSegmentMetres(
                feature.lat, feature.lon, s[0], s[1], s[2], s[3]));
      }
      features.add(LocatedFeature(feature, territory, metres));
    }
  }

  List<LocatedFeature> wrongFeatures(MalaysiaZoneMap map) {
    final allowed = zoneTerritories(map.zones);
    return [
      for (final located in features)
        if (dates.any((date) {
          final zone = map.zoneAt(
              located.feature.lat / 100000, located.feature.lon / 100000, date);
          return zone != null && !allowed[zone]!.contains(located.territory);
        }))
          located
    ];
  }

  String describe(List<LocatedFeature> wrong, int anchored) {
    bool gated(LocatedFeature f) => f.metresToLine <= stateCheckToleranceMetres;
    return '${features.where(gated).length} OpenStreetMap border features '
        'within ${stateCheckToleranceMetres.round()} m of a state line, '
        '${wrong.where(gated).length} on another state\'s zone '
        '($anchored anchored)';
  }
}

class LocatedFeature {
  final OsmFeature feature;
  final String territory;
  final double metresToLine;

  LocatedFeature(this.feature, this.territory, this.metresToLine);

  String get id => feature.id;
  int get lat => feature.lat;
  int get lon => feature.lon;

  String describe() =>
      '${feature.id} ${feature.tag} ${feature.name} ${degrees(lat)},'
      '${degrees(lon)}, ${metresToLine.round()} m inside OpenStreetMap '
      '$territory, resolves to another state\'s zone';
}
