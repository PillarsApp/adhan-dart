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
const refineReachMetres = 110.0;

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

List<int> keptVertices(List<int> points, List<double> tolerances,
    AnchorIndex anchors, Set<int> forced) {
  final count = points.length ~/ 2;
  if (count <= 2) return [for (var i = 0; i < count; i++) i];
  final keep = List<bool>.filled(count, false);
  keep[0] = true;
  keep[count - 1] = true;
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
    keep[farthest] = true;
  }
  for (var i = 1; i < count; i++) {
    if (anchors.nearSegment(points[i * 2 - 2], points[i * 2 - 1], points[i * 2],
        points[i * 2 + 1])) {
      keep[i - 1] = true;
      keep[i] = true;
    }
  }
  for (final i in forced) {
    keep[i] = true;
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
      if (keep[i]) i
  ];
}

class ArcRefiner {
  static const int _stride = 1 << 24;
  final List<List<int>> rawArcs;
  final List<Set<int>> forced;
  final SegmentIndex _segments = SegmentIndex();

  ArcRefiner(this.rawArcs, Iterable<int> stateBorderArcs)
      : forced = List.generate(rawArcs.length, (_) => <int>{}) {
    for (final a in stateBorderArcs) {
      final points = rawArcs[a];
      for (var k = 2; k < points.length; k += 2) {
        _segments.addPolyline(
            [points[k - 2], points[k - 1], points[k], points[k + 1]],
            a * _stride + k ~/ 2 - 1);
      }
    }
  }

  int get forcedCount => forced.fold(0, (sum, set) => sum + set.length);

  bool refine(List<BorderPoint> wrong, List<List<int>> kept) {
    var added = false;
    for (final point in wrong) {
      final reach = point.metresToLine + refineReachMetres;
      final best = <int, int>{};
      final bestMetres = <int, double>{};
      for (final s in _segments.near(point.lat, point.lon, reach)) {
        if (pointSegmentMetres(point.lat, point.lon, s[0], s[1], s[2], s[3]) >
            reach) {
          continue;
        }
        final a = s[4] ~/ _stride;
        final k = s[4] % _stride;
        final indices = kept[a];
        var low = 0;
        var high = indices.length - 1;
        while (high - low > 1) {
          final middle = (low + high) ~/ 2;
          if (indices[middle] <= k) {
            low = middle;
          } else {
            high = middle;
          }
        }
        final from = indices[low];
        final to = indices[high];
        if (to - from < 2) continue;
        final points = rawArcs[a];
        final span = a * _stride + from;
        for (var i = from + 1; i < to; i++) {
          final metres = metresBetween(
              point.lat, point.lon, points[i * 2], points[i * 2 + 1]);
          if (metres < (bestMetres[span] ?? double.infinity)) {
            bestMetres[span] = metres;
            best[span] = i;
          }
        }
      }
      best.forEach((span, i) {
        if (forced[span ~/ _stride].add(i)) added = true;
      });
    }
    return added;
  }
}

class BorderFeatures {
  final List<LocatedFeature> features = [];
  final List<BorderPoint> points = [];
  final List<DateComponents> dates;

  BorderFeatures(List<OsmFeature> extract, OsmSnapshot snapshot, this.dates) {
    final lines = snapshot.stateLines();
    for (final feature in extract) {
      final located = LocatedFeature(feature);
      final samples = feature.samples;
      for (var i = 0; i < samples.length; i += 2) {
        final lat = samples[i];
        final lon = samples[i + 1];
        var metres = double.infinity;
        for (final s in lines.near(lat, lon, osmExtractReachMetres)) {
          metres = math.min(
              metres, pointSegmentMetres(lat, lon, s[0], s[1], s[2], s[3]));
        }
        if (metres > osmExtractReachMetres) continue;
        final territory = snapshot.territoryAt(lat, lon);
        if (territory == null) continue;
        located.points.add(BorderPoint(located, lat, lon, territory, metres));
      }
      if (located.points.isEmpty) continue;
      features.add(located);
      points.addAll(located.points);
    }
  }

  List<BorderPoint> wrongPoints(MalaysiaZoneMap map) {
    final allowed = zoneTerritories(map.zones);
    return [
      for (final point in points)
        if (dates.any((date) {
          final zone = map.zoneAt(point.lat / 100000, point.lon / 100000, date);
          return zone != null && !allowed[zone]!.contains(point.territory);
        }))
          point
    ];
  }

  List<String> failures(List<BorderPoint> wrong) {
    final byFeature = <LocatedFeature, List<BorderPoint>>{};
    for (final point in wrong) {
      if (point.metresToLine <= stateCheckToleranceMetres) {
        byFeature.putIfAbsent(point.feature, () => []).add(point);
      }
    }
    return [
      for (final entry in byFeature.entries)
        'border feature ${entry.key.describe(entry.value)}'
    ];
  }

  String describe(List<BorderPoint> wrong) {
    bool gated(BorderPoint p) => p.metresToLine <= stateCheckToleranceMetres;
    final gatedFeatures = features.where((f) => f.points.any(gated)).length;
    final wrongFeatures =
        {for (final point in wrong.where(gated)) point.feature}.length;
    return '$gatedFeatures OpenStreetMap border features '
        '(${points.where(gated).length} outline points) within '
        '${stateCheckToleranceMetres.round()} m of a state line, '
        '$wrongFeatures with a point on another state\'s zone';
  }
}

class LocatedFeature {
  final OsmFeature feature;
  final List<BorderPoint> points = [];

  LocatedFeature(this.feature);

  String describe(List<BorderPoint> wrong) {
    final deepest =
        wrong.reduce((a, b) => a.metresToLine >= b.metresToLine ? a : b);
    return '${feature.id} ${feature.tag} ${feature.name}: ${wrong.length} of '
        '${points.length} outline points resolve to another state\'s zone, '
        'such as ${degrees(deepest.lat)},${degrees(deepest.lon)}, '
        '${deepest.metresToLine.round()} m inside OpenStreetMap '
        '${deepest.territory}';
  }
}

class BorderPoint {
  final LocatedFeature feature;
  final int lat;
  final int lon;
  final String territory;
  final double metresToLine;

  BorderPoint(
      this.feature, this.lat, this.lon, this.territory, this.metresToLine);
}
