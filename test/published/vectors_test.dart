import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
      expect(File('$vectorsDir/${entry.key}').readAsBytesSync(), entry.value);
    });
  }

  for (final input in Directory('$vectorsDir/valid')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.input.json'))) {
    final name = input.uri.pathSegments.last.replaceFirst('.input.json', '');
    final decoded =
        jsonDecode(input.readAsStringSync()) as Map<String, dynamic>;
    final ott = File('$vectorsDir/valid/$name.ott').readAsBytesSync();

    test('the encoder reproduces $name.ott from its input', () {
      expect(utf8.encode(encodeOtt(decoded)), ott);
    });

    test('the encoder gives the same bytes for a shuffled $name input', () {
      for (var seed = 1; seed <= 5; seed++) {
        final shuffled = _shuffle(decoded, Random(seed));
        expect(utf8.encode(encodeOtt(shuffled)), ott, reason: 'seed $seed');
      }
    });
  }

  test('the encoder refuses a string every decoder rejects', () {
    final input = jsonDecode(
            File('$vectorsDir/valid/canon.input.json').readAsStringSync())
        as Map<String, dynamic>;
    Map<String, dynamic> withName(String name) => {
          ...input,
          'localities': [
            for (final locality in (input['localities'] as List).cast<Map>())
              if (locality['id'] == 'split')
                {
                  ...locality,
                  'names': {'en': name}
                }
              else
                locality
          ],
        };
    expect(encodeOtt(withName('Split')), isNotEmpty);
    expect(() => encodeOtt(withName('\uFEFFSplit')), throwsArgumentError);
    expect(() => encodeOtt(withName('Sp\uD800')), throwsArgumentError);
  });
}

Map<String, dynamic> _shuffle(Map<String, dynamic> input, Random random) {
  final zones = (input['zones'] as List).cast<Map>();
  final order = List.generate(zones.length, (i) => i)..shuffle(random);
  final newIndex = {for (var i = 0; i < order.length; i++) order[i]: i};
  Map<String, dynamic> zone(Map zone) => _shuffleKeys({
        'id': zone['id'],
        'offsets': (zone['offsets'] as List).toList()..shuffle(random),
      }, random);
  Map<String, dynamic> locality(Map locality) => _shuffleKeys({
        for (final entry in locality.entries)
          entry.key as String: switch (entry.key) {
            'zone' => newIndex[entry.value as int],
            'names' => _shuffleKeys(entry.value as Map, random),
            'successors' => (entry.value as List).toList()..shuffle(random),
            _ => entry.value,
          }
      }, random);
  return _shuffleKeys({
    for (final entry in input.entries)
      entry.key: switch (entry.key) {
        'zones' => [for (final i in order) zone(zones[i])],
        'localities' =>
          (input['localities'] as List).cast<Map>().map(locality).toList()
            ..shuffle(random),
        'rows' => _shuffleKeys({
            for (final row in (entry.value as Map).entries)
              row.key as String: _shuffleKeys(row.value as Map, random)
          }, random),
        _ => entry.value,
      }
  }, random);
}

Map<String, dynamic> _shuffleKeys(Map map, Random random) {
  final keys = map.keys.toList()..shuffle(random);
  return {for (final key in keys) key as String: map[key]};
}
