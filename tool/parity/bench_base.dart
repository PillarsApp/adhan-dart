import 'dart:io';

import 'package:adhan/adhan.dart';

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('usage: bench_base.dart');
    exit(2);
  }
  final parameters = CalculationMethod.muslim_world_league.getParameters()
    ..highLatitudeRule = HighLatitudeRule.middle_of_the_night;
  printLondonMedian(parameters);
}

void printLondonMedian(CalculationParameters parameters) {
  final london = Coordinates(51.5074, -0.1278);
  final days = List<DateTime>.generate(
      365, (offset) => DateTime.utc(2026, 1, 1).add(Duration(days: offset)));
  const constructions = 100000;
  final samples = List<double>.filled(constructions, 0);
  final stopwatch = Stopwatch();
  final ticksPerMicrosecond = stopwatch.frequency / 1000000;
  var checksum = 0;
  for (var i = 0; i < constructions; i++) {
    final day = days[i % days.length];
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
