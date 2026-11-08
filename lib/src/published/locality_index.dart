part of 'published_timetable.dart';

const double _earthRadiusMetres = 6371008.8;
const double _metresPerDegreeLatitude = 110574;
const double _metresPerDegreeLongitudeAtEquator = 111320;

double _radians(double degrees) => degrees * math.pi / 180;

void _requireFinite(Coordinates coordinates) {
  if (!coordinates.latitude.isFinite) {
    throw ArgumentError.value(
        coordinates.latitude, 'latitude', 'must be a finite number');
  }
  if (!coordinates.longitude.isFinite) {
    throw ArgumentError.value(
        coordinates.longitude, 'longitude', 'must be a finite number');
  }
}

_LocalityRecord? _resolveLocality(List<_LocalityRecord> records,
    Coordinates coordinates, DateComponents date) {
  _requireFinite(coordinates);
  final latitude = coordinates.latitude;
  final longitude = coordinates.longitude;
  _LocalityRecord? nearest;
  var nearestMm = 0;
  for (final record in records) {
    final geometry = record.geometry;
    if (geometry is! _PointGeometry || !record.locality.inForceOn(date)) {
      continue;
    }
    final reference = record.locality.referencePoint;
    final mm = _haversineMm(
        latitude, longitude, reference.latitude, reference.longitude);
    if (mm > geometry.radiusMetres * 1000) continue;
    if (nearest == null ||
        mm < nearestMm ||
        (mm == nearestMm &&
            record.locality.id.value.compareTo(nearest.locality.id.value) <
                0)) {
      nearest = record;
      nearestMm = mm;
    }
  }
  if (nearest != null) return nearest;
  final quantizedLatitude = (latitude * 1000000).round();
  final quantizedLongitude = (longitude * 1000000).round();
  for (final record in records) {
    final geometry = record.geometry;
    if (geometry is! _AreaGeometry || !record.locality.inForceOn(date)) {
      continue;
    }
    if (_contains(geometry.rings, quantizedLatitude, quantizedLongitude) ||
        _edgeDistanceMm(latitude, longitude, geometry.rings) <=
            geometry.toleranceMetres * 1000) {
      return record;
    }
  }
  return null;
}

int _haversineMm(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _radians(lat1);
  final phi2 = _radians(lat2);
  final dPhi = _radians(lat2 - lat1);
  final dLambda = _radians(lon2 - lon1);
  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
  final d = 2 * _earthRadiusMetres * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return (d * 1000).round();
}

bool _contains(List<List<int>> rings, int lat, int lon) {
  var inside = false;
  for (final ring in rings) {
    final vertices = ring.length ~/ 2;
    for (var i = 0; i < vertices; i++) {
      final j = (i + 1) % vertices;
      final lat1 = ring[2 * i];
      final lon1 = ring[2 * i + 1];
      final lat2 = ring[2 * j];
      final lon2 = ring[2 * j + 1];
      if ((lat1 > lat) == (lat2 > lat)) continue;
      final left = (lon - lon1) * (lat2 - lat1);
      final right = (lat - lat1) * (lon2 - lon1);
      if (lat2 > lat1 ? left < right : left > right) inside = !inside;
    }
  }
  return inside;
}

int _edgeDistanceMm(double lat0, double lon0, List<List<int>> rings) {
  final perDegreeLongitude =
      _metresPerDegreeLongitudeAtEquator * math.cos(_radians(lat0));
  var best = double.infinity;
  for (final ring in rings) {
    final vertices = ring.length ~/ 2;
    for (var i = 0; i < vertices; i++) {
      final j = (i + 1) % vertices;
      final y1 = (ring[2 * i] / 1e6 - lat0) * _metresPerDegreeLatitude;
      final x1 = (ring[2 * i + 1] / 1e6 - lon0) * perDegreeLongitude;
      final y2 = (ring[2 * j] / 1e6 - lat0) * _metresPerDegreeLatitude;
      final x2 = (ring[2 * j + 1] / 1e6 - lon0) * perDegreeLongitude;
      final dx = x2 - x1;
      final dy = y2 - y1;
      final lengthSquared = dx * dx + dy * dy;
      var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared;
      t = t.clamp(0.0, 1.0);
      final px = x1 + t * dx;
      final py = y1 + t * dy;
      best = math.min(best, math.sqrt(px * px + py * py));
    }
  }
  return (best * 1000).round();
}
