import 'dart:io';

import 'package:adhan/adhan.dart';

import 'grid.dart';

/// Compares this library's grid with the adhan-swift grid for each
/// `hourAngleCorrection` value and prints the number of differing cells.
///
/// The Singapore method rounds up in adhan-swift and to the nearest minute
/// here, so a Singapore cell where Swift is exactly one minute later is
/// excluded and counted separately. Every other difference is a defect.
///
/// usage: dart run tool/parity/compare.dart [--reference-dir tool/parity/reference]
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

  var defects = 0;
  for (final correction in HourAngleCorrection.values) {
    final referenceName = 'swift-${correction.name}.csv.gz';
    final reference = _loadReference('$referenceDir/$referenceName');
    final dart =
        _loadRows(gridRows(GridOptions(hourAngleCorrection: correction)));
    final result = _compare(reference, dart);
    defects += result.differing.length;
    stdout.writeln(
        '${correction.name}: ${result.differing.length} differing cells against $referenceName'
        ' (${result.excludedSingaporeCells} Singapore cells excluded:'
        ' adhan-swift rounds the Singapore method up, this library rounds it to the nearest minute)');
    for (final line in result.differing.take(20)) {
      stdout.writeln('  $line');
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

class _Comparison {
  final List<String> differing = [];
  int excludedSingaporeCells = 0;
}

_Comparison _compare(
    Map<String, List<String>> swift, Map<String, List<String>> dart) {
  final result = _Comparison();
  if (swift.keys.length != dart.keys.length ||
      !swift.keys.every(dart.containsKey)) {
    result.differing.add('row keys differ between the two grids');
    return result;
  }
  for (final key in swift.keys) {
    final isSingapore = key.endsWith(',singapore_mid');
    for (var i = 0; i < prayerNames.length; i++) {
      final s = swift[key]![i];
      final d = dart[key]![i];
      if (s == d) {
        continue;
      }
      final sSeconds = int.tryParse(s);
      final dSeconds = int.tryParse(d);
      if (isSingapore &&
          sSeconds != null &&
          dSeconds != null &&
          sSeconds - dSeconds == 60) {
        result.excludedSingaporeCells++;
        continue;
      }
      result.differing.add('$key ${prayerNames[i]}: swift $s, dart $d');
    }
  }
  return result;
}
