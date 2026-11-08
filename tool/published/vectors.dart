import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:adhan/adhan.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:adhan/src/internal/shadow_length.dart';
import 'package:adhan/src/internal/solar_time.dart';

import 'ott_encoder.dart';

const vectorsDir = 'test/published/vectors';

const _core = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

const _earthRadius = 6371008.8;

void main() {
  final files = generateVectors();
  for (final entry in files.entries) {
    final file = File('$vectorsDir/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  stdout.writeln('wrote ${files.length} files under $vectorsDir');
}

Map<String, String> generateVectors() {
  final files = <String, String>{};
  final cases = <Map<String, dynamic>>[];
  for (final vector in [_kacstLike(), _shapes(), _dst(), _lateIsha()]) {
    files['valid/${vector.name}.ott'] = encodeOtt(vector.input);
    files['valid/${vector.name}.input.json'] = _pretty(vector.input);
    cases.addAll(vector.cases);
  }
  files['expected.json'] = _pretty({'cases': cases});
  final malformed = _malformed();
  for (final entry in malformed) {
    files['malformed/${entry.file}'] = entry.content;
  }
  files['malformed/index.json'] = _pretty([
    for (final entry in malformed)
      {'file': entry.file, 'stage': entry.stage, 'reason': entry.reason}
  ]);
  files['README.md'] = _readme;
  return files;
}

String _pretty(Object value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

class _Vector {
  final String name;
  final Map<String, dynamic> input;
  final List<Map<String, dynamic>> cases = [];

  _Vector(this.name, this.input);

  List<String> get columns => (input['columns'] as List).cast<String>();

  int get asrShadow => input['asrShadow'] as int;

  Map _locality(String id) => (input['localities'] as List)
      .cast<Map>()
      .singleWhere((l) => l['id'] == id);

  int _offsetOn(String localityId, String date) {
    final zone = (input['zones'] as List)[_locality(localityId)['zone'] as int];
    var offset = 0;
    for (final entry in (zone['offsets'] as List).cast<List>()) {
      if ((entry[0] as String).compareTo(date) <= 0) offset = entry[1] as int;
    }
    return offset;
  }

  void row(String name, List<double> coordinates, String date,
      {String? localityId, required String locality}) {
    final minutes =
        ((input['rows'] as Map)[locality] as Map)[date] as List<int>;
    final offset = _offsetOn(locality, date);
    final midnight = DateTime.parse('${date}T00:00:00Z');
    DateTime instant(int wall) =>
        midnight.add(Duration(minutes: wall - offset));
    final published = {
      for (var i = 0; i < columns.length; i++)
        columns[i]: _iso(instant(minutes[i]))
    };
    final ref = (_locality(locality)['ref'] as List).cast<int>();
    final point = Coordinates(ref[0] / 1e6, ref[1] / 1e6);
    final asr = instant(minutes[columns.indexOf('asr')]);
    final hanafiColumn = columns.indexOf('asrHanafi');
    final DateTime shafi;
    final DateTime hanafi;
    if (asrShadow == 1) {
      shafi = asr;
      hanafi = hanafiColumn >= 0
          ? instant(minutes[hanafiColumn])
          : asr.add(Duration(minutes: _shift(midnight, point, 2, 1)));
    } else {
      hanafi = asr;
      shafi = asr.add(Duration(minutes: _shift(midnight, point, 1, 2)));
    }
    cases.add({
      'name': name,
      'vector': 'valid/${this.name}.ott',
      'coordinates': coordinates,
      'localityId': localityId,
      'date': date,
      'result': 'row',
      'locality': locality,
      'published': published,
      'asr': {'shafi': _iso(shafi), 'hanafi': _iso(hanafi)},
    });
  }

  void noRow(String name, List<double> coordinates, String date,
      {String? localityId, required String locality}) {
    cases.add({
      'name': name,
      'vector': 'valid/${this.name}.ott',
      'coordinates': coordinates,
      'localityId': localityId,
      'date': date,
      'result': 'noRow',
      'locality': locality,
    });
  }

  void noLocality(String name, List<double> coordinates, String date,
      {String? localityId}) {
    cases.add({
      'name': name,
      'vector': 'valid/${this.name}.ott',
      'coordinates': coordinates,
      'localityId': localityId,
      'date': date,
      'result': 'noLocality',
    });
  }
}

int _shift(
    DateTime midnight, Coordinates point, int userShadow, int rowShadow) {
  final solar = SolarTime(midnight, point);
  ShadowLength length(int shadow) =>
      shadow == 1 ? ShadowLength.single : ShadowLength.double;
  return ((solar.afternoon(length(userShadow)) -
              solar.afternoon(length(rowShadow))) *
          60)
      .round();
}

String _iso(DateTime utc) => utc.toIso8601String().replaceFirst('.000', '');

Map<String, dynamic> _zone(String id, List<List<Object>> offsets) =>
    {'id': id, 'offsets': offsets};

Map<String, dynamic> _point(String id, String group, List<int> ref, int radiusM,
        {Map<String, String> names = const {},
        String? validFrom,
        String? validTo,
        List<String>? successors}) =>
    {
      'id': id,
      'group': group,
      'zone': 0,
      'names': names,
      'ref': ref,
      'point': {'radiusM': radiusM},
      if (validFrom != null) 'validFrom': validFrom,
      if (validTo != null) 'validTo': validTo,
      if (successors != null) 'successors': successors,
    };

Map<String, dynamic> _area(String id, String group, List<int> ref,
        List<List<int>> rings, int toleranceM) =>
    {
      'id': id,
      'group': group,
      'zone': 0,
      'names': const <String, String>{},
      'ref': ref,
      'area': {
        'polygons': [
          for (final ring in rings) MalaysiaZoneMap.encodePolyline(ring)
        ],
        'toleranceM': toleranceM,
      },
    };

List<int> _square(int south, int west, int north, int east) =>
    [south, west, north, west, north, east, south, east];

Map<String, List<int>> _days(String first, List<List<int>> days) {
  final start = DateTime.parse('${first}T00:00:00Z');
  return {
    for (var i = 0; i < days.length; i++)
      _date(start.add(Duration(days: i))): days[i]
  };
}

String _date(DateTime day) => day.toIso8601String().substring(0, 10);

_Vector _kacstLike() {
  const riyadh2026 = [
    [315, 397, 717, 897, 1037, 1127],
    [315, 397, 718, 897, 1037, 1127],
    [315, 398, 718, 898, 1038, 1128],
    [316, 398, 719, 899, 1039, 1129],
    [316, 398, 719, 899, 1039, 1129],
    [316, 398, 720, 900, 1040, 1130],
    [316, 398, 720, 901, 1041, 1131],
    [317, 399, 720, 901, 1041, 1131],
    [317, 399, 721, 902, 1042, 1132],
    [317, 399, 721, 903, 1043, 1133],
  ];
  const riyadh2027 = [
    [315, 397, 717, 896, 1036, 1126],
    [315, 397, 718, 897, 1037, 1127],
    [315, 398, 718, 898, 1038, 1128],
    [316, 398, 719, 898, 1038, 1128],
    [316, 398, 719, 899, 1039, 1129],
    [316, 398, 719, 900, 1040, 1130],
    [316, 398, 720, 900, 1040, 1130],
    [317, 399, 720, 901, 1041, 1131],
    [317, 399, 721, 902, 1042, 1132],
    [317, 399, 721, 902, 1043, 1133],
  ];
  const mecca2026 = [
    [338, 418, 745, 929, 1070, 1160],
    [338, 418, 745, 930, 1071, 1161],
    [338, 419, 746, 931, 1072, 1162],
    [339, 419, 746, 931, 1072, 1162],
    [339, 419, 747, 932, 1073, 1163],
    [339, 419, 747, 932, 1074, 1164],
    [339, 420, 747, 933, 1074, 1164],
    [340, 420, 748, 934, 1075, 1165],
    [340, 420, 748, 934, 1076, 1166],
    [340, 420, 749, 935, 1076, 1166],
  ];
  const mecca2027 = [
    [338, 418, 745, 929, 1070, 1160],
    [338, 418, 745, 930, 1071, 1161],
    [338, 419, 746, 930, 1072, 1162],
    [339, 419, 746, 931, 1072, 1162],
    [339, 419, 746, 932, 1073, 1163],
    [339, 419, 747, 932, 1074, 1164],
    [339, 420, 747, 933, 1074, 1164],
    [340, 420, 748, 934, 1075, 1165],
    [340, 420, 748, 934, 1076, 1166],
    [340, 420, 749, 935, 1076, 1166],
  ];
  const medina2026 = [
    [343, 425, 746, 925, 1065, 1155],
    [343, 425, 746, 926, 1066, 1156],
    [343, 426, 746, 926, 1066, 1156],
    [344, 426, 747, 927, 1067, 1157],
    [344, 426, 747, 928, 1068, 1158],
    [344, 426, 748, 928, 1068, 1158],
    [344, 426, 748, 929, 1069, 1159],
    [345, 427, 749, 930, 1070, 1160],
    [345, 427, 749, 930, 1071, 1161],
    [345, 427, 749, 931, 1071, 1161],
  ];
  const medina2027 = [
    [343, 425, 745, 925, 1065, 1155],
    [343, 425, 746, 926, 1066, 1156],
    [343, 426, 746, 926, 1066, 1156],
    [344, 426, 747, 927, 1067, 1157],
    [344, 426, 747, 928, 1068, 1158],
    [344, 426, 748, 928, 1068, 1158],
    [344, 426, 748, 929, 1069, 1159],
    [345, 427, 749, 929, 1070, 1160],
    [345, 427, 749, 930, 1070, 1160],
    [345, 427, 749, 931, 1071, 1161],
  ];
  final vector = _Vector('kacst-like', {
    'authority': 'sa-umm-al-qura',
    'revision': 12,
    'part': 'all',
    'coverage': ['2026-01-01', '2027-12-31'],
    'columns': _core,
    'asrShadow': 1,
    'zones': [
      _zone('Asia/Riyadh', [
        ['2026-01-01', 180]
      ])
    ],
    'localities': [
      _point('1001', '1001', [24670000, 46690000], 25000,
          names: {'ar': 'الرياض', 'en': 'Riyadh', 'ur': 'ریاض'}),
      _point('1002', '1002', [21426666, 39831666], 25000,
          names: {'ar': 'مكة المكرمة', 'en': 'Mecca', 'ur': 'مکہ مکرمہ'}),
      _point('1003', '1003', [24540000, 39630000], 25000,
          names: {
            'ar': 'المدينة المنورة',
            'en': 'Medina',
            'ur': 'مدینہ منورہ'
          }),
    ],
    'rows': {
      '1001': {
        ..._days('2026-01-01', riyadh2026),
        ..._days('2027-01-01', riyadh2027)
      },
      '1002': {
        ..._days('2026-01-01', mecca2026),
        ..._days('2027-01-01', mecca2027)
      },
      '1003': {
        ..._days('2026-01-01', medina2026),
        ..._days('2027-01-01', medina2027)
      },
    },
  });
  const riyadh = [24.7136, 46.6753];
  vector.row('riyadh-first-day', riyadh, '2026-01-01', locality: '1001');
  vector.row('riyadh-second-year', riyadh, '2027-01-05', locality: '1001');
  vector.row('mecca-kaaba', [21.4225, 39.8262], '2026-01-10', locality: '1002');
  vector.noLocality(
      'jeddah-outside-every-radius', [21.5433, 39.1728], '2026-01-01');
  vector.noRow('riyadh-date-without-row', riyadh, '2026-06-15',
      locality: '1001');
  vector.noRow('riyadh-after-coverage', riyadh, '2028-01-01', locality: '1001');
  vector.row('manual-medina-from-riyadh', riyadh, '2027-01-05',
      localityId: '1003', locality: '1003');
  vector.row('manual-ignores-coordinates', [0.0, 0.0], '2026-01-03',
      localityId: '1001', locality: '1001');
  vector.noLocality('manual-unknown-id', riyadh, '2026-01-01',
      localityId: '9999');
  return vector;
}

_Vector _shapes() {
  const base = [300, 380, 740, 1000, 1100, 1190];
  List<List<int>> three() => [
        for (var i = 0; i < 3; i++) [for (final m in base) m + i]
      ];
  final ringLatitude = 20 + 25000 / _earthRadius * 180 / math.pi;
  final vector = _Vector('shapes', {
    'authority': 'xx-shapes',
    'revision': 1,
    'part': 'all',
    'coverage': ['2026-01-01', '2027-12-31'],
    'columns': _core,
    'asrShadow': 1,
    'zones': [
      _zone('Etc/UTC', [
        ['2026-01-01', 0]
      ])
    ],
    'localities': [
      _area('a-first', 'g', [5500000, 5500000],
          [_square(5000000, 5000000, 6000000, 6000000)], 0),
      _area('a-second', 'g', [6000000, 6000000],
          [_square(5500000, 5500000, 6500000, 6500000)], 0),
      _area('box', 'g', [23500000, 44500000],
          [_square(23000000, 44000000, 24000000, 45000000)], 1000),
      _area(
          'donut',
          'g',
          [11000000, 11000000],
          [
            _square(10000000, 10000000, 12000000, 12000000),
            _square(10800000, 10800000, 11200000, 11200000),
          ],
          0),
      _point('inner', 'g', [23500000, 44500000], 10000),
      _point('new', 'g', [15000000, 48000000], 20000, validFrom: '2027-01-01'),
      _point('old', 'g', [15000000, 48000000], 20000,
          validTo: '2026-12-31', successors: ['new']),
      _point('p-east', 'g', [25000000, 47000000], 60000),
      _point('p-west', 'g', [25000000, 46000000], 60000),
      _point('ring', 'g', [20000000, 50000000], 25000),
    ],
    'rows': {
      for (final id in [
        'a-first',
        'a-second',
        'box',
        'donut',
        'inner',
        'p-east',
        'p-west',
        'ring'
      ])
        id: _days('2026-03-01', three()),
      'old': _days('2026-12-29', three()),
      'new': _days('2027-01-01', three()),
    },
  });
  const day = '2026-03-02';
  _check(
      _haversineMm(25.0, 46.5, 25.0, 47.0) ==
          _haversineMm(25.0, 46.5, 25.0, 46.0),
      'the tie case is equidistant');
  vector.row('tie-breaks-to-the-first-id', [25.0, 46.5], day,
      locality: 'p-east');
  vector.row('nearest-point-wins-east', [25.0, 46.9], day, locality: 'p-east');
  vector.row('nearest-point-wins-west', [25.0, 46.1], day, locality: 'p-west');
  _check(_haversineMm(ringLatitude, 50.0, 20.0, 50.0) == 25000 * 1000,
      'the radius case sits exactly on the radius in millimetres');
  vector.row('point-exactly-at-radius', [ringLatitude, 50.0], day,
      locality: 'ring');
  final beyond = 20 + 25001 / _earthRadius * 180 / math.pi;
  _check(_haversineMm(beyond, 50.0, 20.0, 50.0) > 25000 * 1000,
      'the beyond case lies outside the radius');
  vector.noLocality('point-one-metre-beyond-radius', [beyond, 50.0], day);
  vector.row('point-inside-area-wins', [23.5, 44.5], day, locality: 'inner');
  vector.row('area-outside-the-point-radius', [23.9, 44.9], day,
      locality: 'box');
  _check(
      _edgeDistanceMm(
              24.005, 44.5, _square(23000000, 44000000, 24000000, 45000000)) <=
          1000 * 1000,
      'the tolerance case is within 1000 m of the box');
  vector.row('area-within-tolerance', [24.005, 44.5], day, locality: 'box');
  _check(
      _edgeDistanceMm(
              24.02, 44.5, _square(23000000, 44000000, 24000000, 45000000)) >
          1000 * 1000,
      'the beyond-tolerance case is more than 1000 m from the box');
  vector.noLocality('area-beyond-tolerance', [24.02, 44.5], day);
  vector.noLocality('inside-a-hole', [11.0, 11.0], day);
  vector.row('area-with-a-hole', [10.5, 10.5], day, locality: 'donut');
  vector.row('first-area-in-header-order-wins', [5.75, 5.75], day,
      locality: 'a-first');
  vector.row('retired-locality-on-its-last-day', [15.0, 48.0], '2026-12-31',
      locality: 'old');
  vector.row('successor-on-its-first-day', [15.0, 48.0], '2027-01-01',
      locality: 'new');
  vector.noRow('manual-retired-locality-has-no-row', [15.0, 48.0], '2027-01-01',
      localityId: 'old', locality: 'old');
  vector.noLocality('outside-everything', [0.0, 0.0], day);
  return vector;
}

_Vector _dst() {
  const april = [230, 240, 330, 715, 930, 990, 1100, 1180];
  const october = [240, 250, 350, 700, 900, 960, 1050, 1130];
  List<int> plus(List<int> day, int minutes) =>
      [for (final m in day) m + minutes];
  final vector = _Vector('dst', {
    'authority': 'eg-test',
    'revision': 3,
    'part': 'all',
    'coverage': ['2026-01-01', '2026-12-31'],
    'columns': [
      'imsak',
      'fajr',
      'sunrise',
      'dhuhr',
      'asr',
      'asrHanafi',
      'maghrib',
      'isha'
    ],
    'asrShadow': 1,
    'zones': [
      _zone('Africa/Cairo', [
        ['2026-01-01', 120],
        ['2026-04-24', 180],
        ['2026-10-30', 120],
      ])
    ],
    'localities': [
      _point('cairo', 'cairo', [30044400, 31235700], 30000,
          names: {'ar': 'القاهرة', 'en': 'Cairo'}),
    ],
    'rows': {
      'cairo': {
        ..._days('2026-04-22', [
          april,
          plus(april, 1),
          plus(april, 61),
          plus(april, 62),
          plus(april, 63)
        ]),
        ..._days('2026-10-28', [
          october,
          plus(october, -1),
          plus(october, -61),
          plus(october, -62),
          plus(october, -63)
        ]),
      },
    },
  });
  const cairo = [30.0444, 31.2357];
  vector.row('day-before-summer-time', cairo, '2026-04-23', locality: 'cairo');
  vector.row('first-day-of-summer-time', cairo, '2026-04-24',
      locality: 'cairo');
  vector.row('last-day-of-summer-time', cairo, '2026-10-29', locality: 'cairo');
  vector.row('first-day-after-summer-time', cairo, '2026-10-30',
      locality: 'cairo');
  return vector;
}

_Vector _lateIsha() {
  const day = [150, 240, 780, 1080, 1370, 1450];
  final vector = _Vector('late-isha', {
    'authority': 'xx-north',
    'revision': 7,
    'part': 'all',
    'coverage': ['2026-01-01', '2026-12-31'],
    'columns': _core,
    'asrShadow': 2,
    'zones': [
      _zone('Europe/Oslo', [
        ['2026-01-01', 60]
      ])
    ],
    'localities': [
      _point('north', 'north', [59900000, 10750000], 30000,
          names: {'en': 'North'}),
    ],
    'rows': {
      'north': _days('2026-06-20', [
        day,
        [150, 240, 780, 1080, 1370, 1451],
        [150, 240, 780, 1080, 1371, 1452],
      ]),
    },
  });
  vector.row('isha-after-midnight', [59.91, 10.75], '2026-06-21',
      locality: 'north');
  return vector;
}

class _Malformed {
  final String file;
  final String stage;
  final String reason;
  final String content;

  _Malformed(this.file, this.stage, this.reason, this.content);
}

Map<String, dynamic> _baseHeader() => {
      'authority': 'xx-base',
      'revision': 1,
      'part': 'all',
      'coverage': ['2026-01-01', '2026-12-31'],
      'columns': _core,
      'asrShadow': 1,
      'zones': <Map<String, dynamic>>[
        {
          'id': 'Etc/UTC',
          'offsets': [
            ['2026-01-01', 0]
          ]
        }
      ],
      'localities': <Map<String, dynamic>>[
        {
          'id': 'L1',
          'group': 'g',
          'zone': 0,
          'names': <String, String>{},
          'ref': [10000000, 10000000],
          'point': {'radiusM': 10000},
        }
      ],
    };

const _baseRows = 'L1 2026-01-01 030006301220164018201950edeeded\n';

String _file(Object header, String rows, {String magic = 'OTT 1'}) =>
    '$magic\n${header is String ? header : jsonEncode(header)}\n$rows';

Map<String, dynamic> _header(void Function(Map<String, dynamic> header) edit) {
  final header = _baseHeader();
  edit(header);
  return header;
}

Map<String, dynamic> _locality(Map<String, dynamic> header) =>
    (header['localities'] as List).first as Map<String, dynamic>;

List<_Malformed> _malformed() {
  final decode = <_Malformed>[];
  void bad(String file, String reason, String content) =>
      decode.add(_Malformed(file, 'decode', reason, content));
  void badHeader(String file, String reason,
          void Function(Map<String, dynamic> header) edit) =>
      bad(file, reason, _file(_header(edit), _baseRows));
  void badRows(String file, String reason, String rows) =>
      bad(file, reason, _file(_baseHeader(), rows));

  bad('bad-magic.ott', 'line 1 is not OTT',
      _file(_baseHeader(), _baseRows, magic: 'OTX 1'));
  bad('major-2.ott', 'major version 2 is unknown',
      _file(_baseHeader(), _baseRows, magic: 'OTT 2'));
  bad('empty.ott', 'the file is empty', '');
  bad('header-not-json.ott', 'line 2 is not JSON',
      _file('{authority', _baseRows));
  bad('header-not-object.ott', 'line 2 is not a JSON object',
      _file('[]', _baseRows));
  badHeader('missing-revision.ott', 'revision is absent',
      (h) => h.remove('revision'));
  badHeader('revision-too-large.ott', 'revision is above 2147483647',
      (h) => h['revision'] = 2147483648);
  badHeader('revision-negative.ott', 'revision is negative',
      (h) => h['revision'] = -1);
  badHeader('coverage-reversed.ott', 'coverage ends before it starts',
      (h) => h['coverage'] = ['2026-12-31', '2026-01-01']);
  badHeader('missing-core-column.ott', 'columns lacks isha',
      (h) => h['columns'] = _core.sublist(0, 5));
  badHeader('unknown-column.ott', 'sunset is not a column name',
      (h) => h['columns'] = [..._core, 'sunset']);
  badHeader('duplicate-column.ott', 'fajr appears twice',
      (h) => h['columns'] = [..._core, 'fajr']);
  badHeader(
      'asr-shadow-3.ott', 'asrShadow is not 1 or 2', (h) => h['asrShadow'] = 3);
  badHeader('no-zones.ott', 'zones is empty', (h) => h['zones'] = []);
  badHeader(
      'offsets-unsorted.ott',
      'offset dates are not ascending',
      (h) => (h['zones'] as List).first['offsets'] = [
            ['2026-06-01', 60],
            ['2026-01-01', 0]
          ]);
  badHeader(
      'offsets-start-after-coverage.ott',
      'the first offset date is after coverage starts',
      (h) => (h['zones'] as List).first['offsets'] = [
            ['2026-02-01', 0]
          ]);
  badHeader(
      'offset-too-large.ott',
      'an offset is above 1440 minutes',
      (h) => (h['zones'] as List).first['offsets'] = [
            ['2026-01-01', 1500]
          ]);
  badHeader(
      'no-localities.ott', 'localities is empty', (h) => h['localities'] = []);
  badHeader('locality-bad-id.ott', 'a locality id has a space',
      (h) => _locality(h)['id'] = 'L 1');
  badHeader('locality-long-id.ott', 'a locality id has 33 characters',
      (h) => _locality(h)['id'] = 'L' * 33);
  badHeader('locality-duplicate-id.ott', 'two localities share an id',
      (h) => (h['localities'] as List).add(Map.of(_locality(h))));
  badHeader(
      'locality-unknown-zone.ott',
      'a locality names zone index 1 of 1 zone',
      (h) => _locality(h)['zone'] = 1);
  badHeader('locality-no-geometry.ott', 'a locality has neither point nor area',
      (h) => _locality(h).remove('point'));
  badHeader(
      'locality-both-geometries.ott',
      'a locality has both point and area',
      (h) => _locality(h)['area'] = {
            'polygons': [
              MalaysiaZoneMap.encodePolyline(
                  _square(9000000, 9000000, 11000000, 11000000))
            ],
            'toleranceM': 0
          });
  badHeader(
      'locality-ref-out-of-range.ott',
      'a reference latitude is above 90 degrees',
      (h) => _locality(h)['ref'] = [90000001, 10000000]);
  badHeader(
      'locality-ref-fraction.ott',
      'a reference coordinate is not an integer',
      (h) => _locality(h)['ref'] = [10.5, 10000000]);
  badHeader('locality-radius-zero.ott', 'a point radius is 0',
      (h) => _locality(h)['point'] = {'radiusM': 0});
  badHeader('locality-validity-reversed.ott', 'validTo is before validFrom',
      (h) {
    _locality(h)['validFrom'] = '2026-06-01';
    _locality(h)['validTo'] = '2026-01-01';
  });
  badHeader(
      'locality-unknown-successor.ott',
      'a successor id is not in the header',
      (h) => _locality(h)['successors'] = ['L9']);
  badHeader('area-two-vertices.ott', 'a ring has two vertices', (h) {
    _locality(h).remove('point');
    _locality(h)['area'] = {
      'polygons': [
        MalaysiaZoneMap.encodePolyline([9000000, 9000000, 11000000, 11000000])
      ],
      'toleranceM': 0
    };
  });
  badRows(
      'row-unknown-locality.ott',
      'a row names a locality not in the header',
      'L2 2026-01-01 030006301220164018201950edeeded\n');
  badRows('row-bad-date.ott', 'a row date is not a calendar day',
      'L1 2026-02-30 030006301220164018201950edeeded\n');
  badRows('row-before-coverage.ott', 'a row starts before coverage',
      'L1 2025-12-31 030006301220164018201950edeeded\n');
  badRows('row-after-coverage.ott', 'a row starts after coverage',
      'L1 2027-01-01 030006301220164018201950edeeded\n');
  badRows('row-two-fields.ott', 'a row has two fields',
      'L1 030006301220164018201950edeeded\n');
  badRows('row-short-first-day.ott', 'the first day has fewer than 24 digits',
      'L1 2026-01-01 0300063012201640\n');
  badRows('row-nondigit-first-day.ott', 'the first day has a letter',
      'L1 2026-01-01 0300063012201640182019x0\n');
  bad('crlf.ott', 'lines end with CR LF',
      _file(_baseHeader(), _baseRows).replaceAll('\n', '\r\n'));
  bad('no-final-newline.ott', 'the last line has no LF',
      _file(_baseHeader(), _baseRows.trimRight()));

  final validate = <_Malformed>[];
  void badCells(String file, String reason, String rows) => validate
      .add(_Malformed(file, 'validate', reason, _file(_baseHeader(), rows)));
  badCells('cell-minute-60.ott', 'a reset cell has minute 60',
      'L1 2026-01-01 030006301220164018201950~0560deeded\n');
  badCells('cell-hour-48.ott', 'a reset cell has hour 48',
      'L1 2026-01-01 030006301220164018201950ddddd~4800\n');
  badCells('cell-unknown-letter.ott', 'h is not a delta letter',
      'L1 2026-01-01 030006301220164018201950hdeeded\n');
  badCells('cell-truncated-day.ott', 'the second day has five cells',
      'L1 2026-01-01 030006301220164018201950edeed\n');
  badCells('cell-delta-below-zero.ott', 'a delta takes a column below 0',
      'L1 2026-01-01 000006301220164018201950adeeded\n');
  badCells('first-day-minute-60.ott', 'the first day has minute 60',
      'L1 2026-01-01 036006301220164018201950edeeded\n');
  badCells('core-order.ott', 'asr is before dhuhr',
      'L1 2026-01-01 030006301640122018201950edeeded\n');
  badCells('row-crosses-year.ott', 'a line starting 2026-12-30 has three days',
      'L1 2026-12-30 030006301220164018201950edeededededed\n');
  badCells('rows-overlap.ott', 'two lines of one locality share 2026-01-02',
      'L1 2026-01-01 030006301220164018201950edeeded\nL1 2026-01-02 030006301220164018201950edeeded\n');
  return [...decode, ...validate];
}

void _check(bool condition, String claim) {
  if (!condition) throw StateError('vector self-check failed: $claim');
}

int _haversineMm(double lat1, double lon1, double lat2, double lon2) {
  double radians(double degrees) => degrees * math.pi / 180;
  final phi1 = radians(lat1);
  final phi2 = radians(lat2);
  final dPhi = radians(lat2 - lat1);
  final dLambda = radians(lon2 - lon1);
  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
  final d = 2 * _earthRadius * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return (d * 1000).round();
}

int _edgeDistanceMm(double lat0, double lon0, List<int> ring) {
  const perDegreeLatitude = 110574.0;
  final perDegreeLongitude = 111320.0 * math.cos(lat0 * math.pi / 180);
  var best = double.infinity;
  final n = ring.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final y1 = (ring[2 * i] / 1e6 - lat0) * perDegreeLatitude;
    final x1 = (ring[2 * i + 1] / 1e6 - lon0) * perDegreeLongitude;
    final y2 = (ring[2 * j] / 1e6 - lat0) * perDegreeLatitude;
    final x2 = (ring[2 * j + 1] / 1e6 - lon0) * perDegreeLongitude;
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSquared = dx * dx + dy * dy;
    var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);
    final px = x1 + t * dx;
    final py = y1 + t * dy;
    best = math.min(best, math.sqrt(px * px + py * py));
  }
  return (best * 1000).round();
}

const _readme = '''
# Published timetable vectors

These files pin the `OTT 1` format that `docs/PUBLISHED_TIMETABLE_FORMAT.md` describes. Every decoder and encoder of the format, in any language, is checked against the same bytes. Do not edit them by hand. Regenerate them with:

```
dart run tool/published/vectors.dart
```

`test/published/vectors_test.dart` fails when the files on disk differ from what the generator writes.

## Layout

- `valid/<name>.ott` is a well-formed file. `valid/<name>.input.json` is the encoder input that produces it under the canonical encoding rules, so an encoder test is `encode(input) == ott`.
- `expected.json` lists lookup cases over the valid files. Each case names the vector, the coordinates, an optional manual `localityId`, the date, and the `result`: `row` with the `locality`, the `published` UTC instant per column and the assembled `asr` for both madhabs; `noRow` with the `locality`; or `noLocality`. Instants are `YYYY-MM-DDTHH:MM:SSZ`.
- `malformed/<name>.ott` is a file a decoder rejects. `malformed/index.json` names the stage that rejects each one: `decode` for `PublishedTimetable.decode`, `validate` for `validateAllRows()`.

## Cases

`kacst-like` carries ten real days of three Saudi capitals in 2026 and 2027, with automatic and manual lookups, a date inside coverage with no row, a date after coverage and an unknown manual id. `shapes` covers resolution: a tie between two points, nearest point, a point exactly on its radius and one metre beyond, a point inside an area, area tolerance, a hole, overlapping areas and a retired locality with a successor. `dst` is an Egypt-like zone whose offset changes twice in the year and carries `imsak` and `asrHanafi`. `late-isha` has Isha after midnight and a published Hanafi Asr.

The assembled `asr` in `expected.json` is `PrayerTimes.official` with the default `hourAngleCorrection` and no adjustments. The Hanafi shift uses the locality's reference point.
''';
