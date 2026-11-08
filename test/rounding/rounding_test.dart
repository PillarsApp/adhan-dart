import 'dart:convert';
import 'dart:io';

import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

import '../../tool/parity/grid.dart' show dayLabel, days2026;
import '../../tool/parity/rounding_golden.dart';
import '../../tool/rounding/vectors.dart';

DateComponents _date(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return DateComponents(parts[0], parts[1], parts[2]);
}

DateTime _upToMinute(DateTime utc) {
  final past = utc.second > 0 || utc.millisecond > 0 || utc.microsecond > 0;
  return DateTime.utc(
      utc.year, utc.month, utc.day, utc.hour, utc.minute + (past ? 1 : 0));
}

void main() {
  group('vectors', () {
    final cases = (jsonDecode(File(vectorsPath).readAsStringSync())
        as Map<String, dynamic>)['cases'] as List;

    for (final vector in cases.cast<Map<String, dynamic>>()) {
      final method =
          CalculationMethod.values.byName(vector['method'] as String);
      final prayer = Prayer.values.byName(vector['prayer'] as String);
      final seconds = vector['secondsPastMinute'] as num;
      test('${method.name} ${prayer.name} at $seconds s past a minute', () {
        final expected = vector['expected'] as Map<String, dynamic>;
        final coordinates = Coordinates(
            vector['latitude'] as double, vector['longitude'] as double);
        final date = _date(vector['date'] as String);
        for (final rounding in Rounding.values) {
          final parameters = method.getParameters()..rounding = rounding;
          final times = PrayerTimes.utc(coordinates, date, parameters);
          expect(instant(times.timeForPrayer(prayer)!), expected[rounding.name],
              reason: rounding.name);
        }
      });
    }
  });

  test('sunnah times round up to the next minute under startsUpSunriseDown',
      () {
    final riyadh = ummAlQuraCities.first.coordinates;
    final parameters = CalculationMethod.umm_al_qura.getParameters()
      ..rounding = Rounding.startsUpSunriseDown;
    final mismatches = <String>[];
    var partMinutes = 0;
    for (final day in days2026) {
      final today = PrayerTimes.utc(
          riyadh, DateComponents(day.year, day.month, day.day), parameters);
      final tomorrow = PrayerTimes.utc(
          riyadh, DateComponents.from(day.add(Duration(days: 1))), parameters);
      final night = tomorrow.fajr.difference(today.maghrib);
      final middle =
          today.maghrib.add(Duration(microseconds: night.inMicroseconds ~/ 2));
      final lastThird = today.maghrib
          .add(Duration(microseconds: night.inMicroseconds * 2 ~/ 3));
      if (middle.second > 0) partMinutes++;
      final sunnah = SunnahTimes(today);
      if (sunnah.middleOfTheNight != _upToMinute(middle) ||
          sunnah.lastThirdOfTheNight != _upToMinute(lastThird)) {
        mismatches.add(dayLabel(day));
      }
    }
    expect(partMinutes, greaterThan(0),
        reason: 'some nights must split off the minute');
    expect(mismatches, isEmpty);
  });

  test('every Rounding value keeps its index', () {
    expect(Rounding.values.map((rounding) => rounding.name),
        ['nearest', 'up', 'none', 'startsUpSunriseDown']);
  });

  test('every method keeps the times recorded at 4a50a60 for each rounding',
      () {
    final rows = File('test/rounding/golden_4a50a60.tsv').readAsLinesSync();
    final golden = {
      for (final row in rows.skip(1))
        row.substring(0, row.lastIndexOf('\t')):
            row.substring(row.lastIndexOf('\t') + 1)
    };
    expect(golden, hasLength(630));

    final head = roundingGoldenDigests();
    final changed = [
      for (final entry in golden.entries)
        if (head[entry.key] != entry.value) entry.key.replaceAll('\t', ' ')
    ];
    expect(changed, isEmpty, reason: 'groups whose times changed');
  });
}
