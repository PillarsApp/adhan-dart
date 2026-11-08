import 'dart:convert';

import 'package:adhan/src/data/delta_cells_codec.dart';

const _localityKeys = [
  'id',
  'group',
  'zone',
  'names',
  'ref',
  'point',
  'area',
  'validFrom',
  'validTo',
  'successors'
];

String encodeOtt(Map<String, dynamic> input) {
  final columns = (input['columns'] as List).cast<String>();
  final zones = _sortedZones(input['zones'] as List);
  final zoneIndex = {
    for (var i = 0; i < zones.length; i++) zones[i]['id'] as String: i
  };
  final inputZones = (input['zones'] as List).cast<Map>();
  final localities = _sortedLocalities(
      (input['localities'] as List).cast<Map>(), inputZones, zoneIndex);
  final header = <String, dynamic>{
    'authority': input['authority'],
    'revision': input['revision'],
    'part': input['part'],
    'coverage': input['coverage'],
    'columns': columns,
    'asrShadow': input['asrShadow'],
    'zones': zones,
    'localities': localities,
  };
  _requireEncodable(header);
  final out = StringBuffer('OTT 1\n${jsonEncode(header)}\n');
  final rows = (input['rows'] as Map).cast<String, Map>();
  for (final locality in localities) {
    final days = rows[locality['id']];
    if (days == null) continue;
    for (final run in _runs(days.cast<String, List>())) {
      out.write('${locality['id']} ${run.first} '
          '${encodeCells(run.days, columns.length)}\n');
    }
  }
  return out.toString();
}

void _requireEncodable(Object? value) {
  switch (value) {
    case String():
      for (var i = 0; i < value.length; i++) {
        final unit = value.codeUnitAt(i);
        if (unit == 0xFEFF) {
          throw ArgumentError('a string holds U+FEFF, which breaks file.bom');
        }
        if (unit < 0xD800 || unit > 0xDFFF) continue;
        final next = i + 1 < value.length ? value.codeUnitAt(i + 1) : 0;
        if (unit <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
          i++;
          continue;
        }
        throw ArgumentError(
            'a string holds a lone surrogate, which breaks header.json');
      }
    case Map():
      for (final entry in value.entries) {
        _requireEncodable(entry.key);
        _requireEncodable(entry.value);
      }
    case List():
      value.forEach(_requireEncodable);
  }
}

List<Map<String, dynamic>> _sortedZones(List zones) {
  final sorted = [
    for (final zone in zones.cast<Map>())
      <String, dynamic>{
        'id': zone['id'],
        'offsets': [
          for (final offset in (zone['offsets'] as List).cast<List>())
            [offset[0], offset[1]]
        ]..sort((a, b) => (a[0] as String).compareTo(b[0] as String)),
      }
  ];
  sorted.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  return sorted;
}

List<Map<String, dynamic>> _sortedLocalities(
    List<Map> localities, List<Map> inputZones, Map<String, int> zoneIndex) {
  final sorted = <Map<String, dynamic>>[];
  for (final locality in localities) {
    final zoneId = inputZones[locality['zone'] as int]['id'] as String;
    final names = (locality['names'] as Map).cast<String, String>();
    final ordered = <String, dynamic>{};
    for (final key in _localityKeys) {
      if (!locality.containsKey(key)) continue;
      ordered[key] = switch (key) {
        'zone' => zoneIndex[zoneId],
        'names' => {
            for (final language in names.keys.toList()..sort())
              language: names[language]
          },
        'point' => {'radiusM': (locality['point'] as Map)['radiusM']},
        'area' => {
            'polygons': (locality['area'] as Map)['polygons'],
            'toleranceM': (locality['area'] as Map)['toleranceM'],
          },
        'successors' => (locality['successors'] as List).cast<String>().toList()
          ..sort(),
        _ => locality[key],
      };
    }
    sorted.add(ordered);
  }
  sorted.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  return sorted;
}

class _Run {
  final String first;
  final List<List<int>> days = [];

  _Run(this.first);
}

Iterable<_Run> _runs(Map<String, List> days) sync* {
  final dates = days.keys.toList()..sort();
  _Run? run;
  DateTime? previous;
  for (final date in dates) {
    final day = DateTime.parse('${date}T00:00:00Z');
    final continues = previous != null &&
        day.difference(previous).inDays == 1 &&
        day.year == previous.year;
    if (!continues) {
      if (run != null) yield run;
      run = _Run(date);
    }
    run!.days.add(days[date]!.cast<int>());
    previous = day;
  }
  if (run != null) yield run;
}
