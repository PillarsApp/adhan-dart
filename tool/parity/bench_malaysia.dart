import 'dart:io';

import 'package:adhan/adhan.dart';

import 'grid.dart';

const constructions = 100000;

const malaysianCities = [
  City('KualaLumpur', 3.1390, 101.6869),
  City('KotaKinabalu', 5.9749, 116.0724),
  City('JohorBahru', 1.4655, 103.7578),
  City('Kuching', 1.5535, 110.3593),
  City('GeorgeTown', 5.4164, 100.3327),
  City('ShahAlam', 3.0733, 101.5185),
];

final components2026 = [
  for (final day in days2026) DateComponents(day.year, day.month, day.day)
];

void main() {
  final kualaLumpur = cities[0].coordinates;
  final cold = Stopwatch()..start();
  final first = PrayerTimes(kualaLumpur, DateComponents(2026, 11, 2),
      CalculationMethod.malaysia_official.getParameters());
  cold.stop();
  if (first.source != PrayerTimesSource.official) {
    throw StateError('Kuala Lumpur must read an official row');
  }
  stdout.writeln('bench,cold_first_lookup_ms,'
      '${(cold.elapsedMicroseconds / 1000).toStringAsFixed(3)}');

  final manual = CalculationMethod.malaysia_official.getParameters()
    ..malaysiaZone = 'WLY01';
  report('warm_lookup_us', (i) {
    final times = PrayerTimes.utc(
        kualaLumpur, components2026[i % components2026.length], manual);
    return times.fajr.millisecondsSinceEpoch ~/ 1000;
  });

  final automatic = CalculationMethod.malaysia_official.getParameters();
  report('warm_lookup_auto_us', (i) {
    final times = PrayerTimes.utc(
        kualaLumpur, components2026[i % components2026.length], automatic);
    return times.fajr.millisecondsSinceEpoch ~/ 1000;
  });

  report('zone_resolve_us', (i) {
    final city = malaysianCities[i % malaysianCities.length];
    final zone = MalaysiaZones.resolve(
        city.coordinates, components2026[i % components2026.length]);
    return zone == null ? 0 : zone.code.length;
  });

  final london = cities[1].coordinates;
  final mwl = GridOptions().parameters('mwl_mid');
  report('existing_mwl_us', (i) {
    final times =
        PrayerTimes.utc(london, components2026[i % components2026.length], mwl);
    return times.fajr.millisecondsSinceEpoch ~/ 1000;
  });
}

void report(String name, int Function(int) construct) {
  final samples = List<double>.filled(constructions, 0);
  final stopwatch = Stopwatch();
  final ticksPerMicrosecond = stopwatch.frequency / 1000000;
  var checksum = 0;
  for (var i = 0; i < constructions; i++) {
    stopwatch
      ..reset()
      ..start();
    checksum += construct(i);
    stopwatch.stop();
    samples[i] = stopwatch.elapsedTicks / ticksPerMicrosecond;
  }
  if (checksum <= 0) {
    throw StateError('the $name loop did no work');
  }
  samples.sort();
  final median = samples[constructions ~/ 2];
  stdout.writeln('bench,$name,${median.toStringAsFixed(3)}');
}
