import 'dart:io';

import 'package:test/test.dart';

import '../tool/parity/malaysia_golden.dart';

const _expectedGroups = 828;

void main() {
  test('Malaysian times match the golden recorded at c6dc5b6', () {
    final golden = <String, String>{};
    final rows = File('test/malaysia/golden_c6dc5b6.tsv').readAsLinesSync();
    for (final row in rows.skip(1)) {
      final columns = row.split('\t');
      golden[columns.take(4).join('\t')] = columns[4];
    }
    expect(golden, hasLength(_expectedGroups));

    final head = malaysiaGoldenDigests();
    expect(head.keys.toList(), golden.keys.toList());

    final mismatches = <String>[
      for (final entry in golden.entries)
        if (head[entry.key] != entry.value) entry.key.replaceAll('\t', ' ')
    ];
    expect(mismatches, isEmpty, reason: 'groups whose minutes changed');
  });
}
