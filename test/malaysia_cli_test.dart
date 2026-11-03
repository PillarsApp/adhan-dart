import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/malaysia/src/malaysia_timetables.dart';

void _copyDirectory(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is Directory) {
      _copyDirectory(entity, Directory('${to.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${to.path}/$name');
    }
  }
}

Directory _copyOfTool() {
  final root = Directory.systemTemp.createTempSync('malaysia_cli_test');
  addTearDown(() => root.deleteSync(recursive: true));
  _copyDirectory(
      Directory('tool/malaysia'), Directory('${root.path}/tool/malaysia'));
  return root;
}

const _esolatDir = 'tool/malaysia/raw/esolat';

List<int> _noRecord(String zone) => utf8.encode(
    '{"prayerTime":{"data":["No data available for the current request"]},'
    '"status":"NO_RECORD!","serverTime":"2026-11-03 11:39:36",'
    '"periodType":"duration","lang":"ms_my","zone":"$zone"}');

final List<int> _errorBody =
    utf8.encode('{"prayerTime":null,"status":"ERROR!"}');
final List<int> _emptyList = utf8.encode('[]');

Map<String, List<int>> _committedTimetables() {
  final bodies = <String, List<int>>{};
  for (final file
      in Directory(_esolatDir).listSync().whereType<File>().toList()) {
    final match = RegExp(r'^(\w+)_(\d{4})\.json\.gz$')
        .firstMatch(file.uri.pathSegments.last)!;
    final body = GZipCodec().decode(file.readAsBytesSync());
    final rows = (jsonDecode(utf8.decode(body)) as Map)['prayerTime'];
    if (rows is List && rows.isNotEmpty) {
      bodies['${match.group(1)} ${match.group(2)}'] = body;
    }
  }
  return bodies;
}

class _FakeEsolat {
  final HttpServer _server;
  final List<String> requests = [];

  _FakeEsolat(this._server);

  String get endpoint => 'http://127.0.0.1:${_server.port}'
      '/index.php?r=esolatApi/takwimsolat&period=duration';

  static Future<_FakeEsolat> serve(
      List<int> Function(String zone, int year) respond) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeEsolat(server);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final zone = request.uri.queryParameters['zone']!;
      final form =
          Uri.splitQueryString(await utf8.decoder.bind(request).join());
      final year = int.parse(form['datestart']!.substring(0, 4));
      fake.requests.add('$zone $year');
      request.response
        ..headers.contentType = ContentType.json
        ..add(respond(zone, year));
      await request.response.close();
    });
    return fake;
  }
}

Future<bool> _fetch(Directory root, List<int> years, _FakeEsolat fake,
        {List<String>? lines, bool refresh = false}) =>
    runZoned(
        () => fetchTimetables(root, years,
            refresh: refresh, endpoint: fake.endpoint, pause: Duration.zero),
        zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines?.add(line)));

Future<ProcessResult> _build(Directory root) =>
    Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/malaysia/malaysia_times_cli.dart',
      'build',
      '--root',
      root.path
    ]);

void main() {
  test('build rejects a row whose maghrib falls before asr and writes nothing',
      () async {
    final root = _copyOfTool();
    final raw = File('${root.path}/$_esolatDir/JHR01_2026.json.gz');
    final json = utf8.decode(GZipCodec().decode(raw.readAsBytesSync()));
    final edited =
        json.replaceFirst(RegExp(r'"maghrib":"[^"]*"'), '"maghrib":"12:00:00"');
    expect(edited, isNot(json));
    raw.writeAsBytesSync(GZipCodec().encode(utf8.encode(edited)));

    final result = await _build(root);

    expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, contains('rejected JHR01 2026-01-01 maghrib'));
    expect(Directory('${root.path}/data').existsSync(), isFalse);
  });

  for (final replacement in {
    'NO_RECORD!': _noRecord('JHR02'),
    '[]': _emptyList,
  }.entries) {
    test(
        'build fails and names a zone-year in force whose response is '
        '${replacement.key}', () async {
      final root = _copyOfTool();
      File('${root.path}/$_esolatDir/JHR02_2026.json.gz')
          .writeAsBytesSync(GZipCodec().encode(replacement.value));

      final result = await _build(root);

      expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('JHR02 2026'));
      expect(Directory('${root.path}/data').existsSync(), isFalse);
    });
  }

  test('build fails when zones.csv lists a zone-year with rows as unpublished',
      () async {
    final root = _copyOfTool();
    final zones = File('${root.path}/tool/malaysia/zones.csv');
    final text = zones.readAsStringSync();
    final edited = text.replaceFirst(
        RegExp(r'(?<=\nJHR01,.*),e-solat,,'), ',e-solat,2026,');
    expect(edited, isNot(text));
    zones.writeAsStringSync(edited);

    final result = await _build(root);

    expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, contains('JHR01 2026 has rows'));
    expect(Directory('${root.path}/data').existsSync(), isFalse);
  });

  test('fetch from an empty raw directory requests every zone-year in force',
      () async {
    final root = _copyOfTool();
    Directory('${root.path}/$_esolatDir').deleteSync(recursive: true);
    final committed = _committedTimetables();
    final sabahUnpublished2027 = {
      for (var i = 1; i <= 9; i++) 'SBH0$i 2027',
    };
    final fake = await _FakeEsolat.serve(
        (zone, year) => committed['$zone $year'] ?? _noRecord(zone));

    final ok = await _fetch(root, [2026, 2027], fake);

    expect(fake.requests.toSet(), {...committed.keys, ...sabahUnpublished2027});
    expect(ok, isTrue);
    final written = {
      for (final file
          in Directory('${root.path}/$_esolatDir').listSync().whereType<File>())
        file.uri.pathSegments.last: GZipCodec().decode(file.readAsBytesSync()),
    };
    expect(written, {
      for (final entry in committed.entries)
        '${entry.key.replaceFirst(' ', '_')}.json.gz': entry.value,
    });
  });

  test(
      'fetch --refresh keeps a stored timetable when e-Solat returns '
      'NO_RECORD! or an error', () async {
    final root = _copyOfTool();
    final committed = _committedTimetables();
    final fake = await _FakeEsolat.serve((zone, year) {
      if (zone == 'JHR01' && year == 2026) return _noRecord(zone);
      if (zone == 'JHR02' && year == 2026) return _errorBody;
      return committed['$zone $year'] ?? _noRecord(zone);
    });
    final before = {
      for (final zone in ['JHR01', 'JHR02'])
        zone: File('${root.path}/$_esolatDir/${zone}_2026.json.gz')
            .readAsBytesSync(),
    };

    final lines = <String>[];
    final ok = await _fetch(root, [2026], fake, lines: lines, refresh: true);

    expect(fake.requests, containsAll(['JHR01 2026', 'JHR02 2026']));
    for (final zone in before.keys) {
      expect(
          File('${root.path}/$_esolatDir/${zone}_2026.json.gz')
              .readAsBytesSync(),
          before[zone],
          reason: zone);
      expect(lines.where((line) => line.contains('$zone 2026')), isNotEmpty);
    }
    expect(ok, isFalse);
  });

  test('fetch writes nothing for a [] response and names the zone-year',
      () async {
    final root = _copyOfTool();
    final stored = File('${root.path}/$_esolatDir/JHR03_2026.json.gz')
      ..deleteSync();
    final committed = _committedTimetables();
    final fake = await _FakeEsolat.serve((zone, year) {
      if (zone == 'JHR03' && year == 2026) return _emptyList;
      return committed['$zone $year'] ?? _noRecord(zone);
    });

    final lines = <String>[];
    final ok = await _fetch(root, [2026], fake, lines: lines);

    expect(fake.requests, contains('JHR03 2026'));
    expect(stored.existsSync(), isFalse);
    expect(lines.where((line) => line.contains('JHR03 2026')), isNotEmpty);
    expect(ok, isFalse);
  });
}
