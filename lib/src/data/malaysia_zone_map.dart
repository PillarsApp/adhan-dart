import 'dart:math' as math;

import 'date_components.dart';

/// Decodes `malaysia_zones.txt` and resolves a point and date to a zone code.
///
/// docs/MALAYSIA_TIMES_MAINTENANCE.md describes the format and the resolution
/// order.
class MalaysiaZoneMap {
  final List<MalaysiaZone> zones;
  final List<MalaysiaSpecialArea> specialAreas;
  final List<_Region> _regions;
  final Map<String, MalaysiaZone> _zonesByCode;

  static const int boundaryToleranceMetres = 500;

  MalaysiaZoneMap._(this.zones, this.specialAreas, this._regions)
      : _zonesByCode = {for (final zone in zones) zone.code: zone};

  static MalaysiaZoneMap parse(String text) {
    final zones = <MalaysiaZone>[];
    final specialAreas = <MalaysiaSpecialArea>[];
    final arcs = <List<int>>[];
    final regions = <_Region>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\t');
      switch (fields[0]) {
        case 'Z':
          zones.add(MalaysiaZone._(
              fields[1],
              fields[2],
              fields[3],
              _dayFromIso(fields[4], 0),
              _dayFromIso(fields[5], 99999999),
              fields[6].isEmpty ? const [] : fields[6].split(' '),
              double.parse(fields[7]),
              double.parse(fields[8])));
          break;
        case 'S':
          specialAreas.add(MalaysiaSpecialArea._(
              fields[1],
              fields[2],
              double.parse(fields[3]),
              double.parse(fields[4]),
              int.parse(fields[5])));
          break;
        case 'A':
          arcs.add(decodePolyline(fields[1]));
          break;
        case 'R':
          regions.add(_Region([
            for (final index in fields[1].split(' ')) arcs[int.parse(index)]
          ], [
            for (final row in fields[2].split(' ')) _ZoneRow.parse(row)
          ]));
          break;
        default:
          throw FormatException('unknown record type ${fields[0]}');
      }
    }
    return MalaysiaZoneMap._(zones, specialAreas, regions);
  }

  MalaysiaZone? zone(String code) => _zonesByCode[code];

  /// Indices of every region that encloses the point. More than one means
  /// the source polygons overlap there; the resolver takes the first.
  List<int> regionsAt(double latitude, double longitude) {
    final lat = quantize(latitude);
    final lon = quantize(longitude);
    return [
      for (var i = 0; i < _regions.length; i++)
        if (_regions[i].contains(lat, lon)) i
    ];
  }

  String? zoneAt(double latitude, double longitude, DateComponents date) {
    final day = date.year * 10000 + date.month * 100 + date.day;
    final region = _regionAt(latitude, longitude);
    String? districtZone;
    if (region != null) {
      for (final row in region.rows) {
        final zone = _zonesByCode[row.zone];
        if (zone != null &&
            zone.inForce(day) &&
            row.matches(latitude, longitude)) {
          districtZone = zone.code;
          break;
        }
      }
    }
    final districtState = _zonesByCode[districtZone]?.state;
    for (final area in specialAreas) {
      final zone = _zonesByCode[area.zone];
      if (zone == null || !zone.inForce(day)) continue;
      if (distanceMetres(latitude, longitude, area.latitude, area.longitude) >
          area.radiusMetres) {
        continue;
      }
      if (districtState == null || districtState == zone.state) {
        return zone.code;
      }
    }
    return districtZone;
  }

  _Region? _regionAt(double latitude, double longitude) {
    final lat = quantize(latitude);
    final lon = quantize(longitude);
    for (final region in _regions) {
      if (region.contains(lat, lon)) return region;
    }
    _Region? nearest;
    var nearestMetres = boundaryToleranceMetres.toDouble();
    for (final region in _regions) {
      if (!region.nearBounds(lat, lon, nearestMetres)) continue;
      final metres = region.distanceMetres(lat, lon);
      if (metres <= nearestMetres) {
        nearest = region;
        nearestMetres = metres;
      }
    }
    return nearest;
  }

  static int quantize(double degrees) => (degrees * 100000).round();

  static int _dayFromIso(String iso, int whenEmpty) => iso.isEmpty
      ? whenEmpty
      : int.parse(iso.substring(0, 4)) * 10000 +
          int.parse(iso.substring(5, 7)) * 100 +
          int.parse(iso.substring(8, 10));

  static List<int> decodePolyline(String encoded) {
    final values = <int>[];
    var index = 0;
    var lat = 0;
    var lon = 0;
    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final delta = (result & 1) == 1 ? ~(result >> 1) : result >> 1;
      if (values.length.isEven) {
        lat += delta;
        values.add(lat);
      } else {
        lon += delta;
        values.add(lon);
      }
    }
    return values;
  }

  static String encodePolyline(List<int> latLonPairs) {
    final out = StringBuffer();
    var previousLat = 0;
    var previousLon = 0;
    for (var i = 0; i < latLonPairs.length; i += 2) {
      _encodeValue(latLonPairs[i] - previousLat, out);
      _encodeValue(latLonPairs[i + 1] - previousLon, out);
      previousLat = latLonPairs[i];
      previousLon = latLonPairs[i + 1];
    }
    return out.toString();
  }

  static void _encodeValue(int value, StringBuffer out) {
    var v = value < 0 ? ~(value << 1) : value << 1;
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }
}

class MalaysiaZone {
  final String code;
  final String state;
  final String areas;
  final int validFromDay;
  final int validToDay;
  final List<String> successors;
  final double referenceLatitude;
  final double referenceLongitude;

  MalaysiaZone._(
      this.code,
      this.state,
      this.areas,
      this.validFromDay,
      this.validToDay,
      this.successors,
      this.referenceLatitude,
      this.referenceLongitude);

  bool inForce(int day) => day >= validFromDay && day <= validToDay;

  bool inForceOn(DateComponents date) =>
      inForce(date.year * 10000 + date.month * 100 + date.day);
}

class MalaysiaSpecialArea {
  final String zone;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMetres;

  MalaysiaSpecialArea._(
      this.zone, this.name, this.latitude, this.longitude, this.radiusMetres);
}

const double _metresPerDegreeLatitude = 110574;
const double _metresPerDegreeLongitudeAtEquator = 111320;

double distanceMetres(double lat1, double lon1, double lat2, double lon2) {
  final dy = (lat2 - lat1) * _metresPerDegreeLatitude;
  final dx = (lon2 - lon1) *
      _metresPerDegreeLongitudeAtEquator *
      math.cos((lat1 + lat2) / 2 * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

class _ZoneRow {
  final String zone;
  final List<_Comparison> rule;

  _ZoneRow(this.zone, this.rule);

  static _ZoneRow parse(String text) {
    final colon = text.indexOf(':');
    if (colon < 0) return _ZoneRow(text, const []);
    return _ZoneRow(text.substring(0, colon), [
      for (final part in text.substring(colon + 1).split('&'))
        _Comparison.parse(part)
    ]);
  }

  bool matches(double latitude, double longitude) {
    for (final comparison in rule) {
      if (!comparison.matches(latitude, longitude)) return false;
    }
    return true;
  }
}

class _Comparison {
  final bool onLatitude;
  final String operator;
  final double value;

  _Comparison(this.onLatitude, this.operator, this.value);

  static final _pattern = RegExp(r'^(lat|lon)(<=|>=|<|>)(-?\d+(?:\.\d+)?)$');

  static _Comparison parse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) throw FormatException('malformed rule $text');
    return _Comparison(match.group(1) == 'lat', match.group(2)!,
        double.parse(match.group(3)!));
  }

  bool matches(double latitude, double longitude) {
    final subject = onLatitude ? latitude : longitude;
    switch (operator) {
      case '<':
        return subject < value;
      case '<=':
        return subject <= value;
      case '>':
        return subject > value;
      default:
        return subject >= value;
    }
  }
}

class _Region {
  final List<List<int>> arcs;
  final List<_ZoneRow> rows;
  int minLat = 1 << 40;
  int maxLat = -(1 << 40);
  int minLon = 1 << 40;
  int maxLon = -(1 << 40);

  _Region(this.arcs, this.rows) {
    for (final arc in arcs) {
      for (var i = 0; i < arc.length; i += 2) {
        if (arc[i] < minLat) minLat = arc[i];
        if (arc[i] > maxLat) maxLat = arc[i];
        if (arc[i + 1] < minLon) minLon = arc[i + 1];
        if (arc[i + 1] > maxLon) maxLon = arc[i + 1];
      }
    }
  }

  bool contains(int lat, int lon) {
    if (lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) {
      return false;
    }
    var inside = false;
    for (final arc in arcs) {
      for (var i = 2; i < arc.length; i += 2) {
        final lat1 = arc[i - 2];
        final lon1 = arc[i - 1];
        final lat2 = arc[i];
        final lon2 = arc[i + 1];
        if ((lat1 > lat) == (lat2 > lat)) continue;
        final left = (lon - lon1) * (lat2 - lat1);
        final right = (lat - lat1) * (lon2 - lon1);
        if (lat2 > lat1 ? left < right : left > right) inside = !inside;
      }
    }
    return inside;
  }

  bool nearBounds(int lat, int lon, double metres) {
    final latMargin = (metres / _metresPerDegreeLatitude * 100000).ceil();
    final lonMargin = (metres /
            (_metresPerDegreeLongitudeAtEquator *
                math.cos(lat / 100000 * math.pi / 180)) *
            100000)
        .ceil();
    return lat >= minLat - latMargin &&
        lat <= maxLat + latMargin &&
        lon >= minLon - lonMargin &&
        lon <= maxLon + lonMargin;
  }

  double distanceMetres(int lat, int lon) {
    final lonScale = _metresPerDegreeLongitudeAtEquator *
        math.cos(lat / 100000 * math.pi / 180) /
        100000;
    const latScale = _metresPerDegreeLatitude / 100000;
    var best = double.infinity;
    for (final arc in arcs) {
      for (var i = 2; i < arc.length; i += 2) {
        final y1 = (arc[i - 2] - lat) * latScale;
        final x1 = (arc[i - 1] - lon) * lonScale;
        final y2 = (arc[i] - lat) * latScale;
        final x2 = (arc[i + 1] - lon) * lonScale;
        final dx = x2 - x1;
        final dy = y2 - y1;
        final lengthSquared = dx * dx + dy * dy;
        var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared;
        t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
        final px = x1 + t * dx;
        final py = y1 + t * dy;
        final d = px * px + py * py;
        if (d < best) best = d;
      }
    }
    return math.sqrt(best);
  }
}
