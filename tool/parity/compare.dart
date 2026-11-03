import 'dart:io';

import 'package:adhan/adhan.dart';

import 'grid.dart';

void main(List<String> arguments) {
  var referenceDir = 'tool/parity/reference';
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--reference-dir' && i + 1 < arguments.length) {
      referenceDir = arguments[++i];
    } else {
      stderr.writeln('usage: compare.dart [--reference-dir <dir>]');
      exit(2);
    }
  }

  stdout.writeln(
      'singapore_mid runs with Rounding.up on this side, the rounding the '
      'adhan-swift Singapore method uses by default and this library does not.');
  var defects = 0;
  for (final correction in HourAngleCorrection.values) {
    for (final polar in [
      PolarCircleResolution.aqrabBalad,
      PolarCircleResolution.unresolved
    ]) {
      final suffix =
          polar == PolarCircleResolution.aqrabBalad ? '' : '-${polar.name}';
      final referenceName = 'swift-${correction.name}$suffix.csv.gz';
      final reference = _loadReference('$referenceDir/$referenceName');
      final dart = _loadRows(gridRows(GridOptions(
          hourAngleCorrection: correction,
          polarCircleResolution: polar,
          singaporeRounding: Rounding.up)));
      final differing = _compare(reference, dart);
      defects += differing.length;
      stdout.writeln(
          '${correction.name} ${polar.name}: ${differing.length} differing cells against $referenceName');
      for (final line in differing.take(20)) {
        stdout.writeln('  $line');
      }
    }
  }
  exit(defects == 0 ? 0 : 1);
}

Map<String, List<String>> _loadReference(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('missing reference $path; run from the repository root');
    exit(2);
  }
  final text = String.fromCharCodes(gzip.decode(file.readAsBytesSync()));
  return _loadRows(text.split('\n').where((line) => line.isNotEmpty));
}

Map<String, List<String>> _loadRows(Iterable<String> rows) {
  final result = <String, List<String>>{};
  for (final row in rows) {
    final fields = row.split(',');
    result[fields.sublist(0, 3).join(',')] = fields.sublist(3);
  }
  return result;
}

List<String> _compare(
    Map<String, List<String>> swift, Map<String, List<String>> dart) {
  if (swift.keys.length != dart.keys.length ||
      !swift.keys.every(dart.containsKey)) {
    return ['row keys differ between the two grids'];
  }
  final differing = <String>[];
  for (final key in swift.keys) {
    for (var i = 0; i < prayerNames.length; i++) {
      final s = swift[key]![i];
      final d = dart[key]![i];
      if (s != d) {
        differing.add('$key ${prayerNames[i]}: swift $s, dart $d');
      }
    }
  }
  return differing;
}
