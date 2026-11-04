@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../tool/malaysia/src/malaysia_timetables.dart';
import '../tool/malaysia/src/osm_fetch.dart';

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

const _osmSnapshot = 'tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz';

List<int> _committedOsmBody() =>
    GZipCodec().decode(File(_osmSnapshot).readAsBytesSync());

Map<String, dynamic> _osmRelation(Map<String, dynamic> document, String iso) =>
    (document['elements'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((element) => (element['tags'] as Map)['ISO3166-2'] == iso);

bool _wayEncloses(Map member, double lat, double lon) {
  final nodes = (member['geometry'] as List).cast<Map>();
  final lats = [for (final node in nodes) (node['lat'] as num).toDouble()];
  final lons = [for (final node in nodes) (node['lon'] as num).toDouble()];
  return lats.reduce(min) <= lat &&
      lat <= lats.reduce(max) &&
      lons.reduce(min) <= lon &&
      lon <= lons.reduce(max);
}

class _FakeOverpass {
  final HttpServer _server;
  var requests = 0;

  _FakeOverpass(this._server);

  String get endpoint => 'http://127.0.0.1:${_server.port}/api/interpreter';

  static Future<_FakeOverpass> serve(List<int> body) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeOverpass(server);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      fake.requests++;
      request.response
        ..headers.contentType = ContentType.json
        ..add(body);
      await request.response.close();
    });
    return fake;
  }
}

Future<bool> _fetchOsm(
        Directory root, _FakeOverpass fake, List<String> lines) =>
    runZoned(
        () => fetchOsmSnapshot(root,
            endpoints: [fake.endpoint], pause: Duration.zero),
        zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines.add(line)));

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

  for (final stored in {
    '$_esolatDir/JHR02_2026.json.gz': 'JHR02 2026',
    'tool/malaysia/raw/selangor/SGRGBK_2027.txt.gz': 'SGRGBK 2027',
  }.entries) {
    final fileName = stored.key.split('/').last;
    test('build fails and names $fileName when it is not gzip', () async {
      final root = _copyOfTool();
      final raw = File('${root.path}/${stored.key}');
      raw.writeAsBytesSync(GZipCodec().decode(raw.readAsBytesSync()));

      final result = await _build(root);

      expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
      expect(LineSplitter.split('${result.stdout}'),
          contains(allOf(contains(stored.value), contains(fileName))));
      expect(Directory('${root.path}/data').existsSync(), isFalse);
    });
  }

  for (final fileName in const [
    'geoBoundaries-MYS-ADM2_simplified.geojson.gz',
    'openstreetmap-MYS-ADM4.json.gz',
  ]) {
    test('build fails and names $fileName when it is not gzip', () async {
      final root = _copyOfTool();
      final raw = File('${root.path}/tool/malaysia/raw/$fileName');
      raw.writeAsBytesSync(GZipCodec().decode(raw.readAsBytesSync()));

      final result = await _build(root);

      expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
      expect(LineSplitter.split('${result.stdout}'),
          contains(allOf(contains(fileName), contains('not gzip'))));
      expect(Directory('${root.path}/data').existsSync(), isFalse);
    });

    test('build fails and names $fileName when its content is not JSON',
        () async {
      final root = _copyOfTool();
      final raw = File('${root.path}/tool/malaysia/raw/$fileName');
      raw.writeAsBytesSync(GZipCodec().encode(utf8.encode('not json')));

      final result = await _build(root);

      expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
      expect(
          LineSplitter.split('${result.stdout}'), contains(contains(fileName)));
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

  test('build fails and names an area that resolves to another state\'s zone',
      () async {
    final root = _copyOfTool();
    File('${root.path}/tool/malaysia/special_areas.csv').writeAsStringSync(
        'JHR02,Johor zone in Rompin,Rompin,2.78,103.4,3000,test\n',
        mode: FileMode.append);

    final result = await _build(root);

    expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout,
        contains('state mismatch JHR02 (Johor) inside OpenStreetMap Pahang'));
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

  test('fetch keeps a stored file that is not gzip and names the zone-year',
      () async {
    final root = _copyOfTool();
    final stored = File('${root.path}/$_esolatDir/JHR03_2026.json.gz');
    final plain = GZipCodec().decode(stored.readAsBytesSync());
    stored.writeAsBytesSync(plain);
    final committed = _committedTimetables();
    final fake = await _FakeEsolat.serve(
        (zone, year) => committed['$zone $year'] ?? _noRecord(zone));

    final lines = <String>[];
    final ok = await _fetch(root, [2026], fake, lines: lines);

    expect(ok, isFalse);
    expect(
        lines,
        contains(
            allOf(contains('JHR03 2026'), contains('JHR03_2026.json.gz'))));
    expect(stored.readAsBytesSync(), plain);
  });

  group('a damaged stored e-Solat file', () {
    final damages = <String, List<int> Function(List<int>)>{
      'cut after half its bytes': (bytes) =>
          bytes.sublist(0, bytes.length ~/ 2),
      'zero bytes': (bytes) => <int>[],
    };

    for (final damage in damages.entries) {
      test('build fails and names the file when it has ${damage.key}',
          () async {
        final root = _copyOfTool();
        final stored = File('${root.path}/$_esolatDir/JHR03_2026.json.gz');
        stored.writeAsBytesSync(damage.value(stored.readAsBytesSync()));

        final result = await _build(root);

        expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
        expect(LineSplitter.split('${result.stdout}'),
            contains(allOf(contains('JHR03 2026'), contains(stored.path))));
        expect(Directory('${root.path}/data').existsSync(), isFalse);
      });

      for (final refresh in [false, true]) {
        test(
            'fetch${refresh ? ' --refresh' : ''} keeps the file and names it '
            'when it has ${damage.key}', () async {
          final root = _copyOfTool();
          final stored = File('${root.path}/$_esolatDir/JHR03_2026.json.gz');
          stored.writeAsBytesSync(damage.value(stored.readAsBytesSync()));
          final damaged = stored.readAsBytesSync();
          final committed = _committedTimetables();
          final fake = await _FakeEsolat.serve(
              (zone, year) => committed['$zone $year'] ?? _noRecord(zone));

          final lines = <String>[];
          final ok =
              await _fetch(root, [2026], fake, lines: lines, refresh: refresh);

          expect(ok, isFalse);
          expect(lines,
              contains(allOf(contains('JHR03 2026'), contains(stored.path))));
          expect(stored.readAsBytesSync(), damaged);
          expect(fake.requests, isNot(contains('JHR03 2026')));
        });
      }
    }
  });

  group('a damaged stored Selangor file', () {
    final damages = <String, List<int> Function(List<int>)>{
      'cut after half its bytes': (bytes) =>
          bytes.sublist(0, bytes.length ~/ 2),
      'text that is not UTF-8': (bytes) =>
          GZipCodec().encode([0x53, 0xff, 0xfe, 0xc3, 0x28]),
    };

    for (final damage in damages.entries) {
      test('build fails and names the file when it has ${damage.key}',
          () async {
        final root = _copyOfTool();
        final stored =
            File('${root.path}/tool/malaysia/raw/selangor/SGRGBK_2027.txt.gz');
        stored.writeAsBytesSync(damage.value(stored.readAsBytesSync()));

        final result = await _build(root);

        expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
        expect(LineSplitter.split('${result.stdout}'),
            contains(allOf(contains('SGRGBK 2027'), contains(stored.path))));
        expect(Directory('${root.path}/data').existsSync(), isFalse);
      });
    }
  });

  group('a fetched e-Solat body that is not every day of the year', () {
    final damages = <String, String Function(String)>{
      'the 2025 dates': (json) => json.replaceAllMapped(
          RegExp(r'("date":"\d{2}-[A-Za-z]+-)2026"'),
          (match) => '${match[1]}2025"'),
      'only the first 200 rows': (json) {
        final document = jsonDecode(json) as Map<String, dynamic>;
        document['prayerTime'] =
            (document['prayerTime'] as List).sublist(0, 200);
        return jsonEncode(document);
      },
    };

    for (final damage in damages.entries) {
      for (final refresh in [false, true]) {
        test(
            'fetch${refresh ? ' --refresh' : ''} writes nothing for '
            '${damage.key} and names the zone-year', () async {
          final root = _copyOfTool();
          final stored = File('${root.path}/$_esolatDir/JHR01_2026.json.gz');
          if (!refresh) stored.deleteSync();
          final before = stored.existsSync() ? stored.readAsBytesSync() : null;
          final committed = _committedTimetables();
          final json = utf8.decode(committed['JHR01 2026']!);
          final damaged = damage.value(json);
          expect(damaged, isNot(json));
          final fake = await _FakeEsolat.serve((zone, year) =>
              zone == 'JHR01' && year == 2026
                  ? utf8.encode(damaged)
                  : committed['$zone $year'] ?? _noRecord(zone));

          final lines = <String>[];
          final ok =
              await _fetch(root, [2026], fake, lines: lines, refresh: refresh);

          expect(ok, isFalse);
          expect(fake.requests, contains('JHR01 2026'));
          expect(
              lines,
              contains(allOf(
                  contains('JHR01 2026'), contains('not the days of 2026'))));
          expect(stored.existsSync() ? stored.readAsBytesSync() : null, before);
          if (refresh) expect(lines, contains('JHR02 2026 365 rows'));
        });
      }
    }
  });

  group('fetch-osm', () {
    test('stores an Overpass body that matches the committed snapshot',
        () async {
      final root = _copyOfTool();
      final committed = _committedOsmBody();
      final fake = await _FakeOverpass.serve(committed);

      final lines = <String>[];
      final ok = await _fetchOsm(root, fake, lines);

      expect(ok, isTrue, reason: lines.join('\n'));
      final written = GZipCodec()
          .decode(File('${root.path}/$_osmSnapshot').readAsBytesSync());
      expect((jsonDecode(utf8.decode(written)) as Map)['elements'],
          (jsonDecode(utf8.decode(committed)) as Map)['elements']);
    });

    final damages = <String, String Function(Map<String, dynamic>)>{
      'an osm_base older than the pinned date': (document) {
        (document['osm3s'] as Map)['timestamp_osm_base'] =
            '2026-07-15T00:00:00Z';
        return 'osm_base 2026-07-15T00:00:00Z';
      },
      'an Overpass remark': (document) {
        document['remark'] = 'runtime error: Query timed out in "query" '
            'at line 1 after 901 seconds.';
        return 'runtime error';
      },
      'no Pulau Aman ring in Pulau Pinang': (document) {
        final members = _osmRelation(document, 'MY-07')['members'] as List;
        final before = members.length;
        members.removeWhere((member) =>
            member['type'] == 'way' &&
            member['role'] == 'outer' &&
            _wayEncloses(member as Map, 5.26039, 100.38661));
        expect(members.length, before - 1);
        return 'MY-07 outer';
      },
      'no MY-16 relation': (document) {
        (document['elements'] as List).remove(_osmRelation(document, 'MY-16'));
        return 'lacks MY-16';
      },
      'an outer way without geometry': (document) {
        final members = _osmRelation(document, 'MY-16')['members'] as List;
        (members.firstWhere((member) => member['role'] == 'outer') as Map)
            .remove('geometry');
        return 'no geometry';
      },
    };

    for (final damage in damages.entries) {
      test('keeps the stored snapshot when Overpass returns ${damage.key}',
          () async {
        final root = _copyOfTool();
        final stored = File('${root.path}/$_osmSnapshot');
        final before = stored.readAsBytesSync();
        final document = jsonDecode(utf8.decode(_committedOsmBody()))
            as Map<String, dynamic>;
        final reason = damage.value(document);
        final fake =
            await _FakeOverpass.serve(utf8.encode(jsonEncode(document)));

        final lines = <String>[];
        final ok = await _fetchOsm(root, fake, lines);

        expect(ok, isFalse);
        expect(fake.requests, greaterThan(0));
        expect(
            lines, contains(allOf(contains(fake.endpoint), contains(reason))));
        expect(stored.readAsBytesSync(), before);
      });
    }

    test('keeps a stored snapshot that is not gzip and fetches nothing',
        () async {
      final root = _copyOfTool();
      final stored = File('${root.path}/$_osmSnapshot')
        ..writeAsStringSync('not gzip');
      final fake = await _FakeOverpass.serve(_committedOsmBody());

      final lines = <String>[];
      final ok = await _fetchOsm(root, fake, lines);

      expect(ok, isFalse);
      expect(fake.requests, 0);
      expect(lines, contains(allOf(contains(stored.path), contains('gzip'))));
      expect(stored.readAsStringSync(), 'not gzip');
    });
  });
}
