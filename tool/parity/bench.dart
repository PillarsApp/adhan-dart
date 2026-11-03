import 'dart:io';

import 'package:adhan/adhan.dart';

import 'grid.dart';

void main(List<String> arguments) {
  final GridOptions options;
  try {
    options = GridOptions.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\nusage: bench.dart ${GridOptions.usage}');
    exit(2);
  }
  final london = cities[1].coordinates;
  final parameters = options.parameters('mwl_mid');
  const constructions = 100000;
  final samples = List<double>.filled(constructions, 0);
  final stopwatch = Stopwatch();
  final ticksPerMicrosecond = stopwatch.frequency / 1000000;
  var checksum = 0;
  for (var i = 0; i < constructions; i++) {
    final day = days2026[i % days2026.length];
    final components = DateComponents(day.year, day.month, day.day);
    stopwatch
      ..reset()
      ..start();
    final times = PrayerTimes.utc(london, components, parameters);
    stopwatch.stop();
    checksum += times.fajr.millisecondsSinceEpoch ~/ 1000;
    samples[i] = stopwatch.elapsedTicks / ticksPerMicrosecond;
  }
  if (checksum <= 0) {
    throw StateError('every London construction must succeed');
  }
  samples.sort();
  final median = samples[constructions ~/ 2];
  stdout.writeln('bench,London,mwl_mid,median_us,${median.toStringAsFixed(3)}');
}
