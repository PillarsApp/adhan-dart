import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/published/ott_encoder.dart';
import '../../tool/published/vectors.dart';

void main() {
  final generated = generateVectors();

  test('the generator writes every file under test/published/vectors', () {
    final onDisk = Directory(vectorsDir)
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) =>
            file.path.substring(vectorsDir.length + 1).replaceAll(r'\', '/'))
        .toSet();
    expect(onDisk, generated.keys.toSet());
  });

  for (final entry in generated.entries) {
    test('${entry.key} matches the generator byte for byte', () {
      expect(File('$vectorsDir/${entry.key}').readAsBytesSync(),
          utf8.encode(entry.value));
    });
  }

  for (final input in Directory('$vectorsDir/valid')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.input.json'))) {
    final name = input.uri.pathSegments.last.replaceFirst('.input.json', '');
    test('the encoder reproduces $name.ott from its input', () {
      final decoded =
          jsonDecode(input.readAsStringSync()) as Map<String, dynamic>;
      expect(utf8.encode(encodeOtt(decoded)),
          File('$vectorsDir/valid/$name.ott').readAsBytesSync());
    });
  }
}
