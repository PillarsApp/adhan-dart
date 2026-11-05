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

Directory copyOfTool() {
  final root = Directory.systemTemp.createTempSync('malaysia_cli_test');
  addTearDown(() => root.deleteSync(recursive: true));
  _copyDirectory(
      Directory('tool/malaysia'), Directory('${root.path}/tool/malaysia'));
  return root;
}

List<String> committedZonesLines() =>
    File('data/malaysia/malaysia_zones.txt').readAsStringSync().split('\n');

String writeZones(List<String> lines) {
  final file = File(
      '${Directory.systemTemp.createTempSync('malaysia_zones').path}/zones.txt')
    ..writeAsStringSync(lines.join('\n'));
  addTearDown(() => file.parent.deleteSync(recursive: true));
  return file.path;
}

String plantedZones(String Function(List<String> fields, int region) edit) {
  var region = -1;
  return writeZones([
    for (final line in committedZonesLines())
      () {
        final fields = line.split('\t');
        if (fields[0] == 'R') region++;
        return edit(fields, region);
      }()
  ]);
}

int regionOf(String rows) => committedZonesLines()
    .where((line) => line.startsWith('R\t'))
    .toList()
    .indexWhere((line) => line.split('\t')[2] == rows);
