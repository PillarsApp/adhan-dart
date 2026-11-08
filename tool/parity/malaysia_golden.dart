import 'dart:convert';

import 'package:adhan/adhan.dart';
import 'package:crypto/crypto.dart';

const _offsetSets = <String, List<int>>{
  'zero': [0, 0, 0, 0, 0, 0],
  'mixed': [2, -1, 1, -2, 3, -3],
  'wide': [-5, 5, -4, 4, -6, 6],
};

const _modes = ['auto', 'manual'];

List<MalaysiaZone> _zones() {
  final byCode = <String, MalaysiaZone>{};
  for (final date in [
    DateComponents(2026, 1, 1),
    DateComponents(2027, 12, 31)
  ]) {
    for (final zone in MalaysiaZones.on(date)) {
      byCode[zone.code] = zone;
    }
  }
  final codes = byCode.keys.toList()..sort();
  return [for (final code in codes) byCode[code]!];
}

List<DateComponents> _days() {
  final days = <DateComponents>[];
  for (final year in [2026, 2027]) {
    final end = DateTime.utc(year + 1, 1, 1);
    for (var day = DateTime.utc(year, 1, 1);
        day.isBefore(end);
        day = DateTime.utc(day.year, day.month, day.day + 1)) {
      days.add(DateComponents(day.year, day.month, day.day));
    }
  }
  return days;
}

PrayerAdjustments _adjustments(List<int> minutes) => PrayerAdjustments(
    fajr: minutes[0],
    sunrise: minutes[1],
    dhuhr: minutes[2],
    asr: minutes[3],
    maghrib: minutes[4],
    isha: minutes[5]);

String _iso(DateTime time) => time.toUtc().toIso8601String();

Iterable<MapEntry<String, List<String>>> _groups() sync* {
  final days = _days();
  for (final zone in _zones()) {
    for (final madhab in [Madhab.shafi, Madhab.hanafi]) {
      for (final offsets in _offsetSets.entries) {
        for (final mode in _modes) {
          final lines = <String>[];
          for (final day in days) {
            final parameters =
                CalculationMethod.malaysia_official.getParameters();
            parameters.madhab = madhab;
            parameters.adjustments = _adjustments(offsets.value);
            if (mode == 'manual') {
              parameters.malaysiaZone = zone.code;
            }
            final times = PrayerTimes.utc(zone.referencePoint, day, parameters);
            final date =
                '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            lines.add([
              date,
              times.source.name,
              times.malaysiaZone?.code ?? '-',
              _iso(times.fajr),
              _iso(times.sunrise),
              _iso(times.dhuhr),
              _iso(times.asr),
              _iso(times.maghrib),
              _iso(times.isha),
            ].join('\t'));
          }
          yield MapEntry(
              [zone.code, madhab.name, offsets.key, mode].join('\t'), lines);
        }
      }
    }
  }
}

Map<String, String> malaysiaGoldenDigests() => {
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
  print('zone\tmadhab\toffsets\tmode\tsha256');
  malaysiaGoldenDigests().forEach((key, digest) => print('$key\t$digest'));
}
