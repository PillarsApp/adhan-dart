import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

import '../../tool/published/ott_encoder.dart';

final _riyadh = Coordinates(24.7136, 46.6753);
final _firstDay = DateComponents(2026, 1, 1);

CalculationParameters _parameters({Madhab madhab = Madhab.shafi}) =>
    CalculationMethod.umm_al_qura.getParameters()..madhab = madhab;

List<DateTime> _six(PrayerTimes times) => [
      times.fajr,
      times.sunrise,
      times.dhuhr,
      times.asr,
      times.maghrib,
      times.isha
    ];

void main() {
  final timetable = PublishedTimetable.decode(
      File('test/published/vectors/valid/kacst-like.ott').readAsBytesSync());
  final row = timetable.lookup(_riyadh, _firstDay) as OfficialRow;

  test('official times carry their source and row', () {
    final times = PrayerTimes.official(row, parameters: _parameters());
    expect(times.source, PrayerTimesSource.official);
    expect(times.source.isOfficial, isTrue);
    expect(times.officialRow, same(row));
    expect(times.coordinates, row.locality.referencePoint);
    expect(times.dateComponents, _firstDay);
    expect(times.malaysiaZone, isNull);
    expect(times.malaysiaDay, isNull);
  });

  test('user adjustments move only their prayer', () {
    final plain = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    final adjusted = PrayerTimes.official(row,
        parameters: _parameters(),
        adjustments: PrayerAdjustments(
            fajr: 1, sunrise: -2, dhuhr: 3, asr: -4, maghrib: 5, isha: -6),
        utcOffset: Duration());
    final shifts = [1, -2, 3, -4, 5, -6];
    for (var i = 0; i < 6; i++) {
      expect(
          _six(adjusted)[i], _six(plain)[i].add(Duration(minutes: shifts[i])));
    }
  });

  test('the Asr adjustment is added after the Hanafi shift', () {
    final hanafi = PrayerTimes.official(row,
        parameters: _parameters(madhab: Madhab.hanafi), utcOffset: Duration());
    final adjusted = PrayerTimes.official(row,
        parameters: _parameters(madhab: Madhab.hanafi),
        adjustments: PrayerAdjustments(asr: 7),
        utcOffset: Duration());
    expect(hanafi.asr, DateTime.utc(2026, 1, 1, 12, 40));
    expect(adjusted.asr, hanafi.asr.add(Duration(minutes: 7)));
  });

  test('adjustments default to the adjustments in the parameters', () {
    final shifts = PrayerAdjustments(fajr: 2, isha: -3);
    final fromParameters = PrayerTimes.official(row,
        parameters: _parameters()..adjustments = shifts, utcOffset: Duration());
    final explicit = PrayerTimes.official(row,
        parameters: _parameters(), adjustments: shifts, utcOffset: Duration());
    expect(_six(fromParameters), _six(explicit));
    expect(fromParameters.fajr,
        row.published(PublishedColumn.fajr)!.add(Duration(minutes: 2)));
  });

  test('method adjustments move nothing', () {
    final plain = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    final withMethod = PrayerTimes.official(row,
        parameters: _parameters().withMethodAdjustments(PrayerAdjustments(
            fajr: 10, sunrise: 10, dhuhr: 10, asr: 10, maghrib: 10, isha: 10)),
        utcOffset: Duration());
    expect(_six(withMethod), _six(plain));
  });

  test('SunnahTimes works on official times, with tomorrow calculated', () {
    final times = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    final sunnah = SunnahTimes(times);
    final tomorrow = PrayerTimes.utc(
        row.locality.referencePoint, DateComponents(2026, 1, 2), _parameters());
    final night = tomorrow.fajr.difference(times.maghrib);
    final midpoint =
        times.maghrib.add(Duration(microseconds: night.inMicroseconds ~/ 2));
    expect(sunnah.middleOfTheNight.second, 0);
    expect(sunnah.middleOfTheNight.difference(midpoint).inSeconds.abs(),
        lessThanOrEqualTo(30));
    expect(sunnah.lastThirdOfTheNight.isAfter(sunnah.middleOfTheNight), isTrue);
    expect(sunnah.lastThirdOfTheNight.isBefore(tomorrow.fajr), isTrue);
  });

  test('prayer navigation reads the published instants', () {
    final times = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    expect(times.currentPrayerByDateTime(DateTime.utc(2026, 1, 1, 9)),
        Prayer.dhuhr);
    expect(times.nextPrayerByDateTime(DateTime.utc(2026, 1, 1, 9)), Prayer.asr);
    expect(
        times.timeForPrayer(Prayer.maghrib), DateTime.utc(2026, 1, 1, 14, 16));
  });

  group('Hanafi Asr where the sun never reaches the Hanafi shadow', () {
    OfficialRow polarRow(List<String> columns, List<int> minutes) {
      final bytes = utf8.encode(encodeOtt({
        'authority': 'xx-polar',
        'revision': 1,
        'part': 'all',
        'coverage': ['2026-01-01', '2026-12-31'],
        'columns': columns,
        'asrShadow': 1,
        'zones': [
          {
            'id': 'Europe/Oslo',
            'offsets': [
              ['2026-01-01', 60]
            ]
          }
        ],
        'localities': [
          {
            'id': 'tromso',
            'group': 'troms',
            'zone': 0,
            'names': {'en': 'Tromsø'},
            'ref': [69650000, 18950000],
            'point': {'radiusM': 30000}
          }
        ],
        'rows': {
          'tromso': {'2026-12-21': minutes}
        },
      }));
      return PublishedTimetable.decode(Uint8List.fromList(bytes))
              .lookup(Coordinates(69.65, 18.95), DateComponents(2026, 12, 21))
          as OfficialRow;
    }

    const core = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

    test(
        'without an asrHanafi column it is a StateError, and Shafi still works',
        () {
      final row = polarRow(core, [300, 660, 720, 780, 840, 1020]);
      expect(
          PrayerTimes.official(row,
                  parameters: _parameters(), utcOffset: Duration())
              .asr,
          DateTime.utc(2026, 12, 21, 12));
      expect(
          () => PrayerTimes.official(row,
              parameters: _parameters(madhab: Madhab.hanafi)),
          throwsA(isA<StateError>()));
    });

    test('with an asrHanafi column that column is the Hanafi Asr', () {
      final row = polarRow(
          [...core, 'asrHanafi'], [300, 660, 720, 780, 840, 1020, 800]);
      expect(
          PrayerTimes.official(row,
                  parameters: _parameters(madhab: Madhab.hanafi),
                  utcOffset: Duration())
              .asr,
          DateTime.utc(2026, 12, 21, 12, 20));
    });
  });

  group('the Hanafi shift follows the caller\'s hour-angle correction', () {
    final chatham =
        PublishedTimetable.decode(Uint8List.fromList(utf8.encode(encodeOtt({
      'authority': 'xx-chatham',
      'revision': 1,
      'part': 'all',
      'coverage': ['2026-02-18', '2026-02-18'],
      'columns': ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'],
      'asrShadow': 1,
      'zones': [
        {
          'id': 'Pacific/Chatham',
          'offsets': [
            ['2026-02-18', 825]
          ]
        }
      ],
      'localities': [
        {
          'id': 'chatham',
          'group': 'chatham',
          'zone': 0,
          'names': {'en': 'Chatham Islands'},
          'ref': [-43953500, -176559700],
          'point': {'radiusM': 30000}
        }
      ],
      'rows': {
        'chatham': {
          '2026-02-18': [300, 390, 800, 1020, 1230, 1320]
        }
      },
    })))).lookup(Coordinates(-43.9535, -176.5597), DateComponents(2026, 2, 18))
            as OfficialRow;

    for (final (correction, asr) in [
      (HourAngleCorrection.iterative, DateTime.utc(2026, 2, 18, 4, 16)),
      (HourAngleCorrection.singlePass, DateTime.utc(2026, 2, 18, 4, 15)),
    ]) {
      test('${correction.name} gives Asr at $asr', () {
        expect(
            PrayerTimes.official(chatham,
                    parameters: _parameters(madhab: Madhab.hanafi)
                      ..hourAngleCorrection = correction,
                    utcOffset: Duration())
                .asr,
            asr);
      });
    }
  });
}
