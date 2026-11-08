const int maxPublishedMinute = 2879;

const String _deltaCells = 'abcdefg';

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

List<List<int>> decodeCells(String cells, int columns) {
  var position = 0;
  int readHhmm() {
    if (position + 4 > cells.length) {
      throw FormatException('Truncated time', cells, position);
    }
    final hours = int.tryParse(cells.substring(position, position + 2));
    final minutes = int.tryParse(cells.substring(position + 2, position + 4));
    if (hours == null || minutes == null || hours < 0 || minutes < 0) {
      throw FormatException('Expected four digits', cells, position);
    }
    if (minutes > 59) {
      throw FormatException('Minute above 59', cells, position);
    }
    position += 4;
    final value = hours * 60 + minutes;
    if (value > maxPublishedMinute) {
      throw FormatException('Time after 47:59', cells, position - 4);
    }
    return value;
  }

  final days = <List<int>>[
    [for (var i = 0; i < columns; i++) readHhmm()],
  ];
  while (position < cells.length) {
    final previous = days.last;
    final day = <int>[];
    for (var i = 0; i < columns; i++) {
      if (position >= cells.length) {
        throw FormatException('Truncated day', cells, position);
      }
      final cell = cells[position++];
      if (cell == '~') {
        day.add(readHhmm());
      } else {
        final delta = _deltaCells.indexOf(cell) - 3;
        if (delta < -3) {
          throw FormatException('Unexpected cell "$cell"', cells, position - 1);
        }
        final value = previous[i] + delta;
        if (value < 0 || value > maxPublishedMinute) {
          throw FormatException('Delta leaves the day', cells, position - 1);
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
