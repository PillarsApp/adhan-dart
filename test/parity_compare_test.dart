import 'package:test/test.dart';

import '../tool/parity/compare.dart' show differingCells, parseGrid;

void main() {
  const row = 'London,2026-06-21,mwl_mid,1,2,3,4,5,6';
  const conflictingRow = 'London,2026-06-21,mwl_mid,7,2,3,4,5,6';

  test('a second row with the same key fails, whichever comes first', () {
    expect(() => parseGrid([conflictingRow, row]), throwsFormatException);
    expect(() => parseGrid([row, row]), throwsFormatException);
  });

  test('a row with an extra or a missing column fails', () {
    expect(() => parseGrid(['$row,7']), throwsFormatException);
    expect(() => parseGrid(['London,2026-06-21,mwl_mid,1,2,3,4,5']),
        throwsFormatException);
  });

  test('a changed cell is reported', () {
    expect(differingCells(parseGrid([row]), parseGrid([conflictingRow])),
        ['London,2026-06-21,mwl_mid fajr: swift 1, dart 7']);
    expect(differingCells(parseGrid([row]), parseGrid([row])), isEmpty);
  });
}
