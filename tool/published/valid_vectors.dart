import 'dart:math' as math;

import 'package:adhan/adhan.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:adhan/src/internal/shadow_length.dart';
import 'package:adhan/src/internal/solar_time.dart';

const core = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

const _earthRadius = 6371008.8;

List<Vector> validVectors() => [
      kacstLike(),
      shapes(),
      dst(),
      lateIsha(),
      twoZones(),
      edgeValues(),
      canon()
    ];

class Vector {
  final String name;
  final Map<String, dynamic> input;
  final List<Map<String, dynamic>> cases = [];

  Vector(this.name, this.input);

  List<String> get columns => (input['columns'] as List).cast<String>();

  int get asrShadow => input['asrShadow'] as int;

  Map _locality(String id) => (input['localities'] as List)
      .cast<Map>()
      .singleWhere((l) => l['id'] == id);

  int _offsetOn(String localityId, String date) {
    final zone = (input['zones'] as List)[_locality(localityId)['zone'] as int];
    final offsets = (zone['offsets'] as List).cast<List>().toList()
      ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
    var offset = 0;
    for (final entry in offsets) {
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
              60 +
          0.5)
      .floor();
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

Map<String, List<int>> _calculatedDays(
    List<int> ref, String first, int offset) {
  final parameters = CalculationMethod.umm_al_qura.getParameters();
  final point = Coordinates(ref[0] / 1e6, ref[1] / 1e6);
  final start = DateTime.parse('${first}T00:00:00Z');
  final days = <String, List<int>>{};
  for (var i = 0; i < 10; i++) {
    final midnight = start.add(Duration(days: i));
    final times = PrayerTimes.utc(
        point,
        DateComponents(midnight.year, midnight.month, midnight.day),
        parameters);
    int wall(DateTime instant) =>
        instant.difference(midnight).inMinutes + offset;
    days[_date(midnight)] = [
      wall(times.fajr),
      wall(times.sunrise),
      wall(times.dhuhr),
      wall(times.asr),
      wall(times.maghrib),
      wall(times.isha)
    ];
  }
  return days;
}

Vector kacstLike() {
  const riyadhRef = [24670000, 46690000];
  const meccaRef = [21426666, 39831666];
  const medinaRef = [24540000, 39630000];
  final vector = Vector('kacst-like', {
    'authority': 'sa-umm-al-qura',
    'revision': 12,
    'part': 'all',
    'coverage': ['2026-01-01', '2027-12-31'],
    'columns': core,
    'asrShadow': 1,
    'zones': [
      _zone('Asia/Riyadh', [
        ['2026-01-01', 180]
      ])
    ],
    'localities': [
      _point('1001', '1001', riyadhRef, 25000,
          names: {'ar': 'الرياض', 'en': 'Riyadh', 'ur': 'ریاض'}),
      _point('1002', '1002', meccaRef, 25000,
          names: {'ar': 'مكة المكرمة', 'en': 'Mecca', 'ur': 'مکہ مکرمہ'}),
      _point('1003', '1003', medinaRef, 25000, names: {
        'ar': 'المدينة المنورة',
        'en': 'Medina',
        'ur': 'مدینہ منورہ'
      }),
    ],
    'rows': {
      '1001': {
        ..._calculatedDays(riyadhRef, '2026-01-01', 180),
        ..._calculatedDays(riyadhRef, '2027-01-01', 180)
      },
      '1002': {
        ..._calculatedDays(meccaRef, '2026-01-01', 180),
        ..._calculatedDays(meccaRef, '2027-01-01', 180)
      },
      '1003': {
        ..._calculatedDays(medinaRef, '2026-01-01', 180),
        ..._calculatedDays(medinaRef, '2027-01-01', 180)
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

Vector shapes() {
  const base = [300, 380, 740, 1000, 1100, 1190];
  List<List<int>> three() => [
        for (var i = 0; i < 3; i++) [for (final m in base) m + i]
      ];
  final ringLatitude = 20 + 25000 / _earthRadius * 180 / math.pi;
  final vector = Vector('shapes', {
    'authority': 'xx-shapes',
    'revision': 1,
    'part': 'all',
    'coverage': ['2026-01-01', '2027-12-31'],
    'columns': core,
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
  check(
      _haversineMm(25.0, 46.5, 25.0, 47.0) ==
          _haversineMm(25.0, 46.5, 25.0, 46.0),
      'the tie case is equidistant');
  vector.row('tie-breaks-to-the-first-id', [25.0, 46.5], day,
      locality: 'p-east');
  vector.row('nearest-point-wins-east', [25.0, 46.9], day, locality: 'p-east');
  vector.row('nearest-point-wins-west', [25.0, 46.1], day, locality: 'p-west');
  final toWest = _haversineMm(25.0, 46.45, 25.0, 46.0);
  final toEast = _haversineMm(25.0, 46.45, 25.0, 47.0);
  check(toWest < toEast && toEast <= 60000 * 1000,
      'both points cover the nearest-over-lower-id case and p-west is nearer');
  vector.row('nearest-wins-over-the-lower-id', [25.0, 46.45], day,
      locality: 'p-west');
  check(_haversineMm(ringLatitude, 50.0, 20.0, 50.0) == 25000 * 1000,
      'the radius case sits exactly on the radius in millimetres');
  vector.row('point-exactly-at-radius', [ringLatitude, 50.0], day,
      locality: 'ring');
  final beyond = 20 + 25001 / _earthRadius * 180 / math.pi;
  check(_haversineMm(beyond, 50.0, 20.0, 50.0) > 25000 * 1000,
      'the beyond case lies outside the radius');
  vector.noLocality('point-one-metre-beyond-radius', [beyond, 50.0], day);
  vector.row('point-inside-area-wins', [23.5, 44.5], day, locality: 'inner');
  vector.row('area-outside-the-point-radius', [23.9, 44.9], day,
      locality: 'box');
  check(
      _edgeDistanceMm(
              24.005, 44.5, _square(23000000, 44000000, 24000000, 45000000)) <=
          1000 * 1000,
      'the tolerance case is within 1000 m of the box');
  vector.row('area-within-tolerance', [24.005, 44.5], day, locality: 'box');
  check(
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

Vector dst() {
  const april = [230, 240, 330, 715, 930, 990, 1100, 1180];
  const october = [240, 250, 350, 700, 900, 960, 1050, 1130];
  List<int> plus(List<int> day, int minutes) =>
      [for (final m in day) m + minutes];
  final vector = Vector('dst', {
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

Vector lateIsha() {
  const day = [150, 240, 780, 1080, 1370, 1450];
  final vector = Vector('late-isha', {
    'authority': 'xx-north',
    'revision': 7,
    'part': 'all',
    'coverage': ['2026-01-01', '2026-12-31'],
    'columns': core,
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

Vector twoZones() {
  const istanbul = [360, 450, 790, 970, 1120, 1210];
  const dubai = [340, 420, 740, 920, 1060, 1150];
  final vector = Vector('two-zones', {
    'authority': 'xx-zones',
    'revision': 2,
    'part': 'all',
    'coverage': ['2026-01-01', '2026-12-31'],
    'columns': core,
    'asrShadow': 1,
    'zones': [
      _zone('Europe/Istanbul', [
        ['2026-01-01', 180]
      ]),
      _zone('Asia/Dubai', [
        ['2026-01-01', 240]
      ]),
    ],
    'localities': [
      {
        ..._point('ist', 'tr', [41015100, 28979500], 30000,
            names: {'en': 'Istanbul'}),
        'zone': 0
      },
      {
        ..._point('dxb', 'ae', [25204800, 55270800], 30000,
            names: {'en': 'Dubai'}),
        'zone': 1
      },
    ],
    'rows': {
      'ist': _days('2026-02-01', [istanbul, istanbul, istanbul]),
      'dxb': _days('2026-02-01', [dubai, dubai, dubai]),
    },
  });
  vector.row(
      'istanbul-keeps-its-zone-after-sorting', [41.0082, 28.9784], '2026-02-02',
      locality: 'ist');
  vector.row(
      'dubai-keeps-its-zone-after-sorting', [25.2048, 55.2708], '2026-02-02',
      locality: 'dxb');
  return vector;
}

Vector edgeValues() {
  const march = [330, 420, 790, 1000, 1150, 1230];
  const april = [320, 405, 850, 1070, 1220, 1300];
  List<int> plus(List<int> day, int minutes) =>
      [for (final m in day) m + minutes];
  const westA = [37730000, -25690000];
  const westB = [37750000, -25670000];
  const oldWest = [37740000, -25680000];
  final vector = Vector('edge-values', {
    'authority': 'xx-edge',
    'revision': 0,
    'part': 'west',
    'coverage': ['2026-01-01', '2026-12-31'],
    'columns': core,
    'asrShadow': 1,
    'zones': [
      _zone('Atlantic/Azores', [
        ['2026-10-25', -60],
        ['2026-01-01', -60],
        ['2026-03-29', 0],
      ])
    ],
    'localities': [
      _point('west_b', 'Açores', westB, 15000,
          names: {'pt': 'Ponta "Oeste"\tB', 'en': 'West B\u001b\\'},
          validFrom: '2026-04-01'),
      _point('old-west', 'Açores', oldWest, 30000,
          validTo: '2026-03-31', successors: ['west_b', 'west.a']),
      _point('west.a', 'Açores', westA, 15000,
          names: {'en': 'West A'}, validFrom: '2026-04-01'),
    ],
    'rows': {
      'west.a': _days('2026-04-01', [april, plus(april, 1), plus(april, 2)]),
      'old-west': _days('2026-03-27',
          [march, plus(march, 1), plus(march, 62), plus(march, 63)]),
      'west_b': _days('2026-04-01', [april, plus(april, 1), plus(april, 3)]),
    },
  });
  final here = [37.74, -25.68];
  vector.row('winter-offset-is-negative', here, '2026-03-28',
      locality: 'old-west');
  vector.row('first-day-of-summer-time-azores', here, '2026-03-29',
      locality: 'old-west');
  vector.row('before-retirement-the-successors-are-not-in-force',
      [37.75, -25.67], '2026-03-28',
      locality: 'old-west');
  check(
      _haversineMm(37.73, -25.69, westA[0] / 1e6, westA[1] / 1e6) <
              _haversineMm(37.73, -25.69, westB[0] / 1e6, westB[1] / 1e6) &&
          _haversineMm(37.73, -25.69, westB[0] / 1e6, westB[1] / 1e6) <=
              15000 * 1000,
      'both successors cover the west.a case and west.a is nearer');
  vector.row('nearer-successor-west-a', [37.73, -25.69], '2026-04-02',
      locality: 'west.a');
  vector.row('nearer-successor-west-b', [37.75, -25.67], '2026-04-02',
      locality: 'west_b');
  check(
      _haversineMm(37.9, -25.68, westB[0] / 1e6, westB[1] / 1e6) > 15000 * 1000,
      'the far case lies outside both successor radii');
  vector.noLocality(
      'retired-locality-does-not-resolve', [37.9, -25.68], '2026-04-02');
  vector.noRow('manual-retired-locality-after-its-rows', here, '2026-04-02',
      localityId: 'old-west', locality: 'old-west');
  return vector;
}

Vector canon() {
  const day1 = [300, 390, 740, 1000, 1100, 1190];
  const day2 = [297, 388, 739, 1000, 1101, 1192];
  const day3 = [300, 392, 735, 1000, 1101, 1192];
  const day4 = [301, 393, 736, 1001, 1102, 1193];
  const day5 = [298, 391, 735, 1001, 1105, 1190];
  const day6 = [302, 397, 731, 1004, 1105, 1190];
  final outer = _square(50000000, 50000000, 52000000, 52000000);
  final hole = _square(50800000, 50800000, 51200000, 51200000);
  final ringsInSortedOrder = [outer, hole]..sort((a, b) =>
      MalaysiaZoneMap.encodePolyline(a)
          .compareTo(MalaysiaZoneMap.encodePolyline(b)));
  final rings = ringsInSortedOrder.reversed.toList();
  final vector = Vector('canon', {
    'authority': 'xx-canon',
    'revision': 5,
    'part': 'all',
    'coverage': ['2026-01-01', '2027-12-31'],
    'columns': core,
    'asrShadow': 1,
    'zones': [
      _zone('Etc/UTC', [
        ['2026-01-01', 0]
      ])
    ],
    'localities': [
      _area('rings', 'g', [50500000, 50500000], rings, 0),
      _point('split', 'g', [20000000, 30000000], 10000,
          names: {
            '\uFF58': 'Fullwidth',
            'en': 'Split',
            '\u{1D54F}': 'Astral',
            'del': '\u007f',
            'ctl': '\b\f',
          },
          validFrom: '2026-01-01',
          validTo: '2027-12-31'),
    ],
    'rows': {
      'split': _days('2026-12-29', [day1, day2, day3, day4, day5, day6]),
      'rings': _days('2026-12-29', [day1, day2]),
    },
  });
  const here = [20.0, 30.0];
  vector.row('first-day-of-the-first-line', here, '2026-12-29',
      locality: 'split');
  vector.row('letters-a-to-f', here, '2026-12-30', locality: 'split');
  vector.row('letter-g-and-resets-beyond-the-window', here, '2026-12-31',
      locality: 'split');
  vector.row('first-day-of-the-second-line', here, '2027-01-01',
      locality: 'split');
  vector.row('letters-a-b-c-and-g-again', here, '2027-01-02',
      locality: 'split');
  vector.row('resets-of-plus-four-plus-six-minus-four', here, '2027-01-03',
      locality: 'split');
  vector.row('inside-the-outer-ring-listed-second', [50.5, 50.5], '2026-12-30',
      locality: 'rings');
  vector.noLocality('inside-the-hole-listed-first', [51.0, 51.0], '2026-12-30');
  return vector;
}

void check(bool condition, String claim) {
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
