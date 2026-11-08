import 'dart:convert';
import 'dart:io';

import 'package:adhan/adhan.dart';
import 'package:adhan/src/internal/shadow_length.dart';
import 'package:adhan/src/internal/solar_time.dart';

import '../parity/grid.dart' show City, dayLabel, days2026, prayerNames;
import '../parity/rounding_golden.dart' show ummAlQuraCities;

const vectorsPath = 'test/rounding/vectors.json';

const _wholeSecondsPastMinute = [0, 1, 59];

const _margin = 0.25;

const _londonDay = '2026-03-01';

const _londonPrayers = ['fajr', 'sunrise'];

String instant(DateTime utc) => '${utc.toIso8601String().substring(0, 19)}Z';

String _milliseconds(DateTime utc) =>
    '${utc.toIso8601String().substring(0, 23)}Z';

Map<String, String> _expected(
    String prayer, DateTime minute, int microsecondsPast) {
  final second = microsecondsPast ~/ Duration.microsecondsPerSecond;
  DateTime after(bool next) => minute.add(Duration(minutes: next ? 1 : 0));
  return {
    'nearest': instant(after(second >= 30)),
    'up': instant(after(second > 0)),
    'none': instant(minute.add(Duration(seconds: second))),
    'startsUpSunriseDown':
        instant(after(prayer != 'sunrise' && microsecondsPast > 0)),
  };
}

Map<String, Object> _vector(String method, String prayer, City city,
    DateTime day, DateTime minute, int microsecondsPast) {
  final unrounded = minute.add(Duration(microseconds: microsecondsPast));
  return {
    'method': method,
    'prayer': prayer,
    'secondsPastMinute': (microsecondsPast ~/ 1000) / 1000,
    'latitude': city.latitude,
    'longitude': city.longitude,
    'date': dayLabel(day),
    'unrounded': _milliseconds(unrounded),
    'expected': _expected(prayer, minute, microsecondsPast),
  };
}

double _solarHours(String prayer, SolarTime solar, double fajrAngle) {
  switch (prayer) {
    case 'fajr':
      return solar.hourAngle(-fajrAngle, false);
    case 'sunrise':
      return solar.sunrise;
    case 'dhuhr':
      return solar.transit;
    case 'asr':
      return solar.afternoon(ShadowLength.single);
    case 'maghrib':
    case 'isha':
      return solar.sunset;
  }
  throw ArgumentError.value(prayer, 'prayer');
}

bool _clearOfSecondBoundary(double hours) {
  final seconds = hours * 3600;
  final fraction = seconds - seconds.floorToDouble();
  return fraction >= _margin && fraction <= 1 - _margin;
}

Map<String, Object> _ummAlQura(String prayer, int wholeSeconds) {
  final parameters = CalculationMethod.umm_al_qura.getParameters()
    ..rounding = Rounding.none;
  final ishaDelay = Duration(minutes: prayer == 'isha' ? 90 : 0);
  for (final city in ummAlQuraCities) {
    for (final day in days2026) {
      final date = DateComponents(day.year, day.month, day.day);
      final hours = _solarHours(
          prayer,
          SolarTime(day, city.coordinates, parameters.hourAngleCorrection),
          parameters.fajrAngle);
      if (!_clearOfSecondBoundary(hours)) continue;
      final exact = day
          .add(Duration(
              microseconds: (hours * Duration.microsecondsPerHour).floor()))
          .add(ishaDelay);
      final microsecondsPast =
          exact.microsecondsSinceEpoch % Duration.microsecondsPerMinute;
      if (microsecondsPast ~/ Duration.microsecondsPerSecond != wholeSeconds) {
        continue;
      }
      final minute = exact.subtract(Duration(microseconds: microsecondsPast));
      final none = PrayerTimes.utc(city.coordinates, date, parameters)
          .timeForPrayer(Prayer.values.byName(prayer))!;
      if (none != minute.add(Duration(seconds: wholeSeconds))) {
        throw StateError('$prayer on ${dayLabel(day)} at ${city.name} '
            'is not the floored solar instant');
      }
      return _vector(CalculationMethod.umm_al_qura.name, prayer, city, day,
          minute, microsecondsPast);
    }
  }
  throw StateError('no $prayer at $wholeSeconds s past a minute');
}

Map<String, Object> _london(String prayer) {
  const london = City('London', 51.5074, -0.1278);
  final day = DateTime.parse('${_londonDay}T00:00:00Z');
  final parameters = CalculationMethod.unified_london_times.getParameters()
    ..rounding = Rounding.none;
  final published = PrayerTimes.utc(london.coordinates,
          DateComponents(day.year, day.month, day.day), parameters)
      .timeForPrayer(Prayer.values.byName(prayer))!;
  if (published.microsecondsSinceEpoch % Duration.microsecondsPerMinute != 0) {
    throw StateError('London $prayer on $_londonDay is not a whole minute');
  }
  return _vector(CalculationMethod.unified_london_times.name, prayer, london,
      day, published, 0);
}

void main() {
  final vectors = {
    'output': 'UTC',
    'cases': [
      for (final prayer in prayerNames)
        for (final second in _wholeSecondsPastMinute)
          _ummAlQura(prayer, second),
      for (final prayer in _londonPrayers) _london(prayer),
    ],
  };
  File(vectorsPath)
      .writeAsStringSync('${JsonEncoder.withIndent('  ').convert(vectors)}\n');
}
