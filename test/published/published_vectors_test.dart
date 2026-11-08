import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adhan/adhan.dart';
import 'package:adhan/src/data/delta_cells_codec.dart' show CellRule;
import 'package:adhan/src/published/published_timetable.dart' show OttRule;
import 'package:test/test.dart';

const _vectorsDir = 'test/published/vectors';

Uint8List _bytes(String path) => File('$_vectorsDir/$path').readAsBytesSync();

DateComponents _date(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return DateComponents(parts[0], parts[1], parts[2]);
}

CalculationParameters _parameters(Madhab madhab) =>
    CalculationMethod.umm_al_qura.getParameters()..madhab = madhab;

final _riyadh = Coordinates(24.7136, 46.6753);

(String, String) _outcome(Uint8List bytes) {
  try {
    final timetable = PublishedTimetable.decode(bytes);
    try {
      timetable.validateAllRows();
      return ('accepted', '');
    } on FormatException catch (error) {
      return ('validate', error.message);
    }
  } on FormatException catch (error) {
    return ('decode', error.message);
  }
}

void main() {
  final expected =
      jsonDecode(File('$_vectorsDir/expected.json').readAsStringSync())
          as Map<String, dynamic>;
  final cases = (expected['cases'] as List).cast<Map<String, dynamic>>();
  final vectors = <String, PublishedTimetable>{
    for (final name in cases.map((c) => c['vector'] as String).toSet())
      name: PublishedTimetable.decode(_bytes(name))
  };

  group('lookup', () {
    for (final testCase in cases) {
      test(testCase['name'] as String, () {
        final timetable = vectors[testCase['vector'] as String]!;
        final coordinates = (testCase['coordinates'] as List).cast<double>();
        final localityId = testCase['localityId'] as String?;
        final lookup = timetable.lookup(
            Coordinates(coordinates[0], coordinates[1]),
            _date(testCase['date'] as String),
            localityId: localityId == null ? null : LocalityId(localityId));
        switch (testCase['result'] as String) {
          case 'noLocality':
            expect(lookup, isA<NoLocality>());
          case 'noRow':
            expect(lookup, isA<NoRow>());
            expect((lookup as NoRow).locality.id.value, testCase['locality']);
          case 'row':
            expect(lookup, isA<OfficialRow>());
            final row = lookup as OfficialRow;
            expect(row.locality.id.value, testCase['locality']);
            final published = (testCase['published'] as Map<String, dynamic>)
                .cast<String, String>();
            for (final column in PublishedColumn.values) {
              final instant = row.published(column);
              final expectedInstant = published[column.name];
              if (expectedInstant == null) {
                expect(instant, isNull, reason: column.name);
              } else {
                expect(instant!.isUtc, isTrue, reason: column.name);
                expect(instant, DateTime.parse(expectedInstant),
                    reason: column.name);
              }
            }
            expect(row.authority, timetable.authority);
            expect(row.revision, timetable.revision);
            expect(row.asrShadow, timetable.asrShadow);
            final asr = (testCase['asr'] as Map<String, dynamic>)
                .cast<String, String>();
            for (final madhab in Madhab.values) {
              final times = PrayerTimes.official(row,
                  parameters: _parameters(madhab), utcOffset: Duration());
              expect(times.asr.isUtc, isTrue, reason: madhab.name);
              expect(times.asr, DateTime.parse(asr[madhab.name]!),
                  reason: madhab.name);
              expect(times.fajr, row.published(PublishedColumn.fajr));
              expect(times.sunrise, row.published(PublishedColumn.sunrise));
              expect(times.dhuhr, row.published(PublishedColumn.dhuhr));
              expect(times.maghrib, row.published(PublishedColumn.maghrib));
              expect(times.isha, row.published(PublishedColumn.isha));
            }
        }
      });
    }
  });

  group('presentation', () {
    final row = vectors['valid/dst.ott']!
            .lookup(Coordinates(30.0444, 31.2357), DateComponents(2026, 4, 24))
        as OfficialRow;

    test('no utcOffset presents host local times of the published instants',
        () {
      final times =
          PrayerTimes.official(row, parameters: _parameters(Madhab.shafi));
      expect(times.fajr.isUtc, isFalse);
      expect(times.fajr.toUtc(), row.published(PublishedColumn.fajr));
      expect(times.isha.toUtc(), row.published(PublishedColumn.isha));
    });

    test('a zero utcOffset presents the UTC instants', () {
      final times = PrayerTimes.official(row,
          parameters: _parameters(Madhab.shafi), utcOffset: Duration());
      expect(times.fajr.isUtc, isTrue);
      expect(times.fajr, row.published(PublishedColumn.fajr));
      expect(times.isha, row.published(PublishedColumn.isha));
    });

    test('a non-zero utcOffset shifts the UTC instants', () {
      final times = PrayerTimes.official(row,
          parameters: _parameters(Madhab.shafi), utcOffset: Duration(hours: 3));
      expect(times.fajr,
          row.published(PublishedColumn.fajr)!.add(Duration(hours: 3)));
    });
  });

  group('validateAllRows', () {
    for (final entry in vectors.entries) {
      test('passes on ${entry.key}', () {
        expect(entry.value.validateAllRows, returnsNormally);
      });
    }
  });

  group('malformed', () {
    final index = (jsonDecode(
                File('$_vectorsDir/malformed/index.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();
    final files = Directory('$_vectorsDir/malformed')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.ott'))
        .toSet();
    final rules = {
      for (final rule in OttRule.values) rule.id,
      for (final rule in CellRule.values) rule.id,
    };

    test('the index names every malformed file once', () {
      final named = index.map((entry) => entry['file'] as String).toList();
      expect(named.toSet(), files);
      expect(named.length, files.length);
    });

    test('every decoder rule has a malformed file and every file names a rule',
        () {
      expect(index.map((entry) => entry['rule']).toSet(), rules);
    });

    test('the format doc lists every rule with the stage the vectors record',
        () {
      final table =
          RegExp(r'^\| `([\w.]+)` \| (decode|validate) \|', multiLine: true)
              .allMatches(
                  File('docs/PUBLISHED_TIMETABLE_FORMAT.md').readAsStringSync())
              .map((match) => '${match[1]}\t${match[2]}')
              .toSet();
      final recorded = {
        for (final entry in index) '${entry['rule']}\t${entry['stage']}'
      };
      expect(table, recorded);
      expect(table.map((row) => row.split('\t').first).toSet(), rules);
    });

    for (final entry in index) {
      final file = entry['file'] as String;
      test('$file fails at ${entry['stage']} on ${entry['rule']}', () {
        final (stage, message) = _outcome(_bytes('malformed/$file'));
        expect(stage, entry['stage']);
        expect(message, startsWith('${entry['rule']}: '));
      });
    }
  });

  group('decode', () {
    test('keeps its own copy of the bytes', () {
      final pristine = vectors['valid/kacst-like.ott']!;
      final bytes = _bytes('valid/kacst-like.ott');
      final timetable = PublishedTimetable.decode(bytes);
      bytes.fillRange(0, bytes.length, 0x67);
      for (final day in [1, 2]) {
        final date = DateComponents(2026, 1, day);
        expect(
            (timetable.lookup(_riyadh, date) as OfficialRow)
                .published(PublishedColumn.fajr),
            (pristine.lookup(_riyadh, date) as OfficialRow)
                .published(PublishedColumn.fajr));
      }
    });

    test('a date that is not a calendar day is an argument error', () {
      final timetable = vectors['valid/kacst-like.ott']!;
      expect(() => timetable.lookup(_riyadh, DateComponents(2026, 2, 30)),
          throwsArgumentError);
      expect(
          () => timetable.lookup(_riyadh, DateComponents(2026, 2, 30),
              localityId: LocalityId('1001')),
          throwsArgumentError);
      expect(() => timetable.localityAt(_riyadh, DateComponents(2026, 13, 1)),
          throwsArgumentError);
    });

    test('a coordinate off the globe is an argument error', () {
      final timetable = vectors['valid/kacst-like.ott']!;
      for (final point in [
        Coordinates(90.5, 46),
        Coordinates(-91, 46),
        Coordinates(24, 180.5),
        Coordinates(24, -181),
        Coordinates(double.nan, 46),
        Coordinates(24, double.infinity),
      ]) {
        expect(() => timetable.localityAt(point, DateComponents(2026, 1, 1)),
            throwsArgumentError,
            reason: '$point');
        expect(() => timetable.lookup(point, DateComponents(2026, 1, 1)),
            throwsArgumentError,
            reason: '$point');
      }
      expect(
          timetable.localityAt(
              Coordinates(90, 180), DateComponents(2026, 1, 1)),
          isNull);
      expect(
          timetable.lookup(
              Coordinates(double.nan, 48), DateComponents(2026, 1, 3),
              localityId: LocalityId('1001')),
          isA<OfficialRow>());
    });
  });

  group('header', () {
    test('kacst-like exposes its header', () {
      final timetable = vectors['valid/kacst-like.ott']!;
      expect(timetable.authority, 'sa-umm-al-qura');
      expect(timetable.revision, '12');
      expect(timetable.coverage,
          (DateComponents(2026, 1, 1), DateComponents(2027, 12, 31)));
      expect(timetable.columns.map((c) => c.name),
          ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha']);
      expect(timetable.asrShadow, 1);
      expect(timetable.localities.map((l) => l.id.value),
          ['1001', '1002', '1003']);
      final riyadh = timetable.locality(LocalityId('1001'))!;
      expect(riyadh.name('ar'), 'الرياض');
      expect(riyadh.name('fr'), 'Riyadh');
      expect(riyadh.group, '1001');
      expect(riyadh.referencePoint.latitude, 24.67);
      expect(riyadh.referencePoint.longitude, 46.69);
      expect(timetable.locality(LocalityId('9999')), isNull);
    });

    test('shapes exposes validity and successors', () {
      final timetable = vectors['valid/shapes.ott']!;
      final old = timetable.locality(LocalityId('old'))!;
      expect(old.validFrom, isNull);
      expect(old.validTo, DateComponents(2026, 12, 31));
      expect(old.successors, [LocalityId('new')]);
      expect(old.inForceOn(DateComponents(2026, 12, 31)), isTrue);
      expect(old.inForceOn(DateComponents(2027, 1, 1)), isFalse);
      expect(old.name('en'), 'old');
      final fresh = timetable.locality(LocalityId('new'))!;
      expect(fresh.validFrom, DateComponents(2027, 1, 1));
      expect(fresh.inForceOn(DateComponents(2026, 12, 31)), isFalse);
      expect(
          timetable.localityAt(Coordinates(15, 48), DateComponents(2026, 6, 1)),
          old);
      expect(
          timetable.localityAt(Coordinates(15, 48), DateComponents(2027, 6, 1)),
          fresh);
    });
  });
}
