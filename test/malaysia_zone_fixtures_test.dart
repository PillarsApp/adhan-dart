import 'dart:convert';
import 'dart:io';

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:adhan/src/data/malaysia_zones_data.dart';
import 'package:test/test.dart';

import '../bin/src/csv.dart';

void main() {
  final map = MalaysiaZoneMap.parse(malaysiaZonesData);
  final fixtures = readCsv(File('tool/malaysia/town_fixtures.csv'));

  DateComponents dateOf(String iso) {
    final parts = iso.split('-').map(int.parse).toList();
    return DateComponents(parts[0], parts[1], parts[2]);
  }

  test('every town fixture resolves to its zone on its date', () {
    expect(fixtures, isNotEmpty);
    final failures = <String>[];
    for (final fixture in fixtures) {
      final expected = fixture['zone']!.isEmpty ? null : fixture['zone'];
      final actual = map.zoneAt(double.parse(fixture['lat']!),
          double.parse(fixture['lon']!), dateOf(fixture['date']!));
      if (actual != expected) {
        failures.add('${fixture['place']} ${fixture['date']}: '
            'expected ${expected ?? 'none'}, got ${actual ?? 'none'}');
      }
    }
    expect(failures, isEmpty);
  });

  test('the Dart constant equals data/malaysia/malaysia_zones.txt', () {
    final file = File('data/malaysia/malaysia_zones.txt').readAsBytesSync();
    expect(utf8.encode(malaysiaZonesData), equals(file));
  });

  test('points outside Malaysia return no zone', () {
    final date = DateComponents(2026, 6, 1);
    expect(map.zoneAt(1.3521, 103.8198, date), isNull, reason: 'Singapore');
    expect(map.zoneAt(4.9031, 114.9398, date), isNull,
        reason: 'Bandar Seri Begawan');
    expect(map.zoneAt(-0.0263, 109.3425, date), isNull, reason: 'Pontianak');
  });

  test('every successor is in force the day after its zone retires', () {
    final retired = map.zones.where((zone) => zone.validToDay < 99999999);
    expect(retired, isNotEmpty);
    for (final zone in retired) {
      expect(zone.successors, isNotEmpty, reason: zone.code);
      final lastDay = DateTime.utc(zone.validToDay ~/ 10000,
          zone.validToDay ~/ 100 % 100, zone.validToDay % 100);
      final nextDay = lastDay.add(const Duration(days: 1));
      final next = DateComponents(nextDay.year, nextDay.month, nextDay.day);
      expect(zone.inForceOn(next), isFalse, reason: zone.code);
      for (final code in zone.successors) {
        final successor = map.zone(code);
        expect(successor, isNotNull, reason: '${zone.code} -> $code');
        expect(successor!.inForceOn(next), isTrue,
            reason: '${zone.code} -> $code');
      }
    }
  });
}
