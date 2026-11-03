import 'dart:convert';
import 'dart:io';

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:adhan/src/data/malaysia_zones_data.dart';
import 'package:test/test.dart';

import '../tool/malaysia/src/csv.dart';

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
    const outside = {
      'Singapore': [1.3521, 103.8198],
      'Woodlands, Singapore': [1.43801, 103.78877],
      'Tuas, Singapore': [1.32139, 103.65667],
      'Pulau Ubin, Singapore': [1.41194, 103.96389],
      'Bandar Seri Begawan, Brunei': [4.9031, 114.9398],
      'Bangar, Brunei': [4.70861, 115.07167],
      'Muara, Brunei': [5.02699, 115.06913],
      'Seria, Brunei': [4.60637, 114.32476],
      'Hat Yai, Thailand': [7.00836, 100.47668],
      'Sadao, Thailand': [6.63883, 100.42342],
      'Satun, Thailand': [6.62314, 100.06676],
      'Betong, Thailand': [5.77434, 101.07231],
      'Su-ngai Kolok, Thailand': [6.02977, 101.96586],
      'Narathiwat, Thailand': [6.42639, 101.82308],
      'Pontianak, Indonesia': [-0.0263, 109.3425],
      'Singkawang, Indonesia': [0.90925, 108.98463],
      'Sambas, Indonesia': [1.33333, 109.25],
      'Long Bawan, Indonesia': [3.89851, 115.67505],
      'Nunukan, Indonesia': [4.13841, 117.6507],
      'Tarakan, Indonesia': [3.31332, 117.59152],
      'Bongao, Philippines': [5.08333, 119.78333],
      'Sitangkai, Philippines': [4.74873, 119.40246],
      'Taganak, Philippines': [6.07328, 118.31226],
      'Mapun, Philippines': [6.9747, 118.5144],
      'Balabac, Philippines': [7.98333, 117.06667],
      'Jolo, Philippines': [6.053, 121.00422],
    };
    for (final date in [
      DateComponents(2026, 6, 1),
      DateComponents(2027, 6, 1)
    ]) {
      for (final place in outside.entries) {
        expect(map.zoneAt(place.value[0], place.value[1], date), isNull,
            reason: '${place.key} ${date.year}');
      }
    }
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
