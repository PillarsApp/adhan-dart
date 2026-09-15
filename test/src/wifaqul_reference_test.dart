import 'dart:convert';
import 'dart:io';

import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(
    File('test/data/wifaqul-astronomy-engine.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final tolerance =
      (fixture['provenance']['toleranceSeconds'] as num).toDouble();

  for (final row in fixture['cases'] as List<dynamic>) {
    test('Independent astronomy: ${row['name']}', () {
      final parameters = CalculationMethod.wifaqul_ulama.getParameters()
        ..madhab = row['madhab'] == 'hanafi' ? Madhab.hanafi : Madhab.shafi
        ..wifaqulOptions = WifaqulOptions(
          fajrRule: row['fajrRule'] == 'nisf_al_layl'
              ? WifaqulFajrRule.nisf_al_layl
              : WifaqulFajrRule.aqrabul_ayyam,
          ishaRule: row['ishaRule'] == 'seventh_of_night'
              ? WifaqulIshaRule.seventh_of_night
              : WifaqulIshaRule.longest_day,
        );
      final times = PrayerTimes.utc(
        Coordinates((row['latitude'] as num).toDouble(),
            (row['longitude'] as num).toDouble()),
        DateComponents.from(DateTime.parse('${row['date']}T00:00:00Z')),
        parameters,
      );
      final actual = <String, DateTime>{
        'fajr': times.fajr,
        'sunrise': times.sunrise,
        'dhuhr': times.dhuhr,
        'asr': times.asr,
        'maghrib': times.maghrib,
        'isha': times.isha,
      };
      for (final expected
          in (row['expected'] as Map<String, dynamic>).entries) {
        final reference = DateTime.parse(expected.value as String);
        final difference =
            actual[expected.key]!.difference(reference).inMilliseconds.abs() /
                1000;
        expect(difference, lessThanOrEqualTo(tolerance),
            reason:
                '${row['name']} ${expected.key}: ${actual[expected.key]} versus $reference');
      }
    });
  }
}
