import 'dart:convert';

import 'package:adhan/src/data/delta_cells_codec.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';

import 'valid_vectors.dart' show core;

class Malformed {
  final String file;
  final String stage;
  final String rule;
  final String mutation;
  final List<int> bytes;

  Malformed(this.file, this.stage, this.rule, this.mutation, this.bytes);
}

const _baseDays = [
  [300, 390, 740, 1000, 1100, 1190],
  [301, 390, 741, 1001, 1100, 1191],
];

List<int> _square(int south, int west, int north, int east) =>
    [south, west, north, west, north, east, south, east];

final String _farSquare = MalaysiaZoneMap.encodePolyline(
    _square(40000000, 40000000, 41000000, 41000000));

Map<String, dynamic> _baseHeader() => {
      'authority': 'xx-base',
      'revision': 1,
      'part': 'all',
      'coverage': ['2026-01-01', '2027-12-31'],
      'columns': core,
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
          'names': {'en': 'Base'},
          'ref': [10000000, 10000000],
          'point': {'radiusM': 10000},
          'validFrom': '2026-01-01',
        },
        {
          'id': 'L2',
          'group': 'g',
          'zone': 0,
          'names': <String, String>{},
          'ref': [40500000, 40500000],
          'area': {
            'polygons': [_farSquare],
            'toleranceM': 0
          },
        },
      ],
    };

String _rowLine(
        {String date = '2026-01-01',
        List<List<int>> days = _baseDays,
        int columns = 6}) =>
    'L1 $date ${encodeCells(days, columns)}\n';

final String _firstDay = encodeCells([_baseDays.first], 6);

List<int> _file(Object header, String rows, {String magic = 'OTT 1'}) => utf8
    .encode('$magic\n${header is String ? header : jsonEncode(header)}\n$rows');

const String _sentinel = '\uFFFF';

List<int> _withRawByte(List<int> bytes, int byte) {
  final sentinel = utf8.encode(_sentinel);
  for (var i = 0; i + sentinel.length <= bytes.length; i++) {
    if (bytes[i] == sentinel[0] &&
        bytes[i + 1] == sentinel[1] &&
        bytes[i + 2] == sentinel[2]) {
      return [...bytes.sublist(0, i), byte, ...bytes.sublist(i + 3)];
    }
  }
  throw StateError('the sentinel is absent');
}

const List<int> _triangle = [
  40000000,
  40000000,
  41000000,
  40000000,
  41000000,
  41000000
];

Map<String, dynamic> _header(void Function(Map<String, dynamic> header) edit) {
  final header = _baseHeader();
  edit(header);
  return header;
}

Map<String, dynamic> _point(Map<String, dynamic> header) =>
    (header['localities'] as List).first as Map<String, dynamic>;

Map<String, dynamic> _area(Map<String, dynamic> header) =>
    (header['localities'] as List).last as Map<String, dynamic>;

Map<String, dynamic> _zone(Map<String, dynamic> header) =>
    (header['zones'] as List).first as Map<String, dynamic>;

List<Malformed> malformedVectors() {
  final out = <Malformed>[];
  void decode(String file, String rule, String mutation, List<int> bytes) =>
      out.add(Malformed(file, 'decode', rule, mutation, bytes));
  void header(String file, String rule, String mutation,
          void Function(Map<String, dynamic> header) edit) =>
      decode(file, rule, mutation, _file(_header(edit), _rowLine()));
  void rows(String file, String rule, String mutation, String rows) =>
      decode(file, rule, mutation, _file(_baseHeader(), rows));
  void validate(String file, String rule, String mutation, String cells) =>
      out.add(Malformed(file, 'validate', rule, mutation,
          _file(_baseHeader(), 'L1 2026-01-01 $cells\n')));

  decode('bad-magic.ott', 'file.magic', 'line 1 is OTX 1',
      _file(_baseHeader(), _rowLine(), magic: 'OTX 1'));
  decode('major-2.ott', 'file.magic', 'line 1 is OTT 2',
      _file(_baseHeader(), _rowLine(), magic: 'OTT 2'));
  decode('empty.ott', 'file.empty', 'the file has no bytes', []);
  decode(
      'no-final-newline.ott',
      'file.lastLineNoLF',
      'the last row line has no LF',
      _file(_baseHeader(), _rowLine().trimRight()));
  decode('crlf.ott', 'file.cr', 'every line ends with CR LF', [
    for (final byte in _file(_baseHeader(), _rowLine()))
      if (byte == 0x0A) ...[0x0D, 0x0A] else byte
  ]);
  decode('header-absent.ott', 'file.headerAbsent', 'the file is line 1 only',
      utf8.encode('OTT 1\n'));
  decode('header-not-json.ott', 'header.json', 'line 2 is {authority',
      _file('{authority', _rowLine()));
  decode('header-not-object.ott', 'header.json', 'line 2 is an array',
      _file('[]', _rowLine()));
  decode(
      'header-not-utf8.ott',
      'header.json',
      'the name en of L1 is the byte 0xFF',
      _withRawByte(
          _file(_header((h) => _point(h)['names'] = {'en': _sentinel}),
              _rowLine()),
          0xFF));
  decode(
      'header-duplicate-key.ott',
      'header.duplicateKey',
      'the names of L1 carry the key en twice',
      _file(
          jsonEncode(_baseHeader()).replaceFirst(
              '"names":{"en":"Base"}', '"names":{"en":"Base","en":"Base"}'),
          _rowLine()));
  header('missing-revision.ott', 'header.keyAbsent', 'revision is absent',
      (h) => h.remove('revision'));
  header('authority-empty.ott', 'header.authority', 'authority is ""',
      (h) => h['authority'] = '');
  header('authority-whitespace.ott', 'header.authority',
      'authority is "xx base"', (h) => h['authority'] = 'xx base');
  header('revision-too-large.ott', 'header.revision', 'revision is 2147483648',
      (h) => h['revision'] = 2147483648);
  header('revision-negative.ott', 'header.revision', 'revision is -1',
      (h) => h['revision'] = -1);
  header('part-empty.ott', 'header.part', 'part is ""', (h) => h['part'] = '');
  header(
      'coverage-three-dates.ott',
      'header.coverage',
      'coverage has three dates',
      (h) => h['coverage'] = ['2026-01-01', '2026-06-01', '2027-12-31']);
  header(
      'coverage-date-format.ott',
      'header.coverage',
      'coverage starts 2026/01/01',
      (h) => h['coverage'] = ['2026/01/01', '2027-12-31']);
  header(
      'coverage-reversed.ott',
      'header.coverage.order',
      'coverage ends before it starts',
      (h) => h['coverage'] = ['2027-12-31', '2026-01-01']);
  header('asr-shadow-3.ott', 'header.asrShadow', 'asrShadow is 3',
      (h) => h['asrShadow'] = 3);
  decode(
      'unknown-column.ott',
      'column.unknown',
      'a seventh column sunset with minute 1100 on every day',
      _file(
          _header((h) => h['columns'] = [...core, 'sunset']),
          _rowLine(days: [
            for (final day in _baseDays) [...day, 1100]
          ], columns: 7)));
  decode(
      'duplicate-column.ott',
      'column.duplicate',
      'a seventh column fajr with minute 300 on every day',
      _file(
          _header((h) => h['columns'] = [...core, 'fajr']),
          _rowLine(days: [
            for (final day in _baseDays) [...day, 300]
          ], columns: 7)));
  decode(
      'missing-core-column.ott',
      'column.missingCore',
      'isha is absent from columns and from every day',
      _file(
          _header((h) => h['columns'] = core.sublist(0, 5)),
          _rowLine(
              days: [for (final day in _baseDays) day.sublist(0, 5)],
              columns: 5)));
  header('no-zones.ott', 'zones.empty', 'zones is []', (h) => h['zones'] = []);
  header('zone-id-empty.ott', 'zone.id', 'the zone id is ""',
      (h) => _zone(h)['id'] = '');
  header(
      'zone-id-duplicate.ott',
      'zone.id.duplicate',
      'a second zone with the id Etc/UTC',
      (h) => (h['zones'] as List).add(Map.of(_zone(h))));
  header('offsets-empty.ott', 'zone.offsets.empty', 'offsets is []',
      (h) => _zone(h)['offsets'] = []);
  header(
      'offset-triple.ott',
      'zone.offset.shape',
      'the offset is [date, minutes, 0]',
      (h) => _zone(h)['offsets'] = [
            ['2026-01-01', 0, 0]
          ]);
  header(
      'offset-date-format.ott',
      'zone.offset.date',
      'the offset date is 2026-1-1',
      (h) => _zone(h)['offsets'] = [
            ['2026-1-1', 0]
          ]);
  header(
      'offsets-unsorted.ott',
      'zone.offset.order',
      'offsets are dated 01-01, 06-01, 03-01',
      (h) => _zone(h)['offsets'] = [
            ['2026-01-01', 0],
            ['2026-06-01', 60],
            ['2026-03-01', 30]
          ]);
  header(
      'offset-too-large.ott',
      'zone.offset.range',
      'the offset is 1500',
      (h) => _zone(h)['offsets'] = [
            ['2026-01-01', 1500]
          ]);
  header(
      'offsets-start-after-coverage.ott',
      'zone.offset.start',
      'the first offset is dated 2026-02-01',
      (h) => _zone(h)['offsets'] = [
            ['2026-02-01', 0]
          ]);
  decode(
      'no-localities.ott',
      'localities.empty',
      'localities is [] and the file has no rows',
      _file(_header((h) => h['localities'] = []), ''));
  decode(
      'locality-bad-id.ott',
      'locality.id',
      'the id of L1 is "L 1"',
      _file(_header((h) => _point(h)['id'] = 'L 1'),
          _rowLine().replaceFirst('L1 ', 'L 1 ')));
  decode(
      'locality-long-id.ott',
      'locality.id',
      'the id of L1 is 33 letters',
      _file(_header((h) => _point(h)['id'] = 'L' * 33),
          _rowLine().replaceFirst('L1 ', '${'L' * 33} ')));
  header('locality-duplicate-id.ott', 'locality.id.duplicate',
      'the id of L2 is L1', (h) => _area(h)['id'] = 'L1');
  header('locality-group-empty.ott', 'locality.group', 'the group of L1 is ""',
      (h) => _point(h)['group'] = '');
  header('locality-unknown-zone.ott', 'locality.zone',
      'L1 names zone 1 of one zone', (h) => _point(h)['zone'] = 1);
  header('locality-name-not-string.ott', 'locality.names',
      'the name en of L1 is 7', (h) => _point(h)['names'] = {'en': 7});
  header(
      'locality-ref-three-values.ott',
      'locality.ref.shape',
      'the ref of L1 has three values',
      (h) => _point(h)['ref'] = [10000000, 10000000, 0]);
  header(
      'locality-ref-fraction.ott',
      'locality.ref.integer',
      'the ref latitude of L1 is 10.5',
      (h) => _point(h)['ref'] = [10.5, 10000000]);
  header(
      'locality-ref-out-of-range.ott',
      'locality.ref.range',
      'the ref latitude of L1 is 90000001',
      (h) => _point(h)['ref'] = [90000001, 10000000]);
  header(
      'locality-validity-date.ott',
      'locality.validity.date',
      'validFrom of L1 is 2026-02-30',
      (h) => _point(h)['validFrom'] = '2026-02-30');
  header(
      'locality-validity-reversed.ott',
      'locality.validity.order',
      'validTo of L1 is 2025-12-31, before its validFrom',
      (h) => _point(h)['validTo'] = '2025-12-31');
  header('locality-unknown-successor.ott', 'locality.successor',
      'L1 names the successor L9', (h) => _point(h)['successors'] = ['L9']);
  header('locality-no-geometry.ott', 'locality.geometry', 'L1 has no point',
      (h) => _point(h).remove('point'));
  header(
      'locality-both-geometries.ott',
      'locality.geometry',
      'L1 has an area as well as its point',
      (h) => _point(h)['area'] = {
            'polygons': [_farSquare],
            'toleranceM': 0
          });
  header('locality-radius-zero.ott', 'locality.point.radius',
      'the radius of L1 is 0', (h) => _point(h)['point'] = {'radiusM': 0});
  header(
      'area-no-polygons.ott',
      'locality.area.polygons',
      'the polygons of L2 are []',
      (h) => (_area(h)['area'] as Map)['polygons'] = []);
  header(
      'area-tolerance-negative.ott',
      'locality.area.tolerance',
      'the tolerance of L2 is -1',
      (h) => (_area(h)['area'] as Map)['toleranceM'] = -1);
  header(
      'area-polyline-bad-bytes.ott',
      'locality.area.polyline',
      'the polygon of L2 is "not a polyline!"',
      (h) => (_area(h)['area'] as Map)['polygons'] = ['not a polyline!']);
  header('area-polyline-truncated.ott', 'locality.area.polyline',
      'the polygon of L2 lacks its last byte', (h) {
    final polyline = MalaysiaZoneMap.encodePolyline(_triangle);
    (_area(h)['area'] as Map)['polygons'] = [
      polyline.substring(0, polyline.length - 1)
    ];
  });
  header(
      'area-two-vertices.ott',
      'locality.area.ring',
      'the polygon of L2 has two vertices',
      (h) => (_area(h)['area'] as Map)['polygons'] = [
            MalaysiaZoneMap.encodePolyline(
                [40000000, 40000000, 41000000, 41000000])
          ]);
  header(
      'area-vertex-out-of-range.ott',
      'locality.area.vertex',
      'a vertex of L2 is at latitude 91',
      (h) => (_area(h)['area'] as Map)['polygons'] = [
            MalaysiaZoneMap.encodePolyline(
                _square(89000000, 40000000, 91000000, 41000000))
          ]);
  rows('row-two-fields.ott', 'row.fields', 'the row line has no date',
      'L1 ${encodeCells(_baseDays, 6)}\n');
  rows('row-four-fields.ott', 'row.fields', 'the row line ends with " x"',
      '${_rowLine().trimRight()} x\n');
  rows('row-unknown-locality.ott', 'row.locality', 'the row names L9',
      _rowLine().replaceFirst('L1 ', 'L9 '));
  rows('row-bad-date.ott', 'row.date', 'the row starts 2026-02-30',
      _rowLine(date: '2026-02-30'));
  rows('row-before-coverage.ott', 'row.coverage', 'the row starts 2025-12-31',
      _rowLine(date: '2025-12-31'));
  rows('row-after-coverage.ott', 'row.coverage', 'the row starts 2028-01-01',
      _rowLine(date: '2028-01-01'));
  rows(
      'row-short-first-day.ott',
      'row.firstDay.length',
      'the first day has 16 digits',
      'L1 2026-01-01 ${_firstDay.substring(0, 16)}\n');
  rows(
      'row-nondigit-first-day.ott',
      'row.firstDay.digits',
      'the first day ends in x0',
      'L1 2026-01-01 ${_firstDay.substring(0, 22)}x0\n');

  validate('cell-reset-truncated.ott', 'cell.truncatedTime',
      'the last cell is ~05', '${_firstDay}edeed~05');
  validate('cell-reset-plus.ott', 'cell.digits', 'the first cell is ~+500',
      '$_firstDay~+500deede');
  validate('cell-reset-minus.ott', 'cell.digits', 'the first cell is ~-030',
      '$_firstDay~-030deede');
  validate('cell-reset-tab.ott', 'cell.digits', 'the first cell is ~<TAB>500',
      '$_firstDay~\t500deede');
  validate('cell-reset-vertical-tab.ott', 'cell.digits',
      'the first cell is ~<VT>500', '$_firstDay~\x0B500deede');
  out.add(Malformed(
      'cell-reset-nbsp.ott',
      'validate',
      'cell.digits',
      'the first cell is ~<0xA0>500',
      _withRawByte(
          _file(
              _baseHeader(), 'L1 2026-01-01 $_firstDay~${_sentinel}500deede\n'),
          0xA0)));
  validate('cell-minute-60.ott', 'cell.minute', 'the first cell is ~0560',
      '$_firstDay~0560deede');
  validate('first-day-minute-60.ott', 'cell.minute',
      'the first day starts 0560', '0560${_firstDay.substring(4)}edeede');
  validate('cell-hour-48.ott', 'cell.hour', 'the last cell is ~4800',
      '${_firstDay}ddddd~4800');
  validate('cell-unknown-letter.ott', 'cell.letter', 'the first cell is h',
      '${_firstDay}hdeede');
  validate(
      'cell-delta-below-zero.ott',
      'cell.delta',
      'the first day starts 0000 and the first cell is a',
      '0000${_firstDay.substring(4)}adeede');
  validate('cell-truncated-day.ott', 'cell.truncatedDay',
      'the second day has five cells', '${_firstDay}edeed');
  validate(
      'core-order.ott',
      'row.coreOrder',
      'asr is before dhuhr',
      encodeCells([
        [300, 390, 1000, 740, 1100, 1190]
      ], 6));
  validate(
      'core-equal.ott',
      'row.coreOrder',
      'asr equals dhuhr',
      encodeCells([
        [300, 390, 740, 740, 1100, 1190]
      ], 6));
  out.add(Malformed(
      'row-crosses-year.ott',
      'validate',
      'row.crossesYear',
      'the row starts 2026-12-31 and has two days',
      _file(_baseHeader(), _rowLine(date: '2026-12-31'))));
  out.add(Malformed(
      'row-ends-after-coverage.ott',
      'validate',
      'row.endsAfterCoverage',
      'coverage ends 2026-01-01 and the row has two days',
      _file(_header((h) => h['coverage'] = ['2026-01-01', '2026-01-01']),
          _rowLine())));
  out.add(Malformed(
      'rows-overlap.ott',
      'validate',
      'row.overlap',
      'a second row of L1 starts 2026-01-02',
      _file(_baseHeader(), '${_rowLine()}${_rowLine(date: '2026-01-02')}')));
  return out;
}
