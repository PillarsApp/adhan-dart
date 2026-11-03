import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

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

void main() {
  test('build rejects a row whose maghrib falls before asr and writes nothing',
      () async {
    final root = Directory.systemTemp.createTempSync('malaysia_cli_test');
    addTearDown(() => root.deleteSync(recursive: true));
    _copyDirectory(
        Directory('tool/malaysia'), Directory('${root.path}/tool/malaysia'));

    final raw =
        File('${root.path}/tool/malaysia/raw/esolat/JHR01_2026.json.gz');
    final json = utf8.decode(GZipCodec().decode(raw.readAsBytesSync()));
    final edited =
        json.replaceFirst(RegExp(r'"maghrib":"[^"]*"'), '"maghrib":"12:00:00"');
    expect(edited, isNot(json));
    raw.writeAsBytesSync(GZipCodec().encode(utf8.encode(edited)));

    final result = await Process.run(Platform.resolvedExecutable,
        ['run', 'bin/malaysia_times_cli.dart', 'build', '--root', root.path]);

    expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, contains('rejected JHR01 2026-01-01 maghrib'));
    expect(Directory('${root.path}/data').existsSync(), isFalse);
  });
}
