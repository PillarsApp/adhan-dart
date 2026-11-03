import 'package:adhan/adhan.dart';
import 'package:adhan/src/data/calendar_util.dart';
import 'package:adhan/src/internal/day_times.dart';
import 'package:adhan/src/polar_circle_resolution.dart';
import 'package:test/test.dart';

final regularDate = DateComponents(2020, 5, 15);
final dateAffectedByPolarNight = DateComponents(2020, 12, 21);
final dateAffectedByMidnightSun = DateComponents(2020, 6, 21);
final regularCoordinates = Coordinates(31.947351, 35.227163);
final arjeplogSweden = Coordinates(66.7222444, 17.7189);
final amundsenScottAntarctic = Coordinates(-84.996, 0.01013);
final london = Coordinates(51.5074, -0.1278);

DateTime utcMidnight(DateComponents components) =>
    DateTime.utc(components.year, components.month, components.day);

DateTime utc(int y, int m, int d, int h, int min) =>
    DateTime.utc(y, m, d, h, min);

String dayLabel(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

CalculationParameters muslimWorldLeague(
    {PolarCircleResolution? polar,
    HourAngleCorrection? correction,
    HighLatitudeRule? rule}) {
  final params = CalculationMethod.muslim_world_league.getParameters();
  if (polar != null) {
    params.polarCircleResolution = polar;
  }
  if (correction != null) {
    params.hourAngleCorrection = correction;
  }
  if (rule != null) {
    params.highLatitudeRule = rule;
  }
  return params;
}

CalculationParameters ishaInsideMinimumGap() =>
    muslimWorldLeague()..ishaInterval = DayTimes.minimumPrayerGap.inMinutes - 4;

void expectOrdered(PrayerTimes p) {
  expect(p.fajr.isBefore(p.sunrise), isTrue);
  expect(p.sunrise.isBefore(p.dhuhr), isTrue);
  expect(p.dhuhr.isBefore(p.asr), isTrue);
  expect(p.asr.isBefore(p.maghrib), isTrue);
  expect(p.maghrib.isBefore(p.isha), isTrue);
}

void expectDhuhrOnRequestedDate(PrayerTimes p, DateComponents date) {
  expect(DateComponents.from(p.dhuhr.toUtc()), date);
}

void main() {
  group('defaults', () {
    test('every method uses iterative, aqrabBalad and nearest', () {
      final plain = CalculationParameters(fajrAngle: 18, ishaAngle: 18);
      expect(plain.hourAngleCorrection, HourAngleCorrection.iterative);
      expect(plain.polarCircleResolution, PolarCircleResolution.aqrabBalad);
      expect(plain.rounding, Rounding.nearest);
      for (final method in CalculationMethod.values) {
        final params = method.getParameters();
        expect(params.hourAngleCorrection, HourAngleCorrection.iterative,
            reason: '$method');
        expect(params.polarCircleResolution, PolarCircleResolution.aqrabBalad,
            reason: '$method');
        expect(params.rounding, Rounding.nearest, reason: '$method');
      }
    });
  });

  group('HighLatitudeRule.recommended', () {
    test('uses the distance from the equator in both hemispheres', () {
      expect(HighLatitudeRule.recommended(Coordinates(-54.8019, -68.3030)),
          HighLatitudeRule.seventh_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(-53.1638, -70.9171)),
          HighLatitudeRule.seventh_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(-45.8788, 170.5028)),
          HighLatitudeRule.middle_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(-6.2088, 106.8456)),
          HighLatitudeRule.middle_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(0, 0)),
          HighLatitudeRule.middle_of_the_night);
    });

    test('mirror latitudes agree', () {
      for (final latitude in [45.983226, 48.983226, 49.0, 50.0]) {
        expect(HighLatitudeRule.recommended(Coordinates(latitude, -3.216649)),
            HighLatitudeRule.recommended(Coordinates(-latitude, -3.216649)),
            reason: '$latitude');
      }
    });

    test('48 degrees is the boundary', () {
      for (final sign in [1, -1]) {
        expect(HighLatitudeRule.recommended(Coordinates(sign * 48.0, 0)),
            HighLatitudeRule.middle_of_the_night);
        expect(HighLatitudeRule.recommended(Coordinates(sign * 48.0001, 0)),
            HighLatitudeRule.seventh_of_the_night);
      }
    });
  });

  group('HourAngleCorrection', () {
    final summerDay = DateComponents(2026, 7, 16);
    PrayerTimes londonSummer(HourAngleCorrection correction) => PrayerTimes.utc(
        london,
        summerDay,
        muslimWorldLeague(
            correction: correction,
            rule: HighLatitudeRule.middle_of_the_night));

    test('singlePass keeps the 2.3.0 London summer Isha', () {
      expect(londonSummer(HourAngleCorrection.singlePass).isha,
          utc(2026, 7, 16, 23, 34));
    });

    test('iterative moves London summer Isha', () {
      expect(londonSummer(HourAngleCorrection.iterative).isha,
          utc(2026, 7, 16, 23, 38));
    });

    test('the other five times agree between corrections', () {
      final single = londonSummer(HourAngleCorrection.singlePass);
      final iterative = londonSummer(HourAngleCorrection.iterative);
      expect(single.fajr, iterative.fajr);
      expect(single.sunrise, iterative.sunrise);
      expect(single.dhuhr, iterative.dhuhr);
      expect(single.asr, iterative.asr);
      expect(single.maghrib, iterative.maghrib);
    });
  });

  group('host time zone', () {
    test(
        'rounding a local time inside a daylight saving hour keeps the instant',
        () {
      final beforeFallBack = DateTime.utc(2026, 11, 1, 6, 59, 45).toLocal();
      expect(CalendarUtil.roundedMinute(beforeFallBack).toUtc(),
          DateTime.utc(2026, 11, 1, 7, 0));
      final beforeSpringForward = DateTime.utc(2026, 3, 8, 7, 59, 45).toLocal();
      expect(CalendarUtil.roundedMinute(beforeSpringForward).toUtc(),
          DateTime.utc(2026, 3, 8, 8, 0));
    });

    test('a daylight saving day in the host zone does not move a time', () {
      final reykjavik = Coordinates(64.1466, -21.9426);
      final tromso = Coordinates(69.6492, 18.9553);
      final transitionDay = DateComponents(2026, 11, 1);
      final msc = CalculationMethod.moon_sighting_committee.getParameters()
        ..hourAngleCorrection = HourAngleCorrection.singlePass
        ..polarCircleResolution = PolarCircleResolution.unresolved;
      final mwl = muslimWorldLeague(
          correction: HourAngleCorrection.singlePass,
          polar: PolarCircleResolution.unresolved,
          rule: HighLatitudeRule.middle_of_the_night);
      expect(PrayerTimes(reykjavik, transitionDay, msc).fajr.toUtc(),
          DateTime.fromMillisecondsSinceEpoch(1793518140 * 1000, isUtc: true));
      expect(PrayerTimes(tromso, transitionDay, mwl).fajr.toUtc(),
          DateTime.fromMillisecondsSinceEpoch(1793504160 * 1000, isUtc: true));
    });
  });

  group('PolarCircleResolution', () {
    test('no resolution when the date is unaffected', () {
      final expected = DayTimes.compute(
          arjeplogSweden,
          utcMidnight(regularDate),
          muslimWorldLeague(polar: PolarCircleResolution.unresolved));
      expect(expected, isNotNull);
      for (final resolution in PolarCircleResolution.values) {
        final p = PrayerTimes.utc(
            arjeplogSweden, regularDate, muslimWorldLeague(polar: resolution));
        expect(p.fajr, expected!.fajr, reason: '$resolution');
        expect(p.isha, expected.isha, reason: '$resolution');
      }
    });

    test('no resolution outside the polar circle', () {
      final expected = DayTimes.compute(
          regularCoordinates,
          utcMidnight(dateAffectedByPolarNight),
          muslimWorldLeague(polar: PolarCircleResolution.unresolved));
      expect(expected, isNotNull);
      for (final resolution in PolarCircleResolution.values) {
        final p = PrayerTimes.utc(regularCoordinates, dateAffectedByPolarNight,
            muslimWorldLeague(polar: resolution));
        expect(p.fajr, expected!.fajr, reason: '$resolution');
        expect(p.isha, expected.isha, reason: '$resolution');
      }
    });

    test('midnight sun, unresolved', () {
      expect(
          () => PrayerTimes.utc(arjeplogSweden, dateAffectedByMidnightSun,
              muslimWorldLeague(polar: PolarCircleResolution.unresolved)),
          throwsArgumentError);
    });

    test('midnight sun, aqrabBalad', () {
      final p = PrayerTimes.utc(arjeplogSweden, dateAffectedByMidnightSun,
          muslimWorldLeague(polar: PolarCircleResolution.aqrabBalad));
      expectOrdered(p);
      expect(p.coordinates.latitude, arjeplogSweden.latitude);
      expect(p.coordinates.longitude, arjeplogSweden.longitude);
    });

    test('midnight sun, aqrabYaum', () {
      final p = PrayerTimes.utc(arjeplogSweden, dateAffectedByMidnightSun,
          muslimWorldLeague(polar: PolarCircleResolution.aqrabYaum));
      expectOrdered(p);
      expectDhuhrOnRequestedDate(p, dateAffectedByMidnightSun);
      expect(p.dateComponents, dateAffectedByMidnightSun);
    });

    test('polar night, unresolved', () {
      expect(
          () => PrayerTimes.utc(
              amundsenScottAntarctic,
              dateAffectedByPolarNight,
              muslimWorldLeague(polar: PolarCircleResolution.unresolved)),
          throwsArgumentError);
    });

    test('polar night, aqrabBalad', () {
      expectOrdered(PrayerTimes.utc(
          amundsenScottAntarctic,
          dateAffectedByPolarNight,
          muslimWorldLeague(polar: PolarCircleResolution.aqrabBalad)));
    });

    test('polar night, aqrabYaum', () {
      final p = PrayerTimes.utc(
          amundsenScottAntarctic,
          dateAffectedByPolarNight,
          muslimWorldLeague(polar: PolarCircleResolution.aqrabYaum));
      expectOrdered(p);
      expectDhuhrOnRequestedDate(p, dateAffectedByPolarNight);
    });

    test('aqrabYaum times for Arjeplog on 21 June 2020', () {
      final p = PrayerTimes.utc(
          arjeplogSweden,
          dateAffectedByMidnightSun,
          muslimWorldLeague(
              polar: PolarCircleResolution.aqrabYaum,
              rule: HighLatitudeRule.seventh_of_the_night));
      expect(p.fajr, utc(2020, 6, 20, 22, 48));
      expect(p.sunrise, utc(2020, 6, 20, 22, 54));
      expect(p.dhuhr, utc(2020, 6, 21, 10, 55));
      expect(p.asr, utc(2020, 6, 21, 15, 49));
      expect(p.maghrib, utc(2020, 6, 21, 22, 30));
      expect(p.isha, utc(2020, 6, 21, 22, 37));
    });

    test('aqrabYaum stays ordered when the sun cannot reach the Asr angle', () {
      final coordinates = Coordinates(67.37800510772394, -67.26246475893095);
      for (var day = 2; day <= 8; day++) {
        expectOrdered(PrayerTimes.utc(coordinates, DateComponents(2026, 1, day),
            muslimWorldLeague(polar: PolarCircleResolution.aqrabYaum)));
      }
    });

    test('impossible parameters fail even at the equator', () {
      expect(
          DayTimes.compute(Coordinates(0, 0), DateTime.utc(2026, 1, 1),
              ishaInsideMinimumGap()),
          isNull);
    });

    test('aqrabBalad searches to the equator and gives up', () {
      expect(
          PolarCircleResolution.aqrabBalad.resolve(Coordinates(70, 10),
              DateTime.utc(2026, 1, 1), ishaInsideMinimumGap()),
          isNull);
    });

    test('aqrabBalad never crosses the hemisphere', () {
      for (final latitude in [0.3, -0.3, 0.0]) {
        expect(
            PolarCircleResolution.aqrabBalad.resolve(Coordinates(latitude, 10),
                DateTime.utc(2026, 1, 1), ishaInsideMinimumGap()),
            isNull,
            reason: '$latitude');
      }
    });

    test('aqrabBalad resolves a real polar location', () {
      expect(
          PolarCircleResolution.aqrabBalad.resolve(amundsenScottAntarctic,
              utcMidnight(dateAffectedByPolarNight), muslimWorldLeague()),
          isNotNull);
    });

    test('aqrabYaum gives up when no day is valid', () {
      expect(
          PolarCircleResolution.aqrabYaum.resolve(Coordinates(70, 10),
              DateTime.utc(2026, 1, 1), ishaInsideMinimumGap()),
          isNull);
    });

    test('unresolved returns null without searching', () {
      expect(
          PolarCircleResolution.unresolved.resolve(Coordinates(70, 10),
              DateTime.utc(2026, 1, 1), muslimWorldLeague()),
          isNull);
    });

    test('invalid inputs are not resolved', () {
      for (final resolution in PolarCircleResolution.values) {
        expect(
            () => PrayerTimes.utc(
                Coordinates(999, 999),
                dateAffectedByMidnightSun,
                muslimWorldLeague(polar: resolution)),
            throwsArgumentError,
            reason: '$resolution');
      }
    });

    test('shifted moves every time by whole days', () {
      final base = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final result = DayTimes(
          fajr: base,
          sunrise: base,
          dhuhr: base,
          asr: base,
          maghrib: base,
          isha: base);
      expect(identical(result.shifted(0), result), isTrue);
      expect(result.shifted(2).dhuhr, DateTime.utc(1970, 1, 3));
      expect(result.shifted(-3).isha, DateTime.utc(1969, 12, 29));
    });
  });

  group('date line', () {
    final suva = Coordinates(-18.1416, 178.4419);
    final chatham = Coordinates(-43.95, -176.55);
    DateTime epoch(int seconds) =>
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

    test('iterative keeps the transit on the requested day', () {
      expectOrdered(PrayerTimes.utc(
          suva, DateComponents(2026, 12, 12), muslimWorldLeague()));
      expectOrdered(PrayerTimes.utc(
          chatham, DateComponents(2026, 2, 3), muslimWorldLeague()));
    });

    test('singlePass keeps the 2.3.0 day selection', () {
      final params = muslimWorldLeague(
          correction: HourAngleCorrection.singlePass,
          polar: PolarCircleResolution.unresolved);
      final suvaTimes =
          PrayerTimes.utc(suva, DateComponents(2026, 12, 12), params);
      expect(suvaTimes.fajr, epoch(1797120000));
      expect(suvaTimes.sunrise, epoch(1797096240));
      expect(suvaTimes.isha, epoch(1797120000));
      final chathamTimes =
          PrayerTimes.utc(chatham, DateComponents(2026, 2, 3), params);
      expect(chathamTimes.fajr, epoch(1770163200));
      expect(chathamTimes.sunrise, epoch(1770137340));
      expect(chathamTimes.isha, epoch(1770163200));
    });
  });

  group('global sweep', () {
    test('every 5 degrees latitude, 10 degrees longitude, every day of 2025',
        () {
      const polarCircleLatitude = 66.55;
      final params = muslimWorldLeague(polar: PolarCircleResolution.unresolved);
      final violations = <String>[];
      for (var lat = -90; lat <= 90; lat += 5) {
        for (var lon = -180; lon <= 180; lon += 10) {
          final coordinates = Coordinates(lat.toDouble(), lon.toDouble());
          final inPolarCircle = lat.abs() > polarCircleLatitude;
          var day = DateTime.utc(2025, 1, 1);
          for (var i = 0; i < 365; i++, day = day.add(Duration(days: 1))) {
            final where = '($lat, $lon) ${dayLabel(day)}';
            final PrayerTimes p;
            try {
              p = PrayerTimes.utc(
                  coordinates, DateComponents.from(day), params);
            } on ArgumentError {
              if (!inPolarCircle) {
                violations.add('$where: no times outside the polar circle');
              }
              continue;
            }
            if (!p.fajr.isBefore(p.sunrise)) violations.add('$where: fajr');
            if (!p.sunrise.isBefore(p.dhuhr)) violations.add('$where: sunrise');
            if (!p.dhuhr.isBefore(p.asr)) violations.add('$where: dhuhr');
            if (!p.asr.isBefore(p.maghrib)) violations.add('$where: asr');
            if (!p.maghrib.isBefore(p.isha)) violations.add('$where: maghrib');
          }
        }
      }
      expect(violations, isEmpty);
    });
  });

  group('DayTimes.timesInOrder', () {
    final gap = DayTimes.minimumPrayerGap;
    DateTime t(Duration offset) =>
        DateTime.fromMillisecondsSinceEpoch(1000000000 * 1000, isUtc: true)
            .add(offset);

    test('exact gap is in order', () {
      expect(DayTimes.timesInOrder(t(Duration.zero), t(gap)), isTrue);
    });
    test('more than the gap is in order', () {
      expect(
          DayTimes.timesInOrder(
              t(Duration.zero), t(gap + Duration(seconds: 1))),
          isTrue);
    });
    test('less than the gap is out of order', () {
      expect(
          DayTimes.timesInOrder(
              t(Duration.zero), t(gap - Duration(seconds: 1))),
          isFalse);
    });
    test('equal times are out of order', () {
      expect(
          DayTimes.timesInOrder(t(Duration.zero), t(Duration.zero)), isFalse);
    });
    test('reversed times are out of order', () {
      expect(DayTimes.timesInOrder(t(gap), t(Duration.zero)), isFalse);
    });
    test('a missing time is out of order', () {
      expect(DayTimes.timesInOrder(null, t(Duration.zero)), isFalse);
      expect(DayTimes.timesInOrder(t(Duration.zero), null), isFalse);
      expect(DayTimes.timesInOrder(null, null), isFalse);
    });
  });

  group('SunnahTimes', () {
    test('New York', () {
      final params = CalculationMethod.north_america.getParameters();
      final coordinates = Coordinates(35.7750, -78.6336);
      final today =
          PrayerTimes.utc(coordinates, DateComponents(2015, 7, 12), params);
      expect(today.maghrib, utc(2015, 7, 13, 0, 32));
      final tomorrow =
          PrayerTimes.utc(coordinates, DateComponents(2015, 7, 13), params);
      expect(tomorrow.fajr, utc(2015, 7, 13, 8, 43));
      final sunnah = SunnahTimes(today);
      expect(sunnah.middleOfTheNight, utc(2015, 7, 13, 4, 38));
      expect(sunnah.lastThirdOfTheNight, utc(2015, 7, 13, 5, 59));
    });

    test('London', () {
      final params = CalculationMethod.moon_sighting_committee.getParameters();
      final today =
          PrayerTimes.utc(london, DateComponents(2016, 12, 31), params);
      expect(today.maghrib, utc(2016, 12, 31, 16, 4));
      final tomorrow =
          PrayerTimes.utc(london, DateComponents(2017, 1, 1), params);
      expect(tomorrow.fajr, utc(2017, 1, 1, 6, 25));
      final sunnah = SunnahTimes(today);
      expect(sunnah.middleOfTheNight, utc(2016, 12, 31, 23, 15));
      expect(sunnah.lastThirdOfTheNight, utc(2017, 1, 1, 1, 38));
    });

    test('Oslo', () {
      final params =
          muslimWorldLeague(rule: HighLatitudeRule.middle_of_the_night);
      final coordinates = Coordinates(59.9094, 10.7349);
      final today =
          PrayerTimes.utc(coordinates, DateComponents(2016, 7, 1), params);
      expect(today.maghrib, utc(2016, 7, 1, 20, 41));
      final tomorrow =
          PrayerTimes.utc(coordinates, DateComponents(2016, 7, 2), params);
      expect(tomorrow.fajr, utc(2016, 7, 1, 23, 20));
      final sunnah = SunnahTimes(today);
      expect(sunnah.middleOfTheNight, utc(2016, 7, 1, 22, 1));
      expect(sunnah.lastThirdOfTheNight, utc(2016, 7, 1, 22, 27));
    });

    test('across the spring daylight saving change', () {
      final params = CalculationMethod.north_america.getParameters();
      final coordinates = Coordinates(37.7749, -122.4194);
      final today =
          PrayerTimes.utc(coordinates, DateComponents(2017, 3, 11), params);
      expect(today.fajr, utc(2017, 3, 11, 13, 14));
      expect(today.maghrib, utc(2017, 3, 12, 2, 13));
      final tomorrow =
          PrayerTimes.utc(coordinates, DateComponents(2017, 3, 12), params);
      expect(tomorrow.fajr, utc(2017, 3, 12, 13, 13));
      expect(tomorrow.maghrib, utc(2017, 3, 13, 2, 14));
      final sunnah = SunnahTimes(today);
      expect(sunnah.middleOfTheNight, utc(2017, 3, 12, 7, 43));
      expect(sunnah.lastThirdOfTheNight, utc(2017, 3, 12, 9, 33));
    });

    test('across the autumn daylight saving change', () {
      final params =
          muslimWorldLeague(rule: HighLatitudeRule.seventh_of_the_night);
      final coordinates = Coordinates(48.8566, 2.3522);
      final today =
          PrayerTimes.utc(coordinates, DateComponents(2015, 10, 24), params);
      expect(today.fajr, utc(2015, 10, 24, 4, 38));
      expect(today.maghrib, utc(2015, 10, 24, 16, 45));
      final tomorrow =
          PrayerTimes.utc(coordinates, DateComponents(2015, 10, 25), params);
      expect(tomorrow.fajr, utc(2015, 10, 25, 4, 40));
      expect(tomorrow.maghrib, utc(2015, 10, 25, 16, 43));
      final sunnah = SunnahTimes(today);
      expect(sunnah.middleOfTheNight, utc(2015, 10, 24, 22, 43));
      expect(sunnah.lastThirdOfTheNight, utc(2015, 10, 25, 0, 42));
    });

    test('honour the rounding setting', () {
      final coordinates = Coordinates(35.7750, -78.6336);
      final today = DateComponents(2015, 7, 12);
      final tomorrow = DateComponents(2015, 7, 13);

      _ExactSunnah exact(CalculationParameters params) {
        final todayPrayers = PrayerTimes.utc(coordinates, today, params);
        final tomorrowPrayers = PrayerTimes.utc(coordinates, tomorrow, params);
        final night = tomorrowPrayers.fajr.difference(todayPrayers.maghrib);
        return _ExactSunnah(
          todayPrayers,
          todayPrayers.maghrib
              .add(Duration(microseconds: night.inMicroseconds ~/ 2)),
          todayPrayers.maghrib
              .add(Duration(microseconds: night.inMicroseconds * 2 ~/ 3)),
        );
      }

      final none = exact(CalculationMethod.north_america.getParameters()
        ..rounding = Rounding.none);
      final noneSunnah = SunnahTimes(none.prayers);
      expect(noneSunnah.middleOfTheNight,
          CalendarUtil.roundedMinute(none.middle, Rounding.none));
      expect(noneSunnah.lastThirdOfTheNight,
          CalendarUtil.roundedMinute(none.lastThird, Rounding.none));

      final up = exact(CalculationMethod.north_america.getParameters()
        ..rounding = Rounding.up);
      final upSunnah = SunnahTimes(up.prayers);
      expect(upSunnah.middleOfTheNight,
          CalendarUtil.roundedMinute(up.middle, Rounding.up));
      expect(upSunnah.lastThirdOfTheNight,
          CalendarUtil.roundedMinute(up.lastThird, Rounding.up));
      expect(upSunnah.lastThirdOfTheNight,
          isNot(CalendarUtil.roundedMinute(up.lastThird, Rounding.nearest)));
    });

    test('throws when tomorrow cannot be resolved', () {
      final params = muslimWorldLeague(polar: PolarCircleResolution.unresolved);
      final prayerTimes =
          PrayerTimes.utc(arjeplogSweden, DateComponents(2020, 6, 2), params);
      expect(() => SunnahTimes(prayerTimes), throwsArgumentError);
    });

    test('resolved inside the polar circle', () {
      final prayerTimes = PrayerTimes.utc(
          arjeplogSweden, dateAffectedByMidnightSun, muslimWorldLeague());
      final sunnah = SunnahTimes(prayerTimes);
      expect(sunnah.middleOfTheNight.isAfter(prayerTimes.maghrib), isTrue);
      expect(
          sunnah.lastThirdOfTheNight.isAfter(sunnah.middleOfTheNight), isTrue);
    });
  });
}

class _ExactSunnah {
  final PrayerTimes prayers;
  final DateTime middle;
  final DateTime lastThird;

  _ExactSunnah(this.prayers, this.middle, this.lastThird);
}
