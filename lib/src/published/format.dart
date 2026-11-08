part of 'published_timetable.dart';

const String _magicLine = 'OTT 1';
const int _int32Max = 2147483647;
const int _lf = 0x0A;
const int _cr = 0x0D;
const int _space = 0x20;

final RegExp _localityIdPattern = RegExp(r'^[A-Za-z0-9_.-]{1,32}$');

final DateTime _epoch = DateTime.utc(1970);

int _dayNumber(DateComponents date) =>
    DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

DateComponents _dateOfDay(int dayNumber) =>
    DateComponents.from(_epoch.add(Duration(days: dayNumber)));

int _dateKey(DateComponents date) =>
    date.year * 10000 + date.month * 100 + date.day;

int? _digits(String text) {
  if (text.isEmpty) return null;
  for (final unit in text.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return null;
  }
  return int.parse(text);
}

DateComponents _parseDate(Object? value, String what) {
  if (value is! String ||
      value.length != 10 ||
      value[4] != '-' ||
      value[7] != '-') {
    throw FormatException('$what is not a YYYY-MM-DD date');
  }
  final year = _digits(value.substring(0, 4));
  final month = _digits(value.substring(5, 7));
  final day = _digits(value.substring(8, 10));
  if (year == null || month == null || day == null) {
    throw FormatException('$what is not a YYYY-MM-DD date');
  }
  final resolved = DateTime.utc(year, month, day);
  if (resolved.year != year || resolved.month != month || resolved.day != day) {
    throw FormatException('$what is not a calendar day');
  }
  return DateComponents(year, month, day);
}

Map<String, Object?> _object(Object? value, String what) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$what is not a JSON object');
}

List<Object?> _list(Object? value, String what, {int minLength = 0}) {
  if (value is! List<Object?>) throw FormatException('$what is not an array');
  if (value.length < minLength) {
    throw FormatException('$what has fewer than $minLength entries');
  }
  return value;
}

String _string(Object? value, String what, {bool allowEmpty = false}) {
  if (value is! String) throw FormatException('$what is not a string');
  if (!allowEmpty && value.isEmpty) throw FormatException('$what is empty');
  return value;
}

String _token(Object? value, String what) {
  final text = _string(value, what);
  if (text.contains(RegExp(r'\s'))) {
    throw FormatException('$what contains whitespace');
  }
  return text;
}

int _int(Object? value, String what,
    {int min = -_int32Max - 1, int max = _int32Max}) {
  if (value is! int) throw FormatException('$what is not an integer');
  if (value < min || value > max) {
    throw FormatException('$what is outside $min to $max');
  }
  return value;
}

PublishedColumn _parseColumn(Object? value) {
  final name = _string(value, 'a column name');
  for (final column in PublishedColumn.values) {
    if (column.name == name) return column;
  }
  throw FormatException('$name is not a column name');
}

final class _ZoneOffsets {
  final String id;
  final List<int> days;
  final List<int> minutes;

  _ZoneOffsets(this.id, this.days, this.minutes);

  int offsetOn(int dayNumber) {
    var offset = minutes.first;
    for (var i = 1; i < days.length && days[i] <= dayNumber; i++) {
      offset = minutes[i];
    }
    return offset;
  }

  static _ZoneOffsets parse(Object? value, int coverageStart) {
    final zone = _object(value, 'a zone');
    final id = _string(zone['id'], 'a zone id');
    final days = <int>[];
    final minutes = <int>[];
    for (final entry
        in _list(zone['offsets'], 'offsets of $id', minLength: 1)) {
      final pair = _list(entry, 'an offset of $id');
      if (pair.length != 2) {
        throw FormatException('an offset of $id is not [date, minutes]');
      }
      final day = _dayNumber(_parseDate(pair[0], 'an offset date of $id'));
      if (days.isNotEmpty && day <= days.last) {
        throw FormatException('offset dates of $id are not ascending');
      }
      days.add(day);
      minutes.add(_int(pair[1], 'an offset of $id', min: -1440, max: 1440));
    }
    if (days.first > coverageStart) {
      throw FormatException('the first offset of $id is after coverage starts');
    }
    return _ZoneOffsets(id, days, minutes);
  }
}

sealed class _Geometry {
  const _Geometry();
}

final class _PointGeometry extends _Geometry {
  final int radiusMetres;

  const _PointGeometry(this.radiusMetres);
}

final class _AreaGeometry extends _Geometry {
  final List<List<int>> rings;
  final int toleranceMetres;

  const _AreaGeometry(this.rings, this.toleranceMetres);
}

final class _LocalityRecord {
  final Locality locality;
  final int zone;
  final _Geometry geometry;

  _LocalityRecord(this.locality, this.zone, this.geometry);

  static _LocalityRecord parse(
      Map<String, Object?> json, Set<String> ids, int zoneCount) {
    final id = json['id'] as String;
    final ref = _list(json['ref'], 'ref of $id');
    if (ref.length != 2) throw FormatException('ref of $id is not [lat, lon]');
    final latitude =
        _int(ref[0], 'ref latitude of $id', min: -90000000, max: 90000000);
    final longitude =
        _int(ref[1], 'ref longitude of $id', min: -180000000, max: 180000000);
    final names = <String, String>{};
    for (final entry in _object(json['names'], 'names of $id').entries) {
      names[entry.key] =
          _string(entry.value, 'name ${entry.key} of $id', allowEmpty: true);
    }
    final validFrom = json.containsKey('validFrom')
        ? _parseDate(json['validFrom'], 'validFrom of $id')
        : null;
    final validTo = json.containsKey('validTo')
        ? _parseDate(json['validTo'], 'validTo of $id')
        : null;
    if (validFrom != null &&
        validTo != null &&
        _dateKey(validTo) < _dateKey(validFrom)) {
      throw FormatException('validTo of $id is before validFrom');
    }
    final successors = <LocalityId>[];
    if (json.containsKey('successors')) {
      for (final successor in _list(json['successors'], 'successors of $id')) {
        final code = _string(successor, 'a successor of $id');
        if (!ids.contains(code)) {
          throw FormatException('successor $code of $id is not in the header');
        }
        successors.add(LocalityId(code));
      }
    }
    final locality = Locality._(
        id: LocalityId(id),
        group: _string(json['group'], 'group of $id'),
        names: names,
        referencePoint: Coordinates(latitude / 1000000, longitude / 1000000),
        validFrom: validFrom,
        validTo: validTo,
        successors: successors);
    final zone = _int(json['zone'], 'zone of $id', min: 0, max: zoneCount - 1);
    final hasPoint = json.containsKey('point');
    final hasArea = json.containsKey('area');
    if (hasPoint == hasArea) {
      throw FormatException('$id must have exactly one of point and area');
    }
    if (hasPoint) {
      final point = _object(json['point'], 'point of $id');
      return _LocalityRecord(locality, zone,
          _PointGeometry(_int(point['radiusM'], 'radiusM of $id', min: 1)));
    }
    final area = _object(json['area'], 'area of $id');
    final rings = <List<int>>[];
    for (final polygon
        in _list(area['polygons'], 'polygons of $id', minLength: 1)) {
      rings.add(_parseRing(_string(polygon, 'a polygon of $id'), id));
    }
    return _LocalityRecord(
        locality,
        zone,
        _AreaGeometry(
            rings, _int(area['toleranceM'], 'toleranceM of $id', min: 0)));
  }

  static List<int> _parseRing(String encoded, String id) {
    for (final unit in encoded.codeUnits) {
      if (unit < 63 || unit > 126) {
        throw FormatException('a polygon of $id is not an encoded polyline');
      }
    }
    if (encoded.codeUnitAt(encoded.length - 1) - 63 >= 0x20) {
      throw FormatException('a polygon of $id is truncated');
    }
    final values = MalaysiaZoneMap.decodePolyline(encoded);
    if (values.length.isOdd || values.length < 6) {
      throw FormatException('a ring of $id has fewer than three vertices');
    }
    for (var i = 0; i < values.length; i += 2) {
      if (values[i].abs() > 90000000 || values[i + 1].abs() > 180000000) {
        throw FormatException(
            'a vertex of $id is outside the coordinate range');
      }
    }
    return values;
  }
}

final class _Header {
  final String authority;
  final int revision;
  final String part;
  final DateComponents coverageFrom;
  final DateComponents coverageTo;
  final int firstDay;
  final int lastDay;
  final List<PublishedColumn> columns;
  final List<int> coreIndices;
  final int asrShadow;
  final List<_ZoneOffsets> zones;
  final List<_LocalityRecord> localities;
  final Map<String, int> localityIndex;

  _Header._({
    required this.authority,
    required this.revision,
    required this.part,
    required this.coverageFrom,
    required this.coverageTo,
    required this.columns,
    required this.asrShadow,
    required this.zones,
    required this.localities,
  })  : firstDay = _dayNumber(coverageFrom),
        lastDay = _dayNumber(coverageTo),
        coreIndices = [
          for (final column in PublishedColumn.values)
            if (column.isCore) columns.indexOf(column)
        ],
        localityIndex = {
          for (var i = 0; i < localities.length; i++)
            localities[i].locality.id.value: i
        };

  static _Header parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw FormatException('line 2 is not JSON');
    }
    final json = _object(decoded, 'line 2');
    for (final key in [
      'authority',
      'revision',
      'part',
      'coverage',
      'columns',
      'asrShadow',
      'zones',
      'localities'
    ]) {
      if (!json.containsKey(key)) throw FormatException('$key is absent');
    }
    final coverage = _list(json['coverage'], 'coverage');
    if (coverage.length != 2) {
      throw FormatException('coverage is not [from, to]');
    }
    final coverageFrom = _parseDate(coverage[0], 'coverage start');
    final coverageTo = _parseDate(coverage[1], 'coverage end');
    if (_dateKey(coverageTo) < _dateKey(coverageFrom)) {
      throw FormatException('coverage ends before it starts');
    }
    final columns = <PublishedColumn>[];
    for (final name in _list(json['columns'], 'columns')) {
      final column = _parseColumn(name);
      if (columns.contains(column)) {
        throw FormatException('${column.name} appears twice in columns');
      }
      columns.add(column);
    }
    for (final column in PublishedColumn.values) {
      if (column.isCore && !columns.contains(column)) {
        throw FormatException('columns lacks ${column.name}');
      }
    }
    final asrShadow = _int(json['asrShadow'], 'asrShadow', min: 1, max: 2);
    final firstDay = _dayNumber(coverageFrom);
    final zones = [
      for (final zone in _list(json['zones'], 'zones', minLength: 1))
        _ZoneOffsets.parse(zone, firstDay)
    ];
    final localityJson = [
      for (final locality
          in _list(json['localities'], 'localities', minLength: 1))
        _object(locality, 'a locality')
    ];
    final ids = <String>{};
    for (final locality in localityJson) {
      final id = _string(locality['id'], 'a locality id');
      if (!_localityIdPattern.hasMatch(id)) {
        throw FormatException('locality id "$id" is malformed');
      }
      if (!ids.add(id)) throw FormatException('locality id $id is duplicated');
    }
    return _Header._(
        authority: _token(json['authority'], 'authority'),
        revision: _int(json['revision'], 'revision', min: 0),
        part: _token(json['part'], 'part'),
        coverageFrom: coverageFrom,
        coverageTo: coverageTo,
        columns: List.unmodifiable(columns),
        asrShadow: asrShadow,
        zones: zones,
        localities: [
          for (final locality in localityJson)
            _LocalityRecord.parse(locality, ids, zones.length)
        ]);
  }
}

final class _RowLine {
  final int locality;
  final int firstDay;
  final int year;
  final int cellsStart;
  final int cellsEnd;
  List<List<int>>? days;

  _RowLine(
      this.locality, this.firstDay, this.year, this.cellsStart, this.cellsEnd);
}

List<List<_RowLine>> _indexLines(Uint8List bytes, int start, _Header header) {
  final lines = [for (final _ in header.localities) <_RowLine>[]];
  final cellCount = header.columns.length * 4;
  var position = start;
  while (position < bytes.length) {
    final end = bytes.indexOf(_lf, position);
    final firstSpace = bytes.indexOf(_space, position);
    final secondSpace =
        firstSpace < 0 ? -1 : bytes.indexOf(_space, firstSpace + 1);
    if (firstSpace < 0 ||
        secondSpace < 0 ||
        firstSpace > end ||
        secondSpace > end) {
      throw FormatException('a row line does not have three fields');
    }
    final thirdSpace = bytes.indexOf(_space, secondSpace + 1);
    if (thirdSpace >= 0 && thirdSpace < end) {
      throw FormatException('a row line has more than three fields');
    }
    final id = String.fromCharCodes(bytes, position, firstSpace);
    final locality = header.localityIndex[id];
    if (locality == null) {
      throw FormatException('row locality $id is not in the header');
    }
    final date = _parseDate(
        String.fromCharCodes(bytes, firstSpace + 1, secondSpace),
        'the first date of a row of $id');
    final firstDay = _dayNumber(date);
    if (firstDay < header.firstDay || firstDay > header.lastDay) {
      throw FormatException('a row of $id starts outside coverage');
    }
    final cellsStart = secondSpace + 1;
    if (end - cellsStart < cellCount) {
      throw FormatException(
          'the first day of a row of $id has fewer than $cellCount digits');
    }
    for (var i = cellsStart; i < cellsStart + cellCount; i++) {
      if (bytes[i] < 0x30 || bytes[i] > 0x39) {
        throw FormatException('the first day of a row of $id is not digits');
      }
    }
    lines[locality]
        .add(_RowLine(locality, firstDay, date.year, cellsStart, end));
    position = end + 1;
  }
  for (final localityLines in lines) {
    localityLines.sort((a, b) => a.firstDay.compareTo(b.firstDay));
  }
  return lines;
}
