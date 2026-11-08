import 'dart:convert';

import 'package:adhan/adhan.dart';
import 'package:crypto/crypto.dart';

import 'grid.dart';

const goldenRoundings = [Rounding.nearest, Rounding.up, Rounding.none];

const ummAlQuraCities = [
  City('Riyadh', 24.7136, 46.6753),
  City('Mecca', 21.4225, 39.8262),
];

const _goldenCities = [...cities, ...ummAlQuraCities];

String _iso(DateTime time) => time.toUtc().toIso8601String();

String _line(City city, DateTime day, CalculationParameters parameters) {
  final components = DateComponents(day.year, day.month, day.day);
  final PrayerTimes times;
  try {
    times = PrayerTimes.utc(city.coordinates, components, parameters);
  } catch (error) {
    return '${dayLabel(day)}\tthrows ${error.runtimeType}';
  }
  String sunnah;
  try {
    final night = SunnahTimes(times);
    sunnah =
        '${_iso(night.middleOfTheNight)}\t${_iso(night.lastThirdOfTheNight)}';
  } catch (error) {
    sunnah = 'throws ${error.runtimeType}';
  }
  return [
    dayLabel(day),
    times.source.name,
    _iso(times.fajr),
    _iso(times.sunrise),
    _iso(times.dhuhr),
    _iso(times.asr),
    _iso(times.maghrib),
    _iso(times.isha),
    sunnah,
  ].join('\t');
}

Iterable<MapEntry<String, List<String>>> _groups() sync* {
  for (final city in _goldenCities) {
    for (final method in CalculationMethod.values) {
      for (final rounding in goldenRoundings) {
        final lines = [
          for (final day in days2026)
            _line(city, day, method.getParameters()..rounding = rounding)
        ];
        yield MapEntry(
            [city.name, method.name, rounding.name].join('\t'), lines);
      }
    }
  }
}

Map<String, String> roundingGoldenDigests() => {
      for (final group in _groups())
        group.key:
            sha256.convert(utf8.encode(group.value.join('\n'))).toString()
    };

void main(List<String> args) {
  if (args.contains('--full')) {
    for (final group in _groups()) {
      for (final line in group.value) {
        print('${group.key}\t$line');
      }
    }
    return;
  }
  print('city\tmethod\trounding\tsha256');
  roundingGoldenDigests().forEach((key, digest) => print('$key\t$digest'));
}
