import 'dart:convert';
import 'dart:io';

import 'package:adhan/src/data/malaysia_times_codec.dart';
import 'package:adhan/src/data/malaysia_times_data.dart';
import 'package:test/test.dart';

import '../bin/src/csv.dart';
import '../bin/src/malaysia_timetables.dart';

const _months = [
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

int _minutes(String clock) {
  final match = RegExp(r'^(\d{2}):(\d{2})(?::00)?$').firstMatch(clock);
  if (match == null) throw FormatException('Unreadable time', clock);
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

String _isoDate(String esolatDate) {
  final parts = esolatDate.split('-');
  final month = _months.indexOf(parts[1]) + 1;
  return '${parts[2]}-${month.toString().padLeft(2, '0')}-${parts[0]}';
}

String _isoOfDayIndex(int year, int index) {
  final date = DateTime.utc(year, 1, 1).add(Duration(days: index));
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

void main() {
  final zoneYears = decodeMalaysiaTimes(malaysiaTimesData);
  final byKey = {for (final z in zoneYears) '${z.zone} ${z.year}': z};

  final esolatFiles = Directory('tool/malaysia/raw/esolat')
      .listSync()
      .whereType<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final esolatRows = <String, List<Map<String, dynamic>>>{};
  for (final file in esolatFiles) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(r'^(\w+)_(\d{4})\.json\.gz$').firstMatch(name)!;
    final response =
        jsonDecode(utf8.decode(GZipCodec().decode(file.readAsBytesSync())))
            as Map<String, dynamic>;
    final rows = response['prayerTime'];
    if (rows is List && rows.isNotEmpty) {
      esolatRows['${match.group(1)} ${match.group(2)}'] =
          rows.cast<Map<String, dynamic>>();
    }
  }
  final selangorSources = readCsv(File('tool/malaysia/selangor_sources.csv'));

  final corrections = <String, int>{};
  for (final row in readCsv(File('tool/malaysia/corrections.csv'))) {
    if (row['published'] != row['corrected']) {
      corrections['${row['zone']} ${row['date']} ${row['field']}'] =
          _minutes(row['corrected']!);
    }
  }

  test(
      'holds every e-Solat zone-year with rows and the nine Selangor districts',
      () {
    final expected = <String>{
      ...esolatRows.keys,
      for (final row in selangorSources) '${row['zone']} ${row['year']}',
    };
    expect(selangorSources, hasLength(9));
    expect(byKey.keys.toSet(), expected);
    expect(zoneYears, hasLength(117));
  });

  test('every value equals its source and only the corrections differ', () {
    final differing = <String, int>{};
    for (final zoneYear in zoneYears) {
      final key = '${zoneYear.zone} ${zoneYear.year}';
      final List<List<int>> source;
      if (esolatRows.containsKey(key)) {
        source = [
          for (final row in esolatRows[key]!)
            [for (final field in timeFields) _minutes(row[field] as String)],
        ];
        expect([
          for (final row in esolatRows[key]!) _isoDate(row['date'] as String)
        ], [
          for (var i = 0; i < source.length; i++)
            _isoOfDayIndex(zoneYear.year, i)
        ], reason: key);
      } else {
        final text = GZipCodec().decode(File(
                'tool/malaysia/raw/selangor/${zoneYear.zone}_${zoneYear.year}.txt.gz')
            .readAsBytesSync());
        source = parseSelangorText(utf8.decode(text), zoneYear.year);
      }
      expect(zoneYear.days.length, source.length, reason: key);
      for (var d = 0; d < source.length; d++) {
        for (var f = 0; f < timeFields.length; f++) {
          if (zoneYear.days[d][f] != source[d][f]) {
            differing[
                    '${zoneYear.zone} ${_isoOfDayIndex(zoneYear.year, d)} ${timeFields[f]}'] =
                zoneYear.days[d][f];
          }
        }
      }
    }
    expect(differing, corrections);
    expect(corrections, hasLength(8));
  });

  test('the Dart constant equals the data file byte for byte', () {
    expect(File('data/malaysia/malaysia_times.txt').readAsStringSync(),
        malaysiaTimesData);
  });

  test('encoding the decoded text returns the same text', () {
    expect(encodeMalaysiaTimes(zoneYears), malaysiaTimesData);
  });

  test('codec uses letters for small steps and absolute values for jumps', () {
    final days = [
      [300, 310, 420, 445, 730, 940, 1100, 1160],
      [301, 309, 423, 440, 730, 937, 1099, 1160],
    ];
    final text = encodeMalaysiaTimes([MalaysiaZoneYear('XXX01', 2026, days)]);
    expect(text, 'XXX01 2026 05000510070007251210154018201920ecg~0720dacd\n');
    expect(decodeMalaysiaTimes(text).single.days, days);
  });
}
