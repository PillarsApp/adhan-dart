const int maxPublishedMinute = 2879;

const String _deltaCells = 'abcdefg';

enum CellRule {
  truncatedTime('cell.truncatedTime'),
  digits('cell.digits'),
  minute('cell.minute'),
  hour('cell.hour'),
  letter('cell.letter'),
  delta('cell.delta'),
  truncatedDay('cell.truncatedDay');

  const CellRule(this.id);

  final String id;
}

FormatException _violation(CellRule rule, String detail, int position) =>
    FormatException('${rule.id}: $detail at offset $position');

String encodeCells(List<List<int>> days, int columns) {
  final out = StringBuffer();
  List<int>? previous;
  for (final day in days) {
    if (day.length != columns) {
      throw ArgumentError(
          'expected $columns values per day, got ${day.length}');
    }
    for (var i = 0; i < columns; i++) {
      final minutes = day[i];
      if (minutes < 0 || minutes > maxPublishedMinute) {
        throw ArgumentError('$minutes is not a minute of a published day');
      }
      final delta = previous == null ? null : minutes - previous[i];
      if (delta != null && delta >= -3 && delta <= 3) {
        out.write(_deltaCells[delta + 3]);
      } else {
        if (previous != null) out.write('~');
        out.write(formatHhmm(minutes));
      }
    }
    previous = day;
  }
  return out.toString();
}

int readHhmm(String cells, int position) {
  if (position + 4 > cells.length) {
    throw _violation(CellRule.truncatedTime,
        'a time has ${cells.length - position} of four digits', position);
  }
  final digits = List<int>.generate(4, (i) {
    final unit = cells.codeUnitAt(position + i);
    if (unit < 0x30 || unit > 0x39) {
      throw _violation(
          CellRule.digits, 'a time has a byte that is not a digit', position);
    }
    return unit - 0x30;
  });
  final minutes = digits[2] * 10 + digits[3];
  if (minutes > 59) {
    throw _violation(CellRule.minute, 'a time has minute $minutes', position);
  }
  final value = (digits[0] * 10 + digits[1]) * 60 + minutes;
  if (value > maxPublishedMinute) {
    throw _violation(CellRule.hour, 'a time is after 47:59', position);
  }
  return value;
}

List<List<int>> decodeCells(String cells, int columns) {
  var position = 0;
  int time() {
    final value = readHhmm(cells, position);
    position += 4;
    return value;
  }

  final days = <List<int>>[
    [for (var i = 0; i < columns; i++) time()],
  ];
  while (position < cells.length) {
    final previous = days.last;
    final day = <int>[];
    for (var i = 0; i < columns; i++) {
      if (position >= cells.length) {
        throw _violation(CellRule.truncatedDay,
            'a day has ${day.length} of $columns cells', position);
      }
      final cell = cells[position++];
      if (cell == '~') {
        day.add(time());
      } else {
        final delta = _deltaCells.indexOf(cell) - 3;
        if (delta < -3) {
          throw _violation(CellRule.letter, 'a cell is "$cell"', position - 1);
        }
        final value = previous[i] + delta;
        if (value < 0 || value > maxPublishedMinute) {
          throw _violation(
              CellRule.delta, 'a delta leaves 0 to 47:59', position - 1);
        }
        day.add(value);
      }
    }
    days.add(day);
  }
  return days;
}

String formatHhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}'
    '${(minutes % 60).toString().padLeft(2, '0')}';
