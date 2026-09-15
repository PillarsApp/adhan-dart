import 'package:adhan/adhan.dart';
import 'package:adhan/src/data/calendar_util.dart';
import 'package:adhan/src/data/time_components.dart';
import 'package:adhan/src/internal/solar_time.dart';
import 'package:adhan/src/internal/astronomical.dart';
import 'package:adhan/src/internal/calendrical_helper.dart';
import 'package:adhan/src/internal/solar_coordinates.dart';
import 'package:test/test.dart';
import 'package:adhan/src/internal/wifaqul_twilight.dart';
import 'package:adhan/src/madhab.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

DateTime raw(DateTime date, double hours) =>
    TimeComponents.fromDouble(hours).dateComponents(date);
DateTime rounded(DateTime date) => CalendarUtil.roundedMinute(date);
CalculationParameters parameters() =>
    CalculationMethod.wifaqul_ulama.getParameters();
PrayerTimes times(Coordinates coordinates, DateTime date,
        [CalculationParameters? params]) =>
    PrayerTimes.utc(
        coordinates, DateComponents.from(date), params ?? parameters());
List<DateTime> prayers(PrayerTimes value) => [
      value.fajr,
      value.sunrise,
      value.dhuhr,
      value.asr,
      value.maghrib,
      value.isha
    ];

DateTime cap(DateTime date, Coordinates coordinates) {
  var longest = double.negativeInfinity;
  late DateTime result;
  for (var day = 15; day <= 25; day++) {
    final candidate = DateTime.utc(date.year, 6, day);
    final solar = SolarTime(candidate, coordinates);
    final duration = solar.sunset - solar.sunrise;
    if (duration > longest) {
      longest = duration;
      result = date
          .add(raw(candidate, solar.sunset).difference(candidate))
          .add(const Duration(minutes: 65));
    }
  }
  return result;
}

double geometricAltitude(DateTime date, Coordinates coordinates, double hours) {
  final julianDay = CalendricalHelper.julianDayByDate(date);
  final previous = SolarCoordinates(julianDay - 1);
  final current = SolarCoordinates(julianDay);
  final next = SolarCoordinates(julianDay + 1);
  final fraction = hours / 24;
  final rightAscension = Astronomical.interpolateAngles(current.rightAscension,
      previous.rightAscension, next.rightAscension, fraction);
  final declination = Astronomical.interpolate(
      current.declination, previous.declination, next.declination, fraction);
  final hourAngle = current.apparentSiderealTime +
      360.985647 * fraction +
      coordinates.longitude -
      rightAscension;
  return Astronomical.altitudeOfCelestialBody(
      coordinates.latitude, declination, hourAngle);
}

void main() {
  final london = Coordinates(51.5074, -0.1278);
  final aberdeen = Coordinates(57.1497, -2.0943);

  test('Near-tangent dawn references use actual last crossing dates', () {
    final locations = [
      Coordinates(61.2181, -149.9003),
      Coordinates(62.0355, 129.6755),
    ];
    final referenceDates = [
      DateTime.utc(2026, 4, 17),
      DateTime.utc(2026, 4, 16),
    ];
    final frozenTimes = [
      DateTime.utc(2026, 6, 21, 10, 28),
      DateTime.utc(2026, 6, 20, 15, 33),
    ];
    final requestedDate = DateTime.utc(2026, 6, 21);
    for (var index = 0; index < locations.length; index++) {
      final coordinates = locations[index];
      final reference = referenceDates[index];
      final solar = SolarTime(reference, coordinates);
      final crossing = solar.twilightHourAngle(-18, false);
      expect(crossing.isFinite, isTrue);
      expect(geometricAltitude(reference, coordinates, crossing),
          closeTo(-18, 0.0001));
      for (var date = reference.add(const Duration(days: 1));
          !date.isAfter(requestedDate);
          date = date.add(const Duration(days: 1))) {
        expect(SolarTime(date, coordinates).twilightHourAngle(-18, false).isNaN,
            isTrue,
            reason: date.toIso8601String());
      }
      expect(times(coordinates, requestedDate).fajr, frozenTimes[index]);
      expect(times(coordinates, reference).fajr,
          rounded(raw(reference, crossing)));
    }
  });

  test(
      'Twilight crossings satisfy the geometric angle on both sides of transit',
      () {
    final date = DateTime.utc(2027, 5, 10);
    final solar = SolarTime(date, london);
    for (final angle in [-18.0, -15.0]) {
      for (final afterTransit in [false, true]) {
        final crossing = solar.twilightHourAngle(angle, afterTransit);
        expect(crossing.isFinite, isTrue);
        expect(
            geometricAltitude(date, london, crossing), closeTo(angle, 0.0001));
        expect(crossing > solar.transit, afterTransit);
      }
    }
    expect(solar.twilightHourAngle(double.nan, false).isNaN, isTrue);
    expect(solar.twilightHourAngle(double.infinity, true).isNaN, isTrue);
  });

  test('Existing Karachi method keeps legacy twilight calculation', () {
    final date = DateTime.utc(2026, 2, 10);
    final coordinates = Coordinates(30.0444, 31.2357);
    final solar = SolarTime(date, coordinates);
    final params = CalculationMethod.karachi.getParameters();
    final result = times(coordinates, date, params);
    expect(result.fajr, rounded(raw(date, solar.hourAngle(-18, false))));
    expect(result.isha, rounded(raw(date, solar.hourAngle(-18, true))));
    expect(result.sunrise, rounded(raw(date, solar.sunrise)));
    expect(result.dhuhr,
        rounded(raw(date, solar.transit).add(const Duration(minutes: 1))));
    expect(result.maghrib, rounded(raw(date, solar.sunset)));
  });

  test('Existing calculation method ordinals remain stable', () {
    expect(CalculationMethod.values.map((method) => method.name).toList(), [
      'muslim_world_league',
      'egyptian',
      'karachi',
      'umm_al_qura',
      'dubai',
      'moon_sighting_committee',
      'north_america',
      'kuwait',
      'qatar',
      'singapore',
      'turkey',
      'tehran',
      'unified_london_times',
      'other',
      'wifaqul_ulama'
    ]);
  });

  test('Ordinary events, madhabs and method offsets follow raw solar events',
      () {
    for (final coordinates in [
      london,
      aberdeen,
      Coordinates(30.0444, 31.2357),
      Coordinates(-33.9249, 18.4241)
    ]) {
      final date = DateTime.utc(2026, 2, 10);
      final solar = SolarTime(date, coordinates);
      for (final madhab in Madhab.values) {
        final params = parameters()..madhab = madhab;
        final result = times(coordinates, date, params);
        expect(result.fajr,
            rounded(raw(date, solar.twilightHourAngle(-18, false))));
        expect(result.sunrise, rounded(raw(date, solar.sunrise)));
        expect(result.dhuhr,
            rounded(raw(date, solar.transit).add(const Duration(minutes: 4))));
        expect(result.maghrib,
            rounded(raw(date, solar.sunset).add(const Duration(minutes: 5))));
        expect(result.asr,
            rounded(raw(date, solar.afternoon(madhab.getShadowLength()))));
        expect(
            result.isha,
            rounded(raw(
                date,
                solar.twilightHourAngle(
                    coordinates.latitude >= 48 ? -15 : -18, true))));
      }
    }
  });

  test(
      'Latitude equality chooses northern angle without mutating shared parameters',
      () {
    final params = parameters();
    final date = DateTime.utc(2026, 2, 10);
    for (final latitude in [48.001, 47.999, 48.0, -48.0, 47.999, 48.001]) {
      final coordinates = Coordinates(latitude, 0);
      final result = times(coordinates, date, params);
      final solar = SolarTime(date, coordinates);
      expect(
          result.isha,
          rounded(raw(date,
              solar.twilightHourAngle(latitude >= 48 ? -15 : -18, true))));
      expect(params.ishaAngle, 18);
      expect(params.fajrAngle, 18);
      expect(params.method, CalculationMethod.wifaqul_ulama);
    }
  });

  test('All generic high latitude rules are ignored even for valid twilight',
      () {
    final date = DateTime.utc(2026, 4, 15);
    final baseline = prayers(times(london, date));
    for (final rule in HighLatitudeRule.values) {
      final params = parameters()..highLatitudeRule = rule;
      expect(prayers(times(london, date, params)), baseline);
      final summer = DateTime.utc(2026, 6, 15);
      expect(prayers(times(london, summer, params)),
          prayers(times(london, summer)));
    }
    final generic = CalculationParameters(fajrAngle: 18, ishaAngle: 15)
      ..highLatitudeRule = HighLatitudeRule.seventh_of_the_night;
    expect(times(london, date).fajr.isBefore(times(london, date, generic).fajr),
        isTrue);
  });

  test('Named profile rejects custom angles and intervals', () {
    final mutations = <void Function(CalculationParameters)>[
      (p) => p.fajrAngle = 17,
      (p) => p.ishaAngle = 15,
      (p) => p.ishaAngle = null,
      (p) => p.ishaInterval = 65,
      (p) => p.ishaInterval = -1,
      (p) => p.maghribAngle = 0,
    ];
    for (final mutate in mutations) {
      final params = parameters();
      mutate(params);
      expect(() => times(london, DateTime.utc(2026, 2, 10), params),
          throwsArgumentError);
    }
  });

  test(
      'Signed user adjustments are applied exactly once after policy selection',
      () {
    final date = DateTime.utc(2026, 6, 15);
    final baseline = prayers(times(london, date));
    final params = parameters()
      ..adjustments = PrayerAdjustments(
          fajr: -7, sunrise: 3, dhuhr: -2, asr: 9, maghrib: -4, isha: 6);
    final adjusted = prayers(times(london, date, params));
    final offsets = [-7, 3, -2, 9, -4, 6];
    for (var index = 0; index < offsets.length; index++) {
      expect(adjusted[index],
          baseline[index].add(Duration(minutes: offsets[index])));
    }
  });

  for (final year in [2024, 2026]) {
    for (final coordinates in [london, aberdeen]) {
      test(
          'Full twilight transition season preserves boundaries and rebases last dawn $year ${coordinates.latitude}',
          () {
        DateTime? lastDawn;
        DateTime? lastDawnDate;
        var absentDawnDays = 0;
        var absentIshaDays = 0;
        var clippedPresentIshaDays = 0;
        var dawnTransitions = 0;
        var ishaTransitions = 0;
        bool? priorDawnValid;
        bool? priorIshaValid;
        final start = DateTime.utc(year, 3, 1);
        final end = DateTime.utc(year, 10, 1);
        final referenceCap = cap(start, coordinates).difference(start);
        for (var date = start;
            date.isBefore(end);
            date = date.add(const Duration(days: 1))) {
          final solar = SolarTime(date, coordinates);
          final dawnHours = solar.twilightHourAngle(-18, false);
          final ishaHours = solar.twilightHourAngle(-15, true);
          final result = times(coordinates, date);
          if (priorDawnValid != null && priorDawnValid != dawnHours.isFinite) {
            dawnTransitions++;
          }
          if (priorIshaValid != null && priorIshaValid != ishaHours.isFinite) {
            ishaTransitions++;
          }
          priorDawnValid = dawnHours.isFinite;
          priorIshaValid = ishaHours.isFinite;
          if (dawnHours.isFinite) {
            lastDawn = raw(date, dawnHours);
            lastDawnDate = date;
            expect(result.fajr, rounded(lastDawn));
          } else {
            absentDawnDays++;
            expect(result.fajr,
                rounded(date.add(lastDawn!.difference(lastDawnDate!))));
          }
          final reference = date.add(referenceCap);
          if (ishaHours.isFinite) {
            final event = raw(date, ishaHours);
            if (event.isAfter(reference)) clippedPresentIshaDays++;
            expect(result.isha,
                rounded(event.isBefore(reference) ? event : reference));
          } else {
            absentIshaDays++;
            expect(result.isha, rounded(reference));
          }
        }
        expect(dawnTransitions, 2);
        expect(
            ishaTransitions, coordinates.latitude == london.latitude ? 0 : 2);
        expect(absentDawnDays, greaterThan(0));
        expect(
            absentIshaDays,
            coordinates.latitude == london.latitude
                ? equals(0)
                : greaterThan(0));
        expect(clippedPresentIshaDays, greaterThan(0));
      });
    }
  }

  test(
      'Nisf uses previous raw sunset, not the upcoming night or adjusted Maghrib',
      () {
    final date = DateTime.utc(2026, 6, 1);
    final previous = date.subtract(const Duration(days: 1));
    final tomorrow = date.add(const Duration(days: 1));
    final sunset = raw(previous, SolarTime(previous, london).sunset);
    final sunrise = raw(date, SolarTime(date, london).sunrise);
    final midpoint = sunset
        .add(Duration(seconds: sunrise.difference(sunset).inSeconds ~/ 2));
    final params = parameters()
      ..wifaqulOptions =
          const WifaqulOptions(fajrRule: WifaqulFajrRule.nisf_al_layl);
    expect(times(london, date, params).fajr, rounded(midpoint));
    final todaySunset = raw(date, SolarTime(date, london).sunset);
    final nextSunrise = raw(tomorrow, SolarTime(tomorrow, london).sunrise);
    final wrong = todaySunset.add(
        Duration(seconds: nextSunrise.difference(todaySunset).inSeconds ~/ 2));
    expect(times(london, date, params).fajr, isNot(rounded(wrong)));
    final ordinary = DateTime.utc(2026, 3, 1);
    expect(times(london, ordinary, params).fajr, times(london, ordinary).fajr);
  });

  test(
      'Seventh policy caps present Isha but absent Isha uses annual longest daylight sunset',
      () {
    final params = parameters()
      ..wifaqulOptions =
          const WifaqulOptions(ishaRule: WifaqulIshaRule.seventh_of_night);
    final date = DateTime.utc(2026, 4, 15);
    final solar = SolarTime(date, london);
    final sunset = raw(date, solar.sunset);
    final tomorrow = date.add(const Duration(days: 1));
    final nextSunrise = raw(tomorrow, SolarTime(tomorrow, london).sunrise);
    final seventh = sunset
        .add(Duration(seconds: nextSunrise.difference(sunset).inSeconds ~/ 7));
    final angle = raw(date, solar.twilightHourAngle(-15, true));
    expect(times(london, date, params).isha,
        rounded(angle.isBefore(seventh) ? angle : seventh));
    final summer = DateTime.utc(2026, 6, 1);
    expect(SolarTime(summer, aberdeen).twilightHourAngle(-15, true).isFinite,
        isFalse);
    expect(
        times(aberdeen, summer, params).isha, rounded(cap(summer, aberdeen)));
    final dailyCap = raw(summer, SolarTime(summer, aberdeen).sunset)
        .add(const Duration(minutes: 65));
    expect(times(aberdeen, summer).isha, isNot(rounded(dailyCap)));
    final cairo = Coordinates(30, 31);
    expect(prayers(times(cairo, date, params)), prayers(times(cairo, date)));
  });

  test(
      'UTC, local and signed offsets preserve instants across DST travel zones',
      () {
    timezone_data.initializeTimeZones();
    for (final date in [
      DateTime.utc(2026, 3, 28),
      DateTime.utc(2026, 3, 29),
      DateTime.utc(2026, 10, 25)
    ]) {
      final utc = prayers(times(london, date));
      final local =
          prayers(PrayerTimes(london, DateComponents.from(date), parameters()));
      expect(local.map((value) => value.toUtc()).toList(), utc);
      for (final offset in [
        const Duration(hours: -7),
        const Duration(hours: 5, minutes: 30)
      ]) {
        final shifted = prayers(PrayerTimes.utcOffset(
            london, DateComponents.from(date), parameters(), offset));
        expect(shifted, utc.map((value) => value.add(offset)).toList());
      }
      for (final zone in ['Europe/London', 'America/New_York', 'Asia/Tokyo']) {
        final location = timezone.getLocation(zone);
        expect(
            utc
                .map((value) =>
                    timezone.TZDateTime.from(value, location).toUtc())
                .toList(),
            utc);
      }
    }
  });

  test('East and west UTC midnight rollover remains absolute', () {
    final date = DateTime.utc(2026, 2, 10);
    final east = Coordinates(30, 170);
    final west = Coordinates(30, -170);
    for (final coordinates in [east, west]) {
      final solar = SolarTime(date, coordinates);
      expect(times(coordinates, date).fajr,
          rounded(raw(date, solar.twilightHourAngle(-18, false))));
      expect(times(coordinates, date).isha,
          rounded(raw(date, solar.twilightHourAngle(-18, true))));
    }
    expect(times(east, date).fajr.isBefore(date), isTrue);
    expect(times(west, date).isha.isAfter(date.add(const Duration(days: 1))),
        isTrue);
  });

  test(
      'Polar and unauthorized southern missing events reject rather than substitute latitude',
      () {
    for (final coordinates in [Coordinates(80, 0), Coordinates(-80, 0)]) {
      for (final month in [6, 12]) {
        expect(() => times(coordinates, DateTime.utc(2026, month, 21)),
            throwsArgumentError);
      }
    }
    expect(() => times(Coordinates(-57, 0), DateTime.utc(2026, 12, 21)),
        throwsArgumentError);
    expect(() => times(Coordinates(67, 0), DateTime.utc(2026, 2, 10)),
        throwsArgumentError);
  });

  test('Explicit method offsets replace defaults and finalize once', () {
    final date = DateTime.utc(2026, 6, 15);
    final params = parameters()
      ..methodAdjustments = PrayerAdjustments(
          fajr: 2, sunrise: -3, dhuhr: 7, asr: -4, maghrib: 1, isha: -6)
      ..adjustments = PrayerAdjustments(
          fajr: -1, sunrise: 1, dhuhr: -2, asr: 2, maghrib: -3, isha: 4);
    final baseline = prayers(times(london, date));
    final actual = prayers(times(london, date, params));
    final differences = [1, -2, 1, -2, -7, -2];
    for (var index = 0; index < differences.length; index++) {
      expect(actual[index],
          baseline[index].add(Duration(minutes: differences[index])));
    }
  });

  test(
      'Interleaving exact coordinates and years plus cache eviction preserves reference outputs',
      () {
    final date = DateTime.utc(2024, 6, 15);
    final baseline = prayers(times(london, date));
    final nearby =
        Coordinates(london.latitude + 0.00001, london.longitude + 0.00001);
    final nearbyBaseline = prayers(times(nearby, date));
    for (var index = 0; index < 40; index++) {
      final coordinates = Coordinates(49 + index / 10, -20 + index / 2);
      final request = DateTime.utc(2020 + index % 7, 6, 15);
      final first = prayers(times(coordinates, request));
      expect(prayers(times(coordinates, request)), first);
      expect(WifaqulTwilight.cachedReferenceCount, lessThanOrEqualTo(32));
    }
    expect(prayers(times(london, date)), baseline);
    expect(prayers(times(nearby, date)), nearbyBaseline);
    expect(prayers(times(london, date)), baseline);
  });
}
