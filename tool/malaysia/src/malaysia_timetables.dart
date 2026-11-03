import 'dart:convert';
import 'dart:io';

import 'package:adhan/src/data/malaysia_times_codec.dart';

import 'csv.dart';
import 'malaysia_manifest.dart';

const esolatEndpoint =
    'https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration';

const timeFields = [
  'imsak',
  'fajr',
  'syuruk',
  'dhuha',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];

const _fajr = 1;
const _syuruk = 2;
const _dhuhr = 4;
const _asr = 5;
const _maghrib = 6;
const _isha = 7;
const _coreOrder = [_fajr, _syuruk, _dhuhr, _asr, _maghrib, _isha];

const _esolatMonths = [
  'Jan',
  'Feb',
  'Mac',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Ogos',
  'Sep',
  'Okt',
  'Nov',
  'Dis',
];

const _selangorMonths = [
  'JANUARI',
  'FEBRUARI',
  'MAC',
  'APRIL',
  'MEI',
  'JUN',
  'JULAI',
  'OGOS',
  'SEPTEMBER',
  'OKTOBER',
  'NOVEMBER',
  'DISEMBER',
];

const _dhuhaMinutesAfterSyuruk = 25;
const _fetchAttempts = 3;
const _fetchPause = Duration(milliseconds: 300);

String _esolatDir(Directory root) => '${root.path}/tool/malaysia/raw/esolat';
String _selangorDir(Directory root) =>
    '${root.path}/tool/malaysia/raw/selangor';
String _selangorCsv(Directory root) =>
    '${root.path}/tool/malaysia/selangor_sources.csv';

List<int> _gzip(List<int> bytes) => GZipCodec(level: 9).encode(bytes);

String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

String _two(int value) => value.toString().padLeft(2, '0');

String _isoDate(int year, int month, int day) =>
    '$year-${_two(month)}-${_two(day)}';

bool _isLeap(int year) => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

List<String> _calendar(int year) {
  final lengths = [
    31,
    _isLeap(year) ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];
  return [
    for (var month = 1; month <= 12; month++)
      for (var day = 1; day <= lengths[month - 1]; day++)
        _isoDate(year, month, day),
  ];
}

int? _parseClock(String text) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
  if (match == null) return null;
  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  final seconds = match.group(3) == null ? 0 : int.parse(match.group(3)!);
  if (hours > 23 || minutes > 59) return null;
  if (seconds != 0) return null;
  return hours * 60 + minutes;
}

const _esolatSource = 'e-solat';
const _selangorSource = 'selangor-pdf';

class _CatalogZone {
  final String code;
  final String source;
  final int validFrom;
  final int validTo;
  final Set<int> unpublished;

  _CatalogZone(
      this.code, this.source, this.validFrom, this.validTo, this.unpublished);

  bool inForceDuring(int year) =>
      validFrom <= year * 10000 + 1231 && validTo >= year * 10000 + 101;
}

int _day(String iso, int whenEmpty) =>
    iso.isEmpty ? whenEmpty : int.parse(iso.replaceAll('-', ''));

List<_CatalogZone> _readCatalog(Directory root) => [
      for (final row in readCsv(File('${root.path}/tool/malaysia/zones.csv')))
        if (row['source'] != _esolatSource && row['source'] != _selangorSource)
          throw FormatException(
              'zones.csv ${row['code']}: unknown source ${row['source']}')
        else
          _CatalogZone(row['code']!, row['source']!,
              _day(row['valid_from']!, 0), _day(row['valid_to']!, 99999999), {
            for (final year in row['unpublished']!.split(' '))
              if (year.isNotEmpty) int.parse(year),
          }),
    ];

class _EsolatResponse {
  final List<Map<String, dynamic>>? rows;
  final String problem;
  final bool isNoRecord;
  final Object? serverTime;

  _EsolatResponse._(this.rows, this.problem, this.isNoRecord,
      [this.serverTime]);

  factory _EsolatResponse.parse(List<int> body) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException catch (error) {
      return _EsolatResponse._(
          null, 'a body that is not JSON: ${error.message}', false);
    }
    if (json is! Map<String, dynamic>) {
      return _EsolatResponse._(null, 'JSON that is not an object', false);
    }
    final rows = json['prayerTime'];
    if (rows is List &&
        rows.isNotEmpty &&
        rows.every((row) => row is Map<String, dynamic>)) {
      return _EsolatResponse._(
          rows.cast<Map<String, dynamic>>(), '', false, json['serverTime']);
    }
    return _EsolatResponse._(
        null, 'status ${json['status']}', json['status'] == 'NO_RECORD!');
  }
}

Future<bool> fetchTimetables(Directory root, List<int> years,
    {bool refresh = false,
    String endpoint = esolatEndpoint,
    Duration pause = _fetchPause}) async {
  final dir = Directory(_esolatDir(root))..createSync(recursive: true);
  final catalog = _readCatalog(root);
  final client = HttpClient();
  var ok = true;
  var requested = false;
  try {
    for (final year in years) {
      for (final zone in catalog) {
        if (zone.source != _esolatSource || !zone.inForceDuring(year)) continue;
        final label = '${zone.code} $year';
        final file = File('${dir.path}/${zone.code}_$year.json.gz');
        final stored = file.existsSync()
            ? _EsolatResponse.parse(GZipCodec().decode(file.readAsBytesSync()))
                .rows
            : null;
        if (!refresh && stored != null) {
          print('$label kept ${stored.length} rows');
          continue;
        }
        if (requested) await Future<void>.delayed(pause);
        requested = true;
        final List<int> body;
        try {
          body = await _fetchZoneYear(client, endpoint, zone.code, year, pause);
        } on StateError catch (error) {
          print('$label: ${error.message}');
          ok = false;
          continue;
        }
        final response = _EsolatResponse.parse(body);
        if (response.rows != null) {
          file.writeAsBytesSync(_gzip(body));
          print('$label ${response.rows!.length} rows');
        } else if (stored != null) {
          print('$label: e-Solat returned ${response.problem}; '
              'kept the stored ${stored.length} rows');
          ok = false;
        } else if (response.isNoRecord) {
          print('$label NO_RECORD!');
        } else {
          print('$label: e-Solat returned ${response.problem}; wrote nothing');
          ok = false;
        }
      }
    }
  } finally {
    client.close();
  }
  return ok;
}

Future<List<int>> _fetchZoneYear(HttpClient client, String endpoint,
    String zone, int year, Duration pause) async {
  Object? lastError;
  for (var attempt = 1; attempt <= _fetchAttempts; attempt++) {
    try {
      final request = await client.postUrl(Uri.parse('$endpoint&zone=$zone'));
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      request.write('datestart=$year-01-01&dateend=$year-12-31');
      final response = await request.close();
      final body = await response.fold<List<int>>([], (all, chunk) {
        all.addAll(chunk);
        return all;
      });
      if (response.statusCode != 200) {
        throw HttpException('status ${response.statusCode}');
      }
      jsonDecode(utf8.decode(body));
      return body;
    } on Exception catch (error) {
      lastError = error;
      if (attempt < _fetchAttempts) await Future<void>.delayed(pause);
    }
  }
  throw StateError('failed after $_fetchAttempts attempts: $lastError');
}

class _SelangorSource {
  final String zone;
  final String district;
  final int year;
  final String url;
  final String retrieved;
  final String pdfSha256;

  _SelangorSource(this.zone, this.district, this.year, this.url, this.retrieved,
      this.pdfSha256);

  String get basename => url.substring(url.lastIndexOf('/') + 1);

  _SelangorSource withSha(String sha) =>
      _SelangorSource(zone, district, year, url, retrieved, sha);
}

const _selangorHeader = 'zone,district,year,url,retrieved,pdf_sha256';

List<_SelangorSource> _readSelangorSources(Directory root) => [
      for (final row in readCsv(File(_selangorCsv(root))))
        _SelangorSource(row['zone']!, row['district']!, int.parse(row['year']!),
            row['url']!, row['retrieved']!, row['pdf_sha256']!),
    ];

void importSelangor(Directory root, List<String> pdfPaths) {
  final sources = _readSelangorSources(root);
  final imported = <String, _SelangorSource>{};
  final texts = <String, String>{};
  for (final path in pdfPaths) {
    final basename = path.substring(path.lastIndexOf('/') + 1);
    final matches = sources.where((source) => source.basename == basename);
    if (matches.length != 1) {
      throw StateError('$path matches ${matches.length} rows of '
          'selangor_sources.csv by URL basename');
    }
    final source = matches.single;
    final result = Process.runSync('pdftotext', ['-layout', path, '-'],
        stdoutEncoding: utf8);
    if (result.exitCode != 0) {
      throw StateError('pdftotext failed on $path: ${result.stderr}');
    }
    final text = result.stdout as String;
    final days = parseSelangorText(text, source.year);
    print('${source.zone} ${source.district} ${source.year}: '
        '${days.length} days');
    texts[source.zone] = text;
    imported[source.zone] =
        source.withSha(sha256Hex(File(path).readAsBytesSync()));
  }
  final dir = Directory(_selangorDir(root))..createSync(recursive: true);
  texts.forEach((zone, text) {
    final source = imported[zone]!;
    File('${dir.path}/${zone}_${source.year}.txt.gz')
        .writeAsBytesSync(_gzip(utf8.encode(text)));
  });
  final rows = [
    for (final source in sources) imported[source.zone] ?? source,
  ];
  File(_selangorCsv(root)).writeAsStringSync('$_selangorHeader\n'
      '${rows.map((s) => [
            s.zone,
            s.district,
            s.year,
            s.url,
            s.retrieved,
            s.pdfSha256,
          ].join(',')).join('\n')}\n');
}

List<List<int>> parseSelangorText(String text, int year) {
  final calendar = _calendar(year);
  final seen = <String>[];
  final days = <List<int>>[];
  int? month;
  final header = RegExp(r'BULAN\s+(\w+)');
  final dayRow = RegExp(r"^\s*[A-Z']+\s+\*?(\d{1,2})\b");
  final time = RegExp(r'\b(\d{1,2}):(\d{2})\b');
  for (final line in text.split('\n')) {
    final headerMatch = header.firstMatch(line);
    if (headerMatch != null) {
      final index = _selangorMonths.indexOf(headerMatch.group(1)!);
      if (index >= 0) {
        month = index + 1;
        continue;
      }
    }
    final times = time.allMatches(line).toList();
    final dayMatch = dayRow.firstMatch(line);
    if (month == null || dayMatch == null || times.length != 7) continue;
    final values = [
      for (final match in times)
        int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!),
    ];
    if (values.any((value) => value >= 1440)) {
      throw FormatException('Time out of range: ${line.trim()}');
    }
    seen.add(_isoDate(year, month, int.parse(dayMatch.group(1)!)));
    days.add([
      values[0],
      values[1],
      values[2],
      values[2] + _dhuhaMinutesAfterSyuruk,
      values[3],
      values[4],
      values[5],
      values[6],
    ]);
  }
  final problem = _calendarProblem(seen, calendar);
  if (problem != null) throw FormatException('Selangor $year: $problem');
  return days;
}

String? _calendarProblem(List<String> dates, List<String> calendar) {
  for (var i = 0; i < calendar.length && i < dates.length; i++) {
    if (dates[i] != calendar[i]) {
      return 'expected ${calendar[i]} but found ${dates[i]}';
    }
  }
  if (dates.length < calendar.length) {
    return 'ends at ${dates.isEmpty ? 'nothing' : dates.last}, '
        'missing ${calendar[dates.length]}';
  }
  if (dates.length > calendar.length) {
    return 'has ${dates.length - calendar.length} rows after ${calendar.last}';
  }
  return null;
}

class _ZoneYear {
  final String zone;
  final int year;
  final List<String> dates;
  final List<List<int>> published;
  final List<List<int>> corrected;

  _ZoneYear(this.zone, this.year, this.dates, this.published)
      : corrected = [for (final day in published) List<int>.of(day)];
}

class _Cell {
  final String zone;
  final String date;
  final String field;

  _Cell(this.zone, this.date, this.field);

  @override
  bool operator ==(Object other) =>
      other is _Cell &&
      other.zone == zone &&
      other.date == date &&
      other.field == field;

  @override
  int get hashCode => Object.hash(zone, date, field);
}

class _Violation {
  final String field;
  final String rule;
  final String detail;

  _Violation(this.field, this.rule, this.detail);
}

DataBuild buildTimetables(Directory root) {
  final errors = <String>[];
  final sources = <ManifestEntry>[];
  final zoneYears = <_ZoneYear>[];

  final esolatFiles = Directory(_esolatDir(root))
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => name.endsWith('.json.gz'))
      .toList()
    ..sort();
  final years = <int>{};
  for (final name in esolatFiles) {
    final match = RegExp(r'^([A-Z0-9]+)_(\d{4})\.json\.gz$').firstMatch(name);
    if (match == null) {
      errors.add('unexpected file in raw/esolat: $name');
      continue;
    }
    final year = int.parse(match.group(2)!);
    years.add(year);
    _loadEsolat(root, name, match.group(1)!, year, zoneYears, sources, errors);
  }
  _loadSelangor(root, zoneYears, sources, errors);
  years.addAll(zoneYears.map((zoneYear) => zoneYear.year));
  _checkCatalog(_readCatalog(root), years, zoneYears, errors);

  zoneYears.sort((a, b) {
    final byYear = a.year.compareTo(b.year);
    return byYear != 0 ? byYear : a.zone.compareTo(b.zone);
  });
  sources.sort((a, b) {
    final byKind = a.kind.compareTo(b.kind);
    if (byKind != 0) return byKind;
    final aKey = _sourceSortKey(a.name);
    final bKey = _sourceSortKey(b.name);
    return aKey.compareTo(bKey);
  });

  final corrected = <_Cell, int>{};
  final waivers = <_Cell, Set<String>>{};
  final correctionCells = <_Cell>{};
  final waiverRules = <String>{};
  _applyCorrections(root, zoneYears, corrected, waivers, correctionCells,
      waiverRules, errors);

  final suppressed = <String>{};
  var rejected = 0;
  for (final zoneYear in zoneYears) {
    final byDate = <String, List<_Violation>>{};
    for (final entry in _violations(zoneYear).entries) {
      final live = <_Violation>[];
      for (final violation in entry.value) {
        final cell = _Cell(zoneYear.zone, entry.key, violation.field);
        final rules = waivers[cell];
        if (rules != null && rules.contains(violation.rule)) {
          suppressed.add('${zoneYear.zone},${entry.key},${violation.field},'
              '${violation.rule}');
        } else {
          live.add(violation);
        }
      }
      if (live.isNotEmpty) byDate[entry.key] = live;
    }
    for (final entry in byDate.entries) {
      rejected++;
      final first = entry.value.first;
      final dayIndex = zoneYear.dates.indexOf(entry.key);
      final fieldIndex = timeFields.indexOf(first.field);
      final value = dayIndex < 0 || fieldIndex < 0
          ? ''
          : ' ${formatMinutes(zoneYear.corrected[dayIndex][fieldIndex])}';
      final more = entry.value
          .skip(1)
          .map((v) => '; ${v.field} ${v.rule}: ${v.detail}')
          .join();
      errors.add('rejected ${zoneYear.zone} ${entry.key} ${first.field}'
          '$value ${first.rule}: ${first.detail}$more');
    }
  }
  for (final key in waiverRules) {
    if (!suppressed.contains(key)) {
      errors.add('waiver suppresses no violation: $key');
    }
  }

  final lines = encodeMalaysiaTimes([
    for (final zoneYear in zoneYears)
      if (zoneYear.dates.length == _calendar(zoneYear.year).length)
        MalaysiaZoneYear(zoneYear.zone, zoneYear.year, zoneYear.corrected),
  ]);
  final summary = '${zoneYears.length} zone-years, $rejected rejected, '
      '${correctionCells.length} corrected, ${waiverRules.length} waived';
  return DataBuild(errors.isEmpty ? lines : '', errors, sources, summary);
}

void _checkCatalog(List<_CatalogZone> catalog, Set<int> years,
    List<_ZoneYear> zoneYears, List<String> errors) {
  final built = {
    for (final zoneYear in zoneYears) '${zoneYear.zone} ${zoneYear.year}',
  };
  final byCode = {for (final zone in catalog) zone.code: zone};
  for (final zoneYear in zoneYears) {
    final zone = byCode[zoneYear.zone];
    if (zone == null || !zone.inForceDuring(zoneYear.year)) {
      errors.add('${zoneYear.zone} ${zoneYear.year}: zones.csv has no zone '
          '${zoneYear.zone} in force in ${zoneYear.year}');
    }
  }
  for (final year in years.toList()..sort()) {
    for (final zone in catalog.where((zone) => zone.inForceDuring(year))) {
      final label = '${zone.code} $year';
      if (zone.unpublished.contains(year)) {
        if (built.contains(label)) {
          errors.add('$label has rows, but zones.csv lists $year as '
              'unpublished for ${zone.code}');
        }
      } else if (!built.contains(label)) {
        errors.add('$label has no ${zone.source} rows, but zones.csv has '
            '${zone.code} in force in $year');
      }
    }
  }
}

String _sourceSortKey(String name) {
  final parts = name.split(' ');
  return '${parts[1]} ${parts[0]}';
}

void _loadEsolat(
    Directory root,
    String fileName,
    String zone,
    int year,
    List<_ZoneYear> zoneYears,
    List<ManifestEntry> sources,
    List<String> errors) {
  final body = GZipCodec()
      .decode(File('${_esolatDir(root)}/$fileName').readAsBytesSync());
  final response = _EsolatResponse.parse(body);
  final rows = response.rows;
  if (rows == null) {
    errors.add('$zone $year: the stored e-Solat response has no rows '
        '(${response.problem})');
    return;
  }
  final dates = <String>[];
  final days = <List<int>>[];
  for (final fields in rows) {
    final dateMatch = RegExp(r'^(\d{2})-([A-Za-z]+)-(\d{4})$')
        .firstMatch('${fields['date']}');
    final month =
        dateMatch == null ? -1 : _esolatMonths.indexOf(dateMatch.group(2)!);
    if (dateMatch == null || month < 0) {
      errors.add('$zone $year: unreadable date ${fields['date']}');
      return;
    }
    final date = _isoDate(int.parse(dateMatch.group(3)!), month + 1,
        int.parse(dateMatch.group(1)!));
    final day = <int>[];
    for (final field in timeFields) {
      final minutes = _parseClock('${fields[field]}');
      if (minutes == null) {
        errors.add('$zone $date $field: unreadable time or non-zero seconds '
            '"${fields[field]}"');
        return;
      }
      day.add(minutes);
    }
    dates.add(date);
    days.add(day);
  }
  zoneYears.add(_ZoneYear(zone, year, dates, days));
  sources.add(ManifestEntry(
      'esolat',
      '$zone $year',
      '${response.serverTime}'.split(' ').first,
      '$esolatEndpoint&zone=$zone&datestart=$year-01-01&dateend=$year-12-31',
      sha256Hex(body)));
}

void _loadSelangor(Directory root, List<_ZoneYear> zoneYears,
    List<ManifestEntry> sources, List<String> errors) {
  for (final source in _readSelangorSources(root)) {
    final file =
        File('${_selangorDir(root)}/${source.zone}_${source.year}.txt.gz');
    if (!file.existsSync()) {
      errors.add('missing ${file.path}');
      continue;
    }
    final textBytes = GZipCodec().decode(file.readAsBytesSync());
    final List<List<int>> days;
    try {
      days = parseSelangorText(utf8.decode(textBytes), source.year);
    } on FormatException catch (error) {
      errors.add('${source.zone}: ${error.message}');
      continue;
    }
    zoneYears
        .add(_ZoneYear(source.zone, source.year, _calendar(source.year), days));
    sources.add(ManifestEntry('selangor-pdf', '${source.zone} ${source.year}',
        source.retrieved, source.url, source.pdfSha256));
    sources.add(ManifestEntry(
        'selangor-text',
        '${source.zone} ${source.year}',
        source.retrieved,
        'tool/malaysia/raw/selangor/${source.zone}_${source.year}.txt.gz',
        sha256Hex(textBytes)));
  }
}

void _applyCorrections(
    Directory root,
    List<_ZoneYear> zoneYears,
    Map<_Cell, int> corrected,
    Map<_Cell, Set<String>> waivers,
    Set<_Cell> correctionCells,
    Set<String> waiverRules,
    List<String> errors) {
  final file = File('${root.path}/tool/malaysia/corrections.csv');
  final byKey = {
    for (final zoneYear in zoneYears)
      '${zoneYear.zone} ${zoneYear.year}': zoneYear,
  };
  for (final row in readCsv(file)) {
    final label = '${row['zone']} ${row['date']} ${row['field']}';
    final date = row['date']!;
    final zoneYear = byKey['${row['zone']} ${date.split('-').first}'];
    final fieldIndex = timeFields.indexOf(row['field']!);
    if (zoneYear == null) {
      errors.add('correction names a zone-year that is not built: $label');
      continue;
    }
    final dayIndex = zoneYear.dates.indexOf(date);
    if (dayIndex < 0 || fieldIndex < 0) {
      errors.add('correction names an unknown date or field: $label');
      continue;
    }
    final published = _parseClock(row['published']!);
    final replacement = _parseClock(row['corrected']!);
    if (published == null || replacement == null) {
      errors.add('correction has an unreadable time: $label');
      continue;
    }
    final raw = zoneYear.published[dayIndex][fieldIndex];
    if (raw != published) {
      errors.add('correction published value differs from the source: $label '
          'source ${formatMinutes(raw)} csv ${row['published']}');
      continue;
    }
    final cell = _Cell(zoneYear.zone, date, row['field']!);
    final earlier = corrected[cell];
    if (earlier != null && earlier != replacement) {
      errors.add('conflicting corrections for $label');
      continue;
    }
    corrected[cell] = replacement;
    zoneYear.corrected[dayIndex][fieldIndex] = replacement;
    if (replacement == published) {
      waivers.putIfAbsent(cell, () => <String>{}).add(row['rule']!);
      waiverRules.add('${zoneYear.zone},$date,${row['field']},${row['rule']}');
    } else {
      correctionCells.add(cell);
    }
  }
}

Map<String, List<_Violation>> _violations(_ZoneYear zoneYear) {
  final found = <String, List<_Violation>>{};
  void add(String date, _Violation violation) =>
      found.putIfAbsent(date, () => []).add(violation);

  final calendar = _calendar(zoneYear.year);
  final problem = _calendarProblem(zoneYear.dates, calendar);
  if (problem != null) {
    add(zoneYear.dates.isEmpty ? '${zoneYear.year}' : zoneYear.dates.first,
        _Violation('date', 'complete-year', problem));
    return found;
  }
  for (var d = 0; d < zoneYear.dates.length; d++) {
    final date = zoneYear.dates[d];
    final day = zoneYear.corrected[d];
    for (var i = 1; i < _coreOrder.length; i++) {
      final earlier = day[_coreOrder[i - 1]];
      final later = day[_coreOrder[i]];
      if (earlier >= later) {
        final earlierName = timeFields[_coreOrder[i - 1]];
        final laterName = timeFields[_coreOrder[i]];
        add(
            date,
            _Violation(laterName, 'core-order',
                '$earlierName ${formatMinutes(earlier)} >= $laterName ${formatMinutes(later)}'));
      }
    }
    final gap = day[_fajr] - day[0];
    if (gap < 0 || gap > 30) {
      add(
          date,
          _Violation('imsak', 'imsak-gap',
              'fajr ${formatMinutes(day[_fajr])} is $gap minutes after imsak ${formatMinutes(day[0])}'));
    }
    if (d > 0) {
      final previous = zoneYear.corrected[d - 1];
      for (var i = 0; i < timeFields.length; i++) {
        final step = day[i] - previous[i];
        if (step.abs() > 3) {
          add(
              date,
              _Violation(timeFields[i], 'daily-step',
                  '${formatMinutes(previous[i])} to ${formatMinutes(day[i])} is $step minutes'));
        }
      }
    }
  }
  return found;
}
