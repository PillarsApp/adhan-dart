import 'dart:convert';
import 'dart:io';

import 'package:adhan/src/data/date_components.dart';

import 'src/malaysia_manifest.dart';
import 'src/malaysia_timetables.dart';
import 'src/malaysia_zones.dart';
import 'src/osm_fetch.dart';

const usage = '''
Malaysian timetable and zone data generator

Usage:
  dart run tool/malaysia/malaysia_times_cli.dart fetch <year>... [--refresh] [--root <dir>]
  dart run tool/malaysia/malaysia_times_cli.dart import-selangor <pdf>... [--root <dir>]
  dart run tool/malaysia/malaysia_times_cli.dart fetch-osm [--root <dir>]
  dart run tool/malaysia/malaysia_times_cli.dart build [--root <dir>]
  dart run tool/malaysia/malaysia_times_cli.dart check <zones file> [--root <dir>]
  dart run tool/malaysia/malaysia_times_cli.dart lookup <latitude> <longitude> <yyyy-mm-dd>

fetch            Download every e-Solat zone that tool/malaysia/zones.csv has in force in
                 each year into tool/malaysia/raw/esolat/. Skips a zone-year whose stored
                 file has rows unless --refresh is given. Writes a response only when its
                 rows are the days of the year, each once and in order, and otherwise
                 leaves the stored file as it was. Exits 1 when a download fails, a
                 response is not written (NO_RECORD! for a zone-year with no stored rows
                 excepted), or a stored file cannot be read as gzip.
import-selangor  Extract the Selangor district PDFs with pdftotext -layout into
                 tool/malaysia/raw/selangor/ and record each PDF's SHA-256.
fetch-osm        Download the pinned OpenStreetMap snapshot of Malaysia's state
                 boundaries from the Overpass API into tool/malaysia/raw/. Writes
                 nothing and exits 1 when the stored snapshot cannot be read, or
                 unless an endpoint returns every state with geometry on every
                 border way, no Overpass remark, an osm_base no older than the
                 pinned date, and at least as many rings per state and role as the
                 stored snapshot. Delete the stored snapshot first when a ring is
                 meant to go.
build            Validate every zone-year, apply tool/malaysia/corrections.csv, and write
                 data/malaysia/ and lib/src/data/malaysia_*_data.dart. Exits 1 and writes
                 nothing when any row is rejected, a zone-year that zones.csv has in
                 force has no rows, a stored file is not gzip, or a zone check fails.
check            Measure a zones file against the OpenStreetMap snapshot and
                 print every area that resolves to another state's zone.
                 Exits 1 when there is one.
lookup           Print the zone in force at a point on a date, or none.

--root <dir>     Repository root. Defaults to the current directory.
''';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stderr.write(usage);
    exitCode = 64;
    return;
  }
  switch (options.command) {
    case 'fetch':
      final fetched = await fetchTimetables(
          options.root, options.positional.map(int.parse).toList(),
          refresh: options.refresh);
      if (!fetched) exitCode = 1;
      break;
    case 'import-selangor':
      importSelangor(options.root, options.positional);
      break;
    case 'fetch-osm':
      if (!await fetchOsmSnapshot(options.root)) exitCode = 1;
      break;
    case 'build':
      exitCode = build(options.root);
      break;
    case 'check':
      final lines = checkZones(options.root, File(options.positional[0]));
      lines.forEach(print);
      if (lines.any((line) => line.startsWith('state mismatch'))) exitCode = 1;
      break;
    case 'lookup':
      final date = DateTime.parse(options.positional[2]);
      print(lookupZone(
              double.parse(options.positional[0]),
              double.parse(options.positional[1]),
              DateComponents(date.year, date.month, date.day)) ??
          'none');
      break;
  }
}

const maxOutputBytes = 400000;
const maxGzippedOutputBytes = 60000;

int build(Directory root) {
  final timetables = buildTimetables(root);
  final zones = buildZones(root);
  final outputs = {
    'malaysia_times.txt': utf8.encode(timetables.output),
    'malaysia_zones.txt': utf8.encode(zones.output),
  };
  final errors = [...timetables.errors, ...zones.errors];
  outputs.forEach((name, bytes) {
    final gzipped = GZipCodec(level: 9).encode(bytes).length;
    print('$name ${bytes.length} bytes, $gzipped gzipped');
    if (bytes.length > maxOutputBytes || gzipped > maxGzippedOutputBytes) {
      errors.add('$name exceeds $maxOutputBytes bytes or '
          '$maxGzippedOutputBytes bytes gzipped');
    }
  });
  errors.forEach(print);
  print(timetables.summary);
  print(zones.summary);
  if (errors.isNotEmpty) return 1;

  final dataDir = Directory('${root.path}/data/malaysia')
    ..createSync(recursive: true);
  outputs.forEach(
      (name, bytes) => File('${dataDir.path}/$name').writeAsBytesSync(bytes));
  File('${dataDir.path}/MANIFEST').writeAsStringSync(
      renderManifest(outputs, [...timetables.sources, ...zones.sources]));
  _writeDartConstant(
      root, 'malaysia_times_data.dart', 'malaysiaTimesData', timetables.output);
  _writeDartConstant(
      root, 'malaysia_zones_data.dart', 'malaysiaZonesData', zones.output);
  return 0;
}

void _writeDartConstant(
    Directory root, String fileName, String name, String text) {
  File('${root.path}/lib/src/data/$fileName')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
        '// Generated by tool/malaysia/malaysia_times_cli.dart build. Do not edit.\n'
        "const String $name =\n    r'''$text''';\n");
}

class _Options {
  final String command;
  final List<String> positional;
  final Directory root;
  final bool refresh;

  _Options(this.command, this.positional, this.root, this.refresh);

  static const _arity = {
    'fetch-osm': 0,
    'build': 0,
    'check': 1,
    'lookup': 3,
  };

  static _Options? parse(List<String> args) {
    if (args.isEmpty) return null;
    final command = args.first;
    if (!const [
      'fetch',
      'import-selangor',
      'fetch-osm',
      'build',
      'check',
      'lookup'
    ].contains(command)) {
      return null;
    }
    final positional = <String>[];
    var root = Directory.current;
    var refresh = false;
    for (var i = 1; i < args.length; i++) {
      if (args[i] == '--refresh') {
        refresh = true;
      } else if (args[i] == '--root' && i + 1 < args.length) {
        root = Directory(args[++i]);
      } else if (args[i].startsWith('--')) {
        return null;
      } else {
        positional.add(args[i]);
      }
    }
    final arity = _arity[command];
    if (arity != null && positional.length != arity) return null;
    if (arity == null && positional.isEmpty) return null;
    return _Options(command, positional, root, refresh);
  }
}
