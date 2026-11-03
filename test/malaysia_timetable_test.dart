import 'dart:convert';
import 'dart:io';

import 'package:adhan/adhan.dart';
import 'package:adhan/src/data/malaysia_times_codec.dart';
import 'package:adhan/src/data/malaysia_times_data.dart';
import 'package:adhan/src/data/malaysia_zones_data.dart';
import 'package:adhan/src/internal/shadow_length.dart';
import 'package:adhan/src/internal/solar_time.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _utcPlus8 = Duration(hours: 8);

const _subuh = 1;
const _syuruk = 2;
const _zohor = 4;
const _asar = 5;
const _maghrib = 6;
const _isyak = 7;

final _kualaLumpur = Coordinates(3.1390, 101.6869);
final _kotaKinabalu = Coordinates(5.9749, 116.0724);
final _shahAlam = Coordinates(3.0733, 101.5185);
final _singapore = Coordinates(1.3521, 103.8198);
final _london = Coordinates(51.5074, -0.1278);
final _nov2 = DateComponents(2026, 11, 2);

CalculationParameters _official({String? zone}) =>
    CalculationMethod.malaysia_official.getParameters()..malaysiaZone = zone;

DateTime _instant(DateComponents date, int minuteOfDay) =>
    DateTime.utc(date.year, date.month, date.day, 0, minuteOfDay)
        .subtract(_utcPlus8);

int _minutes(String clock) =>
    int.parse(clock.substring(0, 2)) * 60 + int.parse(clock.substring(3));

String _two(int value) => value.toString().padLeft(2, '0');

String _clock(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}';

List<DateTime> _six(PrayerTimes times) => [
      times.fajr,
      times.sunrise,
      times.dhuhr,
      times.asr,
      times.maghrib,
      times.isha
    ];

List<DateTime> _eight(MalaysiaDay day) => [
      day.imsak,
      day.subuh,
      day.syuruk,
      day.dhuha,
      day.zohor,
      day.asar,
      day.maghrib,
      day.isyak
    ];

DateComponents _dayOfYear(int year, int index) =>
    DateComponents.from(DateTime.utc(year, 1, 1).add(Duration(days: index)));

void main() {
  test('every zone-year row reads back through PrayerTimes and day', () {
    final zoneYears = decodeMalaysiaTimes(malaysiaTimesData);
    expect(zoneYears, hasLength(117));
    for (final zoneYear in zoneYears) {
      final label = '${zoneYear.zone} ${zoneYear.year}';
      expect(zoneYear.days, hasLength(365), reason: label);
      final zone = MalaysiaZones.zone(zoneYear.zone)!;
      final parameters = _official(zone: zoneYear.zone);
      for (var index = 0; index < zoneYear.days.length; index++) {
        final date = _dayOfYear(zoneYear.year, index);
        final row = [
          for (final minuteOfDay in zoneYear.days[index])
            _instant(date, minuteOfDay)
        ];
        final times = PrayerTimes.utc(zone.referencePoint, date, parameters);
        expect(times.source, PrayerTimesSource.official,
            reason: '$label $date');
        expect(
            _six(times),
            [
              row[_subuh],
              row[_syuruk],
              row[_zohor],
              row[_asar],
              row[_maghrib],
              row[_isyak]
            ],
            reason: '$label $date');
        final day = MalaysiaTimetable.day(zone, date, utcOffset: Duration())!;
        expect(_eight(day), row, reason: '$label $date');
        expect(day.source, PrayerTimesSource.official);
      }
    }
  });

  test('fixed rows from the published data after corrections', () {
    final kualaLumpur = MalaysiaTimetable.day(
        MalaysiaZones.zone('WLY01')!, _nov2,
        utcOffset: _utcPlus8)!;
    expect(_eight(kualaLumpur).map(_clock), [
      '05:38',
      '05:48',
      '06:56',
      '07:21',
      '13:00',
      '16:20',
      '18:58',
      '20:09'
    ]);
    final labuan = MalaysiaTimetable.day(
        MalaysiaZones.zone('WLY02')!, DateComponents(2027, 5, 22),
        utcOffset: _utcPlus8)!;
    expect(_clock(labuan.maghrib), '18:28');
  });

  test('Kuala Lumpur on 2026-11-02 reads the WLY01 row', () {
    final times =
        PrayerTimes(_kualaLumpur, _nov2, _official(), utcOffset: _utcPlus8);
    expect(_clock(times.fajr), '05:48');
    expect(_clock(times.isha), '20:09');
    expect(times.source, PrayerTimesSource.official);
    expect(times.source.isOfficial, isTrue);
    expect(times.malaysiaZone!.code, 'WLY01');
    expect(times.malaysiaZone, MalaysiaZones.zone('WLY01'));
    expect(times.malaysiaZone!.state, 'Wilayah Persekutuan');
    final day = times.malaysiaDay!;
    expect(_clock(day.imsak), '05:38');
    expect(_clock(day.dhuha), '07:21');
    expect(day.zone, times.malaysiaZone);
    expect(day.date, _nov2);
    expect(day.revision, MalaysiaTimetable.revision);
    expect(day.source, PrayerTimesSource.official);
  });

  test('Sabah in 2027 has no row and falls back to the preset', () {
    final date = DateComponents(2027, 1, 1);
    final times = PrayerTimes(_kotaKinabalu, date, _official());
    expect(times.source, PrayerTimesSource.calculatedNoRow);
    expect(times.source.isOfficial, isFalse);
    expect(times.malaysiaZone!.code, 'SBH07');
    expect(times.malaysiaDay, isNull);
    final preset = CalculationParameters(
            method: CalculationMethod.other, fajrAngle: 18, ishaAngle: 18)
        .withMethodAdjustments(PrayerAdjustments(
            fajr: 1, sunrise: -1, dhuhr: 3, asr: 1, maghrib: 2, isha: 1));
    expect(_six(times), _six(PrayerTimes(_kotaKinabalu, date, preset)));
  });

  test('outside Malaysia has no zone', () {
    final times = PrayerTimes(_singapore, _nov2, _official());
    expect(times.source, PrayerTimesSource.calculatedNoZone);
    expect(times.malaysiaZone, isNull);
    expect(times.malaysiaDay, isNull);
  });

  group('a manual zone', () {
    test('wins over the coordinates', () {
      final times =
          PrayerTimes.utc(_kualaLumpur, _nov2, _official(zone: 'WLY02'));
      final labuan = MalaysiaTimetable.day(MalaysiaZones.zone('WLY02')!, _nov2,
          utcOffset: Duration())!;
      expect(times.source, PrayerTimesSource.official);
      expect(times.malaysiaZone!.code, 'WLY02');
      expect(times.fajr, labuan.subuh);
      expect(times.isha, labuan.isyak);
      expect(times.malaysiaDay!.zone.code, 'WLY02');
    });

    test('with an unknown code has no zone', () {
      final times = PrayerTimes(_kualaLumpur, _nov2, _official(zone: 'XXX99'));
      expect(times.source, PrayerTimesSource.calculatedNoZone);
      expect(times.malaysiaZone, isNull);
      expect(times.malaysiaDay, isNull);
    });
  });

  group('a retired zone', () {
    test('has no row after its last day and names its successors', () {
      final times = PrayerTimes(
          _kualaLumpur, DateComponents(2027, 3, 1), _official(zone: 'SGR01'));
      expect(times.source, PrayerTimesSource.calculatedNoRow);
      expect(times.malaysiaZone!.code, 'SGR01');
      final zone = MalaysiaZones.zone('SGR01')!;
      expect(zone.successors.map((successor) => successor.code),
          ['SGRGBK', 'SGRHLG', 'SGRHSL', 'SGRPTG', 'SGRSPG']);
      expect(zone.validFrom, isNull);
      expect(zone.validTo, DateComponents(2026, 12, 31));
      expect(
          MalaysiaZones.zone('SGRPTG')!.validFrom, DateComponents(2027, 1, 1));
      expect(MalaysiaZones.zone('WLY01')!.validFrom, isNull);
      expect(MalaysiaZones.zone('WLY01')!.validTo, isNull);
      expect(MalaysiaZones.zone('WLY01')!.successors, isEmpty);
    });

    test('is listed only while in force', () {
      final after =
          MalaysiaZones.on(DateComponents(2027, 1, 1)).map((zone) => zone.code);
      expect(after, contains('SGRPTG'));
      expect(after, isNot(contains('SGR01')));
      final before =
          MalaysiaZones.on(DateComponents(2026, 6, 1)).map((zone) => zone.code);
      expect(before, contains('SGR01'));
      expect(before, isNot(contains('SGRPTG')));
    });

    test('SWK09 is listed but never resolved', () {
      expect(
          MalaysiaZones.on(_nov2).map((zone) => zone.code), contains('SWK09'));
      final resolved = MalaysiaZones.resolve(
          MalaysiaZones.zone('SWK09')!.referencePoint, _nov2);
      expect(resolved?.code, isNot('SWK09'));
    });
  });

  test('Shah Alam moves from SGR01 to SGRPTG at the new year', () {
    final lastDay =
        PrayerTimes(_shahAlam, DateComponents(2026, 12, 31), _official());
    expect(lastDay.source, PrayerTimesSource.official);
    expect(lastDay.malaysiaZone!.code, 'SGR01');
    final firstDay =
        PrayerTimes(_shahAlam, DateComponents(2027, 1, 1), _official());
    expect(firstDay.source, PrayerTimesSource.official);
    expect(firstDay.malaysiaZone!.code, 'SGRPTG');
  });

  test('Hanafi shifts the published Asar by the shift at the zone reference',
      () {
    final zone = MalaysiaZones.zone('WLY02')!;
    final shafi =
        PrayerTimes.utc(_kualaLumpur, _nov2, _official(zone: zone.code));
    final hanafi = PrayerTimes.utc(_kualaLumpur, _nov2,
        _official(zone: zone.code)..madhab = Madhab.hanafi);
    int shiftAt(Coordinates point) {
      final solar = SolarTime(DateTime.utc(2026, 11, 2), point);
      return ((solar.afternoon(ShadowLength.double) -
                  solar.afternoon(ShadowLength.single)) *
              60)
          .round();
    }

    final shift = shiftAt(zone.referencePoint);
    expect(shift, isNot(shiftAt(_kualaLumpur)));
    expect(shift, greaterThan(0));
    expect(shift, lessThan(90));
    expect(hanafi.asr, shafi.malaysiaDay!.asar.add(Duration(minutes: shift)));
    expect(hanafi.malaysiaDay!.asar, shafi.malaysiaDay!.asar);
    expect([hanafi.fajr, hanafi.dhuhr, hanafi.maghrib, hanafi.isha],
        [shafi.fajr, shafi.dhuhr, shafi.maghrib, shafi.isha]);
  });

  group('coordinates', () {
    test('a non-finite coordinate throws ArgumentError with no manual zone',
        () {
      for (final point in [
        Coordinates(double.nan, 101.6869),
        Coordinates(3.1390, double.nan),
        Coordinates(double.infinity, 101.6869),
        Coordinates(3.1390, double.negativeInfinity),
      ]) {
        expect(() => PrayerTimes.utc(point, _nov2, _official()),
            throwsArgumentError);
      }
    });

    test('a manual zone wins and the coordinates are not validated', () {
      final times = PrayerTimes.utc(
          Coordinates(double.nan, double.nan), _nov2, _official(zone: 'WLY01'));
      expect(times.source, PrayerTimesSource.official);
      expect(times.malaysiaZone!.code, 'WLY01');
    });
  });

  group('adjustments on an official row', () {
    test('user adjustments move only their prayer', () {
      final plain = PrayerTimes.utc(_kualaLumpur, _nov2, _official());
      final adjusted = PrayerTimes.utc(_kualaLumpur, _nov2,
          _official()..adjustments = PrayerAdjustments(isha: 3));
      expect(adjusted.isha, plain.isha.add(Duration(minutes: 3)));
      expect(_six(adjusted).sublist(0, 5), _six(plain).sublist(0, 5));
      expect(adjusted.malaysiaDay!.isyak, plain.malaysiaDay!.isyak);
    });

    test('method adjustments do not move the row', () {
      final parameters = _official();
      expect(parameters.methodAdjustments.dhuhr, 3);
      final times = PrayerTimes.utc(_kualaLumpur, _nov2, parameters);
      expect(times.dhuhr, _instant(_nov2, _minutes('13:00')));
      expect(times.sunrise, _instant(_nov2, _minutes('06:56')));
    });
  });

  group('presentation', () {
    final subuh = _instant(_nov2, _minutes('05:48'));

    test('PrayerTimes presents local without an offset', () {
      final times = PrayerTimes(_kualaLumpur, _nov2, _official());
      expect(times.fajr.isUtc, isFalse);
      expect(times.fajr.toUtc(), subuh);
      expect(times.malaysiaDay!.subuh.isUtc, isFalse);
      expect(times.malaysiaDay!.subuh.toUtc(), subuh);
    });

    test('PrayerTimes.utc presents the UTC instant', () {
      final times = PrayerTimes.utc(_kualaLumpur, _nov2, _official());
      expect(times.fajr.isUtc, isTrue);
      expect(times.fajr, subuh);
    });

    test('day presents like PrayerTimes', () {
      final zone = MalaysiaZones.zone('WLY01')!;
      final local = MalaysiaTimetable.day(zone, _nov2)!;
      expect(local.subuh.isUtc, isFalse);
      expect(local.subuh.toUtc(), subuh);
      final wall = MalaysiaTimetable.day(zone, _nov2, utcOffset: _utcPlus8)!;
      expect(_clock(wall.subuh), '05:48');
      expect(_clock(wall.isyak), '20:09');
    });
  });

  test('WLY01 instants across 2026 do not depend on the host time zone', () {
    final zoneYear = decodeMalaysiaTimes(malaysiaTimesData)
        .singleWhere((line) => line.zone == 'WLY01' && line.year == 2026);
    final zone = MalaysiaZones.zone('WLY01')!;
    for (var index = 0; index < zoneYear.days.length; index++) {
      final date = _dayOfYear(2026, index);
      final row = zoneYear.days[index];
      final times = PrayerTimes(_kualaLumpur, date, _official(zone: 'WLY01'));
      expect(_six(times).map((time) => time.toUtc()), [
        _instant(date, row[_subuh]),
        _instant(date, row[_syuruk]),
        _instant(date, row[_zohor]),
        _instant(date, row[_asar]),
        _instant(date, row[_maghrib]),
        _instant(date, row[_isyak])
      ]);
      final day = MalaysiaTimetable.day(zone, date)!;
      expect(_eight(day).map((time) => time.toUtc()),
          [for (final minuteOfDay in row) _instant(date, minuteOfDay)]);
    }
  });

  test('revision is the first eight hex digits of both manifest hashes', () {
    final times = sha256.convert(utf8.encode(malaysiaTimesData)).toString();
    final zones = sha256.convert(utf8.encode(malaysiaZonesData)).toString();
    expect(MalaysiaTimetable.revision,
        '${times.substring(0, 8)}-${zones.substring(0, 8)}');
    final outputs = {
      for (final fields in File('data/malaysia/MANIFEST')
          .readAsLinesSync()
          .map((line) => line.split('\t'))
          .where((fields) => fields.first == 'output'))
        fields[1]: fields.last
    };
    expect(outputs['malaysia_times.txt'], times);
    expect(outputs['malaysia_zones.txt'], zones);
  });

  group('existing methods', () {
    test('keep their enum positions', () {
      expect(
          CalculationMethod.values.last, CalculationMethod.malaysia_official);
      expect(CalculationMethod.other.index, 13);
    });

    test('report a calculated source', () {
      final times = PrayerTimes(_london, DateComponents(2026, 7, 16),
          CalculationMethod.muslim_world_league.getParameters());
      expect(times.source, PrayerTimesSource.calculated);
      expect(times.malaysiaZone, isNull);
      expect(times.malaysiaDay, isNull);
    });

    test('London reports an official source without a Malaysian row', () {
      final times = PrayerTimes(_london, DateComponents(2026, 7, 16),
          CalculationMethod.unified_london_times.getParameters());
      expect(times.source, PrayerTimesSource.official);
      expect(times.malaysiaZone, isNull);
      expect(times.malaysiaDay, isNull);
    });
  });
}
