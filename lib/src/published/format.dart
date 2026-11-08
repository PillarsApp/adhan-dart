part of 'published_timetable.dart';

const String _magicLine = 'OTT 1';
const int _int32Max = 2147483647;
const int _int32Min = -2147483648;
const int _maxHeaderDepth = 32;
const int _maxPolylineChunks = 7;
const int _lf = 0x0A;
const int _cr = 0x0D;
const int _space = 0x20;

enum OttRule {
  fileEmpty('file.empty'),
  fileLastLineNoLf('file.lastLineNoLF'),
  fileCr('file.cr'),
  fileBom('file.bom'),
  fileMagic('file.magic'),
  fileHeaderAbsent('file.headerAbsent'),
  headerJson('header.json'),
  headerDuplicateKey('header.duplicateKey'),
  headerKeyAbsent('header.keyAbsent'),
  headerAuthority('header.authority'),
  headerRevision('header.revision'),
  headerPart('header.part'),
  headerCoverage('header.coverage'),
  headerCoverageOrder('header.coverage.order'),
  headerAsrShadow('header.asrShadow'),
  columnUnknown('column.unknown'),
  columnDuplicate('column.duplicate'),
  columnMissingCore('column.missingCore'),
  zonesEmpty('zones.empty'),
  zoneId('zone.id'),
  zoneIdDuplicate('zone.id.duplicate'),
  zoneOffsetsEmpty('zone.offsets.empty'),
  zoneOffsetShape('zone.offset.shape'),
  zoneOffsetDate('zone.offset.date'),
  zoneOffsetOrder('zone.offset.order'),
  zoneOffsetRange('zone.offset.range'),
  zoneOffsetStart('zone.offset.start'),
  localitiesEmpty('localities.empty'),
  localityId('locality.id'),
  localityIdDuplicate('locality.id.duplicate'),
  localityGroup('locality.group'),
  localityZone('locality.zone'),
  localityNames('locality.names'),
  localityRefShape('locality.ref.shape'),
  localityRefInteger('locality.ref.integer'),
  localityRefRange('locality.ref.range'),
  localityValidityDate('locality.validity.date'),
  localityValidityOrder('locality.validity.order'),
  localitySuccessor('locality.successor'),
  localityGeometry('locality.geometry'),
  localityPointRadius('locality.point.radius'),
  localityAreaPolygons('locality.area.polygons'),
  localityAreaTolerance('locality.area.tolerance'),
  localityAreaPolyline('locality.area.polyline'),
  localityAreaRing('locality.area.ring'),
  localityAreaVertex('locality.area.vertex'),
  rowFields('row.fields'),
  rowLocality('row.locality'),
  rowDate('row.date'),
  rowCoverage('row.coverage'),
  rowFirstDayLength('row.firstDay.length'),
  rowFirstDayDigits('row.firstDay.digits'),
  rowCoreOrder('row.coreOrder'),
  rowCrossesYear('row.crossesYear'),
  rowEndsAfterCoverage('row.endsAfterCoverage'),
  rowOverlap('row.overlap');

  const OttRule(this.id);

  final String id;
}

FormatException _violation(OttRule rule, String detail) =>
    FormatException('${rule.id}: $detail');

final RegExp _localityIdPattern = RegExp(r'^[A-Za-z0-9_.-]{1,32}$');
final RegExp _namePattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

final DateTime _epoch = DateTime.utc(1970);

int _dayNumber(DateComponents date) =>
    DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

DateComponents _dateOfDay(int dayNumber) =>
    DateComponents.from(_epoch.add(Duration(days: dayNumber)));

int _dateKey(DateComponents date) =>
    date.year * 10000 + date.month * 100 + date.day;

String _iso(DateComponents date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

bool _isCalendarDay(DateComponents date) {
  final resolved = DateTime.utc(date.year, date.month, date.day);
  return resolved.year == date.year &&
      resolved.month == date.month &&
      resolved.day == date.day;
}

int? _digits(String text) {
  if (text.isEmpty) return null;
  for (final unit in text.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return null;
  }
  return int.parse(text);
}

DateComponents _parseDate(Object? value, OttRule rule, String what) {
  if (value is! String ||
      value.length != 10 ||
      value[4] != '-' ||
      value[7] != '-') {
    throw _violation(rule, '$what is not a YYYY-MM-DD date');
  }
  final year = _digits(value.substring(0, 4));
  final month = _digits(value.substring(5, 7));
  final day = _digits(value.substring(8, 10));
  if (year == null || month == null || day == null) {
    throw _violation(rule, '$what is not a YYYY-MM-DD date');
  }
  final date = DateComponents(year, month, day);
  if (!_isCalendarDay(date)) {
    throw _violation(rule, '$what is not a calendar day');
  }
  return date;
}

Map<String, Object?> _object(Object? value, OttRule rule, String what) {
  if (value is Map<String, Object?>) return value;
  throw _violation(rule, '$what is not a JSON object');
}

List<Object?> _list(Object? value, OttRule rule, String what,
    {int minLength = 0}) {
  if (value is! List<Object?>) throw _violation(rule, '$what is not an array');
  if (value.length < minLength) {
    throw _violation(rule, '$what has fewer than $minLength entries');
  }
  return value;
}

String _string(Object? value, OttRule rule, String what,
    {bool allowEmpty = false}) {
  if (value is! String) throw _violation(rule, '$what is not a string');
  if (!allowEmpty && value.isEmpty) throw _violation(rule, '$what is empty');
  return value;
}

String _name(Object? value, OttRule rule, String what) {
  final text = _string(value, rule, what, allowEmpty: true);
  if (!_namePattern.hasMatch(text)) {
    throw _violation(rule, '$what does not match ${_namePattern.pattern}');
  }
  return text;
}

int _int(Object? value, OttRule rule, String what,
    {int min = -_int32Max - 1, int max = _int32Max}) {
  if (value is! int) throw _violation(rule, '$what is not an integer');
  if (value < min || value > max) {
    throw _violation(rule, '$what is outside $min to $max');
  }
  return value;
}

int _refValue(Object? value, String what, int limit) {
  if (value is! int || value < _int32Min || value > _int32Max) {
    throw _violation(
        OttRule.localityRefInteger, '$what is not a 32-bit integer');
  }
  if (value < -limit || value > limit) {
    throw _violation(
        OttRule.localityRefRange, '$what is outside ${-limit} to $limit');
  }
  return value;
}

PublishedColumn _parseColumn(Object? value) {
  if (value is String) {
    for (final column in PublishedColumn.values) {
      if (column.name == value) return column;
    }
  }
  throw _violation(OttRule.columnUnknown, '$value is not a column name');
}

/// Dart's parser keeps one value of a repeated key silently.
void _rejectDuplicateKeysAndDeepNesting(String header) {
  final frames = <Set<String>?>[];
  var expectKey = false;
  var i = 0;
  while (i < header.length) {
    final unit = header.codeUnitAt(i);
    if (unit == 0x7B || unit == 0x5B) {
      if (frames.length == _maxHeaderDepth) {
        throw _violation(OttRule.headerJson,
            'line 2 nests deeper than $_maxHeaderDepth levels');
      }
      frames.add(unit == 0x7B ? <String>{} : null);
      if (unit == 0x7B) expectKey = true;
    } else if (unit == 0x7D || unit == 0x5D) {
      frames.removeLast();
    } else if (unit == 0x2C) {
      expectKey = frames.last != null;
    } else if (unit == 0x22) {
      var end = i + 1;
      while (header.codeUnitAt(end) != 0x22) {
        if (header.codeUnitAt(end) == 0x5C) end++;
        end++;
      }
      final keys = frames.last;
      if (keys != null && expectKey) {
        final key = jsonDecode(header.substring(i, end + 1)) as String;
        if (!keys.add(key)) {
          throw _violation(OttRule.headerDuplicateKey,
              'key "$key" appears twice in one object');
        }
        expectKey = false;
      }
      i = end;
    }
    i++;
  }
}

/// Dart's parser keeps a lone surrogate escape and a number that overflows to
/// infinity.
void _rejectLoneSurrogatesAndNonFiniteNumbers(Object? value) {
  switch (value) {
    case String():
      for (var i = 0; i < value.length; i++) {
        final unit = value.codeUnitAt(i);
        if (unit < 0xD800 || unit > 0xDFFF) continue;
        final next = i + 1 < value.length ? value.codeUnitAt(i + 1) : 0;
        if (unit <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
          i++;
          continue;
        }
        throw _violation(
            OttRule.headerJson, 'line 2 has a lone surrogate escape');
      }
    case double():
      if (!value.isFinite) {
        throw _violation(
            OttRule.headerJson, 'line 2 has a number that is not finite');
      }
    case Map<String, Object?>():
      for (final entry in value.entries) {
        _rejectLoneSurrogatesAndNonFiniteNumbers(entry.key);
        _rejectLoneSurrogatesAndNonFiniteNumbers(entry.value);
      }
    case List<Object?>():
      value.forEach(_rejectLoneSurrogatesAndNonFiniteNumbers);
  }
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
    final zone = _object(value, OttRule.zoneId, 'a zone');
    final id = _string(zone['id'], OttRule.zoneId, 'a zone id');
    final days = <int>[];
    final minutes = <int>[];
    for (final entry in _list(
        zone['offsets'], OttRule.zoneOffsetsEmpty, 'offsets of $id',
        minLength: 1)) {
      final pair = _list(entry, OttRule.zoneOffsetShape, 'an offset of $id');
      if (pair.length != 2) {
        throw _violation(
            OttRule.zoneOffsetShape, 'an offset of $id is not [date, minutes]');
      }
      final day = _dayNumber(
          _parseDate(pair[0], OttRule.zoneOffsetDate, 'an offset date of $id'));
      if (days.isNotEmpty && day <= days.last) {
        throw _violation(
            OttRule.zoneOffsetOrder, 'offset dates of $id are not ascending');
      }
      days.add(day);
      minutes.add(_int(pair[1], OttRule.zoneOffsetRange, 'an offset of $id',
          min: -1440, max: 1440));
    }
    if (days.first > coverageStart) {
      throw _violation(OttRule.zoneOffsetStart,
          'the first offset of $id is after coverage starts');
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
    final ref = _list(json['ref'], OttRule.localityRefShape, 'ref of $id');
    if (ref.length != 2) {
      throw _violation(
          OttRule.localityRefShape, 'ref of $id is not [lat, lon]');
    }
    final latitude = _refValue(ref[0], 'ref latitude of $id', 90000000);
    final longitude = _refValue(ref[1], 'ref longitude of $id', 180000000);
    final names = <String, String>{};
    for (final entry
        in _object(json['names'], OttRule.localityNames, 'names of $id')
            .entries) {
      names[entry.key] = _string(
          entry.value, OttRule.localityNames, 'name ${entry.key} of $id',
          allowEmpty: true);
    }
    final validFrom = json.containsKey('validFrom')
        ? _parseDate(
            json['validFrom'], OttRule.localityValidityDate, 'validFrom of $id')
        : null;
    final validTo = json.containsKey('validTo')
        ? _parseDate(
            json['validTo'], OttRule.localityValidityDate, 'validTo of $id')
        : null;
    if (validFrom != null &&
        validTo != null &&
        _dateKey(validTo) < _dateKey(validFrom)) {
      throw _violation(
          OttRule.localityValidityOrder, 'validTo of $id is before validFrom');
    }
    final successors = <LocalityId>[];
    if (json.containsKey('successors')) {
      for (final successor in _list(
          json['successors'], OttRule.localitySuccessor, 'successors of $id')) {
        final code =
            _string(successor, OttRule.localitySuccessor, 'a successor of $id');
        if (!ids.contains(code)) {
          throw _violation(OttRule.localitySuccessor,
              'successor $code of $id is not in the header');
        }
        successors.add(LocalityId(code));
      }
    }
    final locality = Locality._(
        id: LocalityId(id),
        group: _string(json['group'], OttRule.localityGroup, 'group of $id'),
        names: names,
        referencePoint: Coordinates(latitude / 1000000, longitude / 1000000),
        validFrom: validFrom,
        validTo: validTo,
        successors: successors);
    final zone = _int(json['zone'], OttRule.localityZone, 'zone of $id',
        min: 0, max: zoneCount - 1);
    final hasPoint = json.containsKey('point');
    final hasArea = json.containsKey('area');
    if (hasPoint == hasArea) {
      throw _violation(OttRule.localityGeometry,
          '$id must have exactly one of point and area');
    }
    if (hasPoint) {
      final point =
          _object(json['point'], OttRule.localityPointRadius, 'point of $id');
      return _LocalityRecord(
          locality,
          zone,
          _PointGeometry(_int(
              point['radiusM'], OttRule.localityPointRadius, 'radiusM of $id',
              min: 1)));
    }
    final area =
        _object(json['area'], OttRule.localityAreaPolygons, 'area of $id');
    final rings = <List<int>>[];
    for (final polygon in _list(
        area['polygons'], OttRule.localityAreaPolygons, 'polygons of $id',
        minLength: 1)) {
      rings.add(_parseRing(
          _string(polygon, OttRule.localityAreaPolyline, 'a polygon of $id'),
          id));
    }
    return _LocalityRecord(
        locality,
        zone,
        _AreaGeometry(
            rings,
            _int(area['toleranceM'], OttRule.localityAreaTolerance,
                'toleranceM of $id',
                min: 0)));
  }

  static List<int> _parseRing(String encoded, String id) {
    FormatException polyline(String detail) =>
        _violation(OttRule.localityAreaPolyline, 'a polygon of $id $detail');
    final values = <int>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      var result = 0;
      var chunks = 0;
      int chunk;
      do {
        if (index == encoded.length) throw polyline('is truncated');
        chunk = encoded.codeUnitAt(index++) - 63;
        if (chunk < 0 || chunk > 63) {
          throw polyline('is not an encoded polyline');
        }
        if (chunks == _maxPolylineChunks) {
          throw polyline('has a value of more than $_maxPolylineChunks chunks');
        }
        result |= (chunk & 0x1f) << (5 * chunks);
        chunks++;
      } while (chunk >= 0x20);
      final delta = (result & 1) == 1 ? ~(result >> 1) : result >> 1;
      if (delta < _int32Min || delta > _int32Max) {
        throw polyline('has a value that does not fit in 32 bits');
      }
      if (values.length.isEven) {
        latitude += delta;
        values.add(latitude);
      } else {
        longitude += delta;
        values.add(longitude);
      }
    }
    if (values.length.isOdd) {
      throw _violation(
          OttRule.localityAreaRing, 'a ring of $id has an odd value count');
    }
    if (values.length < 6) {
      throw _violation(OttRule.localityAreaRing,
          'a ring of $id has fewer than three vertices');
    }
    for (var i = 0; i < values.length; i += 2) {
      final vertexLatitude = values[i];
      final vertexLongitude = values[i + 1];
      if (vertexLatitude < -90000000 ||
          vertexLatitude > 90000000 ||
          vertexLongitude < -180000000 ||
          vertexLongitude > 180000000) {
        throw _violation(OttRule.localityAreaVertex,
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

  static _Header parse(Uint8List bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw _violation(OttRule.headerJson, 'line 2 is not UTF-8');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw _violation(OttRule.headerJson, 'line 2 is not JSON');
    }
    final json = _object(decoded, OttRule.headerJson, 'line 2');
    _rejectDuplicateKeysAndDeepNesting(text);
    _rejectLoneSurrogatesAndNonFiniteNumbers(json);
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
      if (!json.containsKey(key)) {
        throw _violation(OttRule.headerKeyAbsent, '$key is absent');
      }
    }
    final coverage =
        _list(json['coverage'], OttRule.headerCoverage, 'coverage');
    if (coverage.length != 2) {
      throw _violation(OttRule.headerCoverage, 'coverage is not [from, to]');
    }
    final coverageFrom =
        _parseDate(coverage[0], OttRule.headerCoverage, 'coverage start');
    final coverageTo =
        _parseDate(coverage[1], OttRule.headerCoverage, 'coverage end');
    if (_dateKey(coverageTo) < _dateKey(coverageFrom)) {
      throw _violation(
          OttRule.headerCoverageOrder, 'coverage ends before it starts');
    }
    final columns = <PublishedColumn>[];
    for (final name
        in _list(json['columns'], OttRule.columnUnknown, 'columns')) {
      final column = _parseColumn(name);
      if (columns.contains(column)) {
        throw _violation(
            OttRule.columnDuplicate, '${column.name} appears twice in columns');
      }
      columns.add(column);
    }
    for (final column in PublishedColumn.values) {
      if (column.isCore && !columns.contains(column)) {
        throw _violation(
            OttRule.columnMissingCore, 'columns lacks ${column.name}');
      }
    }
    final asrShadow = _int(
        json['asrShadow'], OttRule.headerAsrShadow, 'asrShadow',
        min: 1, max: 2);
    final firstDay = _dayNumber(coverageFrom);
    final zones = <_ZoneOffsets>[];
    final zoneIds = <String>{};
    for (final zone
        in _list(json['zones'], OttRule.zonesEmpty, 'zones', minLength: 1)) {
      final offsets = _ZoneOffsets.parse(zone, firstDay);
      if (!zoneIds.add(offsets.id)) {
        throw _violation(
            OttRule.zoneIdDuplicate, 'zone id ${offsets.id} is duplicated');
      }
      zones.add(offsets);
    }
    final localityJson = [
      for (final locality in _list(
          json['localities'], OttRule.localitiesEmpty, 'localities',
          minLength: 1))
        _object(locality, OttRule.localityId, 'a locality')
    ];
    final ids = <String>{};
    for (final locality in localityJson) {
      final id = _string(locality['id'], OttRule.localityId, 'a locality id');
      if (!_localityIdPattern.hasMatch(id)) {
        throw _violation(OttRule.localityId, 'locality id "$id" is malformed');
      }
      if (!ids.add(id)) {
        throw _violation(
            OttRule.localityIdDuplicate, 'locality id $id is duplicated');
      }
    }
    return _Header._(
        authority:
            _name(json['authority'], OttRule.headerAuthority, 'authority'),
        revision:
            _int(json['revision'], OttRule.headerRevision, 'revision', min: 0),
        part: _name(json['part'], OttRule.headerPart, 'part'),
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

bool _containsBom(Uint8List bytes) {
  for (var i = 0; i + 2 < bytes.length; i++) {
    if (bytes[i] == 0xEF && bytes[i + 1] == 0xBB && bytes[i + 2] == 0xBF) {
      return true;
    }
  }
  return false;
}

List<List<_RowLine>> _indexLines(Uint8List bytes, int start, _Header header) {
  final lines = [for (final _ in header.localities) <_RowLine>[]];
  final cellCount = header.columns.length * 4;
  var position = start;
  while (position < bytes.length) {
    final end = bytes.indexOf(_lf, position);
    final spaces = <int>[];
    for (var i = position; i < end && spaces.length < 3; i++) {
      if (bytes[i] == _space) spaces.add(i);
    }
    if (spaces.length != 2) {
      throw _violation(OttRule.rowFields, 'a row line is not three fields');
    }
    final id = String.fromCharCodes(bytes, position, spaces[0]);
    final locality = header.localityIndex[id];
    if (locality == null) {
      throw _violation(
          OttRule.rowLocality, 'row locality $id is not in the header');
    }
    final date = _parseDate(
        String.fromCharCodes(bytes, spaces[0] + 1, spaces[1]),
        OttRule.rowDate,
        'the first date of a row of $id');
    final firstDay = _dayNumber(date);
    if (firstDay < header.firstDay || firstDay > header.lastDay) {
      throw _violation(
          OttRule.rowCoverage, 'a row of $id starts outside coverage');
    }
    final cellsStart = spaces[1] + 1;
    if (end - cellsStart < cellCount) {
      throw _violation(OttRule.rowFirstDayLength,
          'the first day of a row of $id has fewer than $cellCount digits');
    }
    for (var i = cellsStart; i < cellsStart + cellCount; i++) {
      if (bytes[i] < 0x30 || bytes[i] > 0x39) {
        throw _violation(OttRule.rowFirstDayDigits,
            'the first day of a row of $id is not digits');
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
