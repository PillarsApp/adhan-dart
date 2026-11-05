@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:adhan/src/data/date_components.dart';
import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:test/test.dart';

import '../tool/malaysia/src/geometry.dart';
import '../tool/malaysia/src/malaysia_zones.dart';
import 'malaysia_test_support.dart';

const _committedZones = 'data/malaysia/malaysia_zones.txt';
const _borderExtract =
    'tool/malaysia/raw/openstreetmap-MYS-border-features.tsv.gz';

String _zonesWithRegionArcs(int region, List<int> Function(List<int>) edit,
    {List<String> extraArcs = const []}) {
  final lines = committedZonesLines();
  final lastArc = lines.lastIndexWhere((line) => line.startsWith('A\t'));
  var r = -1;
  return writeZones([
    for (var i = 0; i < lines.length; i++)
      if (i == lastArc) ...[
        lines[i],
        ...extraArcs
      ] else if (lines[i].startsWith('R\t') && ++r == region)
        () {
          final fields = lines[i].split('\t');
          final arcs = edit(fields[1].split(' ').map(int.parse).toList());
          return [fields[0], arcs.join(' '), fields[2]].join('\t');
        }()
      else
        lines[i]
  ]);
}

List<List<int>> _arcs() => [
      for (final line in committedZonesLines())
        if (line.startsWith('A\t'))
          MalaysiaZoneMap.decodePolyline(line.substring(2))
    ];

String _shiftedFederalArc(double metres) {
  final map = MalaysiaZoneMap.parse(committedZonesLines().join('\n'));
  final date = DateComponents(2026, 6, 1);
  bool inCheras(int lat, int lon) =>
      lat >= 305000 && lat <= 307000 && lon >= 10174000 && lon <= 10176000;
  final arcs = _arcs();
  final federal = committedZonesLines()
      .where((line) => line.startsWith('R\t'))
      .elementAt(regionOf('WLY01'))
      .split('\t')[1]
      .split(' ')
      .map(int.parse);
  int inside(int a) => [
        for (var i = 0; i < arcs[a].length; i += 2)
          if (inCheras(arcs[a][i], arcs[a][i + 1])) i
      ].length;
  final chosen = federal.reduce((a, b) => inside(a) >= inside(b) ? a : b);
  final points = [...arcs[chosen]];
  for (var i = 2; i < points.length - 2; i += 2) {
    if (!inCheras(points[i], points[i + 1])) continue;
    final cosine = cos(points[i] / 100000 * pi / 180);
    final x = (arcs[chosen][i + 3] - arcs[chosen][i - 1]) * cosine;
    final y = (arcs[chosen][i + 2] - arcs[chosen][i - 2]).toDouble();
    final length = sqrt(x * x + y * y);
    List<double> at(double d) => [
          points[i] / 100000 + x / length * d / 110574,
          points[i + 1] / 100000 - y / length * d / (111320 * cosine),
        ];
    final probe = at(40);
    final side =
        map.zoneAt(probe[0], probe[1], date) == 'WLY01' ? metres : -metres;
    final moved = at(side);
    points[i] = MalaysiaZoneMap.quantize(moved[0]);
    points[i + 1] = MalaysiaZoneMap.quantize(moved[1]);
  }
  var a = -1;
  return writeZones([
    for (final line in committedZonesLines())
      line.startsWith('A\t') && ++a == chosen
          ? 'A\t${MalaysiaZoneMap.encodePolyline(points)}'
          : line
  ]);
}

void main() {
  group('check border features', () {
    test('fails when an arc moves 85 m into Kuala Lumpur at Cheras', () {
      final check = checkZones(Directory.current, File(_shiftedFederalArc(85)));

      expect(check.failed, isTrue);
      expect(
          check.lines,
          contains(allOf(startsWith('border feature'),
              contains('inside OpenStreetMap Kuala Lumpur'))));
    });
  });

  group('check land and places with no zone', () {
    test('fails on a hole in a region whose islands are named', () {
      final semporna = regionOf('SBH03');
      final hole = MalaysiaZoneMap.encodePolyline([
        for (final corner in const [
          [446000, 11856000],
          [446000, 11860000],
          [450000, 11860000],
          [450000, 11856000],
          [446000, 11856000],
        ])
          ...corner
      ]);
      final zones = _zonesWithRegionArcs(
          semporna, (arcs) => [...arcs, _arcs().length],
          extraArcs: ['A\t$hole']);

      final check = checkZones(Directory.current, File(zones));

      expect(check.failed, isTrue);
      expect(check.lines,
          contains(startsWith('no zone inside OpenStreetMap Sabah')));
    });

    test('fails on places with no zone that no_zone_areas.csv does not name',
        () {
      final arcs = _arcs();
      final mabul = [
        for (var a = 0; a < arcs.length; a++)
          if (arcs[a].length <= 20 && ringContains(arcs[a], 424621, 11863059)) a
      ].single;
      final zones = _zonesWithRegionArcs(regionOf('SBH03'),
          (regionArcs) => regionArcs.where((a) => a != mabul).toList());

      final check = checkZones(Directory.current, File(zones));

      expect(check.failed, isTrue);
      expect(check.lines, contains(contains('not named in no_zone_areas.csv')));
    });
  });

  group('check inputs', () {
    ZoneCheck checkCopy(void Function(String tool) damage,
        {String zones = _committedZones}) {
      final root = copyOfTool();
      damage('${root.path}/tool/malaysia');
      return checkZones(root, File(zones));
    }

    test('names a zones file that is missing', () {
      final check = checkCopy((_) {}, zones: 'no/such/zones.txt');

      expect(check.failed, isTrue);
      expect(check.lines.single,
          allOf(contains('no/such/zones.txt'), contains('cannot be read')));
    });

    test('names a zones file that is cut short', () {
      final cut = writeZones(
          [File(_committedZones).readAsStringSync().substring(0, 5000)]);

      final check = checkCopy((_) {}, zones: cut);

      expect(check.failed, isTrue);
      expect(check.lines.single,
          allOf(contains(cut), contains('is not a zones file')));
    });

    test('names no_zone_areas.csv when it is missing or has no osm_ids', () {
      final missing =
          checkCopy((tool) => File('$tool/no_zone_areas.csv').deleteSync());
      final boxes = checkCopy((tool) => File('$tool/no_zone_areas.csv')
          .writeAsStringSync('name,territory,min_lat,max_lat,reason\n'));

      expect(missing.failed, isTrue);
      expect(missing.lines.single,
          allOf(contains('no_zone_areas.csv'), contains('cannot be read')));
      expect(boxes.failed, isTrue);
      expect(boxes.lines.single,
          allOf(contains('no_zone_areas.csv'), contains('osm_ids')));
    });

    test('names an extract that is missing or not the pinned one', () {
      final missing = checkCopy((tool) =>
          File('$tool/raw/${_borderExtract.split('/').last}').deleteSync());
      final edited = checkCopy((tool) {
        final file = File('$tool/raw/${_borderExtract.split('/').last}');
        final lines = const LineSplitter()
            .convert(utf8.decode(GZipCodec().decode(file.readAsBytesSync())));
        file.writeAsBytesSync(GZipCodec().encode(
            utf8.encode('${lines.take(lines.length - 1).join('\n')}\n')));
      });

      expect(missing.failed, isTrue);
      expect(missing.lines.single,
          allOf(contains('border-features'), contains('cannot be read')));
      expect(edited.failed, isTrue);
      expect(edited.lines.single,
          allOf(contains('border-features'), contains('not the pinned')));
    });

    test('names state_line_exceptions.csv when a point is not a number', () {
      final check = checkCopy((tool) {
        final file = File('$tool/state_line_exceptions.csv');
        file.writeAsStringSync(file
            .readAsStringSync()
            .replaceFirst('3.12096 101.64422', '3.12096 1O1.64422'));
      });

      expect(check.failed, isTrue);
      expect(
          check.lines.single,
          allOf(contains('state_line_exceptions.csv Jalan 16/2'),
              contains('bad point')));
    });
  });
}
