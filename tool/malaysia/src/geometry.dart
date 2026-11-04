import 'dart:convert';
import 'dart:math' as math;

import 'package:adhan/src/data/malaysia_zone_map.dart';

const double metresPerDegreeLatitude = 110574;
const double metresPerDegreeLongitudeAtEquator = 111320;
const double latScale = metresPerDegreeLatitude / 100000;

double lonScaleAt(int lat) =>
    metresPerDegreeLongitudeAtEquator *
    math.cos(lat / 100000 * math.pi / 180) /
    100000;

double metresBetween(int lat1, int lon1, int lat2, int lon2) {
  final dy = (lat2 - lat1) * latScale;
  final dx = (lon2 - lon1) * lonScaleAt((lat1 + lat2) ~/ 2);
  return math.sqrt(dx * dx + dy * dy);
}

double pointSegmentMetres(
    int lat, int lon, int lat1, int lon1, int lat2, int lon2) {
  final lonScale = lonScaleAt(lat);
  final x1 = (lon1 - lon) * lonScale;
  final y1 = (lat1 - lat) * latScale;
  final dx = (lon2 - lon1) * lonScale;
  final dy = (lat2 - lat1) * latScale;
  final lengthSquared = dx * dx + dy * dy;
  var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared;
  t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  final px = x1 + t * dx;
  final py = y1 + t * dy;
  return math.sqrt(px * px + py * py);
}

List<int> nearestPointOnSegment(
    int lat, int lon, int lat1, int lon1, int lat2, int lon2) {
  final lonScale = lonScaleAt(lat);
  final dx = (lon2 - lon1) * lonScale;
  final dy = (lat2 - lat1) * latScale;
  final lengthSquared = dx * dx + dy * dy;
  var t = lengthSquared == 0
      ? 0.0
      : -(((lon1 - lon) * lonScale) * dx + ((lat1 - lat) * latScale) * dy) /
          lengthSquared;
  t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  return [
    (lat1 + t * (lat2 - lat1)).round(),
    (lon1 + t * (lon2 - lon1)).round()
  ];
}

bool ringContains(List<int> ring, int lat, int lon) {
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

bool ringsContain(List<List<int>> rings, int lat, int lon) {
  var inside = false;
  for (final ring in rings) {
    if (ringContains(ring, lat, lon)) inside = !inside;
  }
  return inside;
}

int turn(int ay, int ax, int by, int bx, int cy, int cx) =>
    ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)).sign;

bool segmentsIntersect(
    int ay, int ax, int by, int bx, int cy, int cx, int dy, int dx) {
  final abc = turn(ay, ax, by, bx, cy, cx);
  final abd = turn(ay, ax, by, bx, dy, dx);
  final cda = turn(cy, cx, dy, dx, ay, ax);
  final cdb = turn(cy, cx, dy, dx, by, bx);
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

bool segmentsCross(
    int ay, int ax, int by, int bx, int cy, int cx, int dy, int dx) {
  final abc = turn(ay, ax, by, bx, cy, cx);
  final abd = turn(ay, ax, by, bx, dy, dx);
  final cda = turn(cy, cx, dy, dx, ay, ax);
  final cdb = turn(cy, cx, dy, dx, by, bx);
  return abc * abd < 0 && cda * cdb < 0;
}

List<int>? segmentIntersection(
    int ay, int ax, int by, int bx, int cy, int cx, int dy, int dx) {
  final denominator = (bx - ax) * (dy - cy) - (by - ay) * (dx - cx);
  if (denominator == 0) return null;
  final t = ((cx - ax) * (dy - cy) - (cy - ay) * (dx - cx)) / denominator;
  final u = ((cx - ax) * (by - ay) - (cy - ay) * (bx - ax)) / denominator;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return [(ay + t * (by - ay)).round(), (ax + t * (bx - ax)).round()];
}

List<int> ringBounds(List<int> ring) {
  final box = [1 << 40, -(1 << 40), 1 << 40, -(1 << 40)];
  for (var i = 0; i < ring.length; i += 2) {
    box[0] = math.min(box[0], ring[i]);
    box[1] = math.max(box[1], ring[i]);
    box[2] = math.min(box[2], ring[i + 1]);
    box[3] = math.max(box[3], ring[i + 1]);
  }
  return box;
}

bool ringsCross(List<int> a, List<int> b) {
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
      if (segmentsIntersect(
          a[j], a[j + 1], a[i], a[i + 1], b[l], b[l + 1], b[k], b[k + 1])) {
        return true;
      }
    }
  }
  return false;
}

int vertexKey(int lat, int lon) => (lat + 10000000) * (1 << 26) + lon;

String degrees(int quantized) => (quantized / 100000).toStringAsFixed(5);

class SegmentIndex {
  final int cellSize;
  final Map<int, List<int>> _cells = {};
  final List<List<int>> _segments = [];

  SegmentIndex({this.cellSize = 2000});

  void addRing(List<int> ring, int owner) {
    for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
      _add([ring[j], ring[j + 1], ring[i], ring[i + 1], owner]);
    }
  }

  void addPolyline(List<int> line, int owner) {
    for (var i = 2; i < line.length; i += 2) {
      _add([line[i - 2], line[i - 1], line[i], line[i + 1], owner]);
    }
  }

  void _add(List<int> segment) {
    final index = _segments.length;
    _segments.add(segment);
    final minLat = math.min(segment[0], segment[2]) ~/ cellSize;
    final maxLat = math.max(segment[0], segment[2]) ~/ cellSize;
    final minLon = math.min(segment[1], segment[3]) ~/ cellSize;
    final maxLon = math.max(segment[1], segment[3]) ~/ cellSize;
    for (var a = minLat; a <= maxLat; a++) {
      for (var b = minLon; b <= maxLon; b++) {
        _cells
            .putIfAbsent((a + 100000) * 200000 + (b + 100000), () => [])
            .add(index);
      }
    }
  }

  Iterable<List<int>> near(int lat, int lon, double metres) sync* {
    final latCells =
        (metres / metresPerDegreeLatitude * 100000 / cellSize).ceil() + 1;
    final lonCells =
        (metres / (lonScaleAt(lat) * 100000) * 100000 / cellSize).ceil() + 1;
    final seen = <int>{};
    final centreLat = lat ~/ cellSize;
    final centreLon = lon ~/ cellSize;
    for (var a = centreLat - latCells; a <= centreLat + latCells; a++) {
      for (var b = centreLon - lonCells; b <= centreLon + lonCells; b++) {
        for (final index
            in _cells[(a + 100000) * 200000 + (b + 100000)] ?? const <int>[]) {
          if (seen.add(index)) yield _segments[index];
        }
      }
    }
  }
}

class Shape {
  final String id;
  final String name;
  final List<List<int>> rings;

  Shape(this.id, this.name, this.rings);

  bool contains(int lat, int lon) => ringsContain(rings, lat, lon);

  bool touches(List<int> ring) =>
      contains(ring[0], ring[1]) ||
      rings.any(
          (own) => ringsCross(own, ring) || ringContains(ring, own[0], own[1]));

  double depthMetres(int lat, int lon) {
    var best = double.infinity;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
        best = math.min(
            best,
            pointSegmentMetres(
                lat, lon, ring[j], ring[j + 1], ring[i], ring[i + 1]));
      }
    }
    return best;
  }

  List<int> get bounds {
    final box = [1 << 40, -(1 << 40), 1 << 40, -(1 << 40)];
    for (final ring in rings) {
      final b = ringBounds(ring);
      box[0] = math.min(box[0], b[0]);
      box[1] = math.max(box[1], b[1]);
      box[2] = math.min(box[2], b[2]);
      box[3] = math.max(box[3], b[3]);
    }
    return box;
  }
}

List<int> reversedLine(List<int> line) => [
      for (var i = line.length - 2; i >= 0; i -= 2) ...[line[i], line[i + 1]]
    ];

List<int> ringCentroid(List<int> ring) {
  var lat = 0;
  var lon = 0;
  for (var i = 0; i < ring.length; i += 2) {
    lat += ring[i];
    lon += ring[i + 1];
  }
  final n = ring.length ~/ 2;
  return [lat ~/ n, lon ~/ n];
}

List<int> lineMidpoint(List<int> line) {
  if (line.length < 4) return [line[0], line[1]];
  final i = (line.length ~/ 4) * 2;
  final j = math.min(i + 2, line.length - 2);
  return [(line[i] + line[j]) ~/ 2, (line[i + 1] + line[j + 1]) ~/ 2];
}

Map<String, Shape> readShapes(String geoJson) {
  final features = (json.decode(geoJson) as Map)['features'] as List;
  final shapes = <String, Shape>{};
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
    shapes[id] = Shape(id, properties['shapeName'] as String, rings);
  }
  return shapes;
}

class PolygonIndex {
  static const int bandSize = 1000;
  final Map<int, List<List<int>>> _bands = {};

  PolygonIndex(Iterable<List<int>> rings) {
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
        if (ring[i] == ring[j]) continue;
        final segment = [ring[j], ring[j + 1], ring[i], ring[i + 1]];
        final low = math.min(ring[i], ring[j]) ~/ bandSize;
        final high = math.max(ring[i], ring[j]) ~/ bandSize;
        for (var band = low; band <= high; band++) {
          _bands.putIfAbsent(band, () => []).add(segment);
        }
      }
    }
  }

  bool contains(int lat, int lon) {
    var inside = false;
    for (final s in _bands[lat ~/ bandSize] ?? const <List<int>>[]) {
      if ((s[0] > lat) == (s[2] > lat)) continue;
      if (lon < s[1] + (lat - s[0]) * (s[3] - s[1]) / (s[2] - s[0])) {
        inside = !inside;
      }
    }
    return inside;
  }
}
