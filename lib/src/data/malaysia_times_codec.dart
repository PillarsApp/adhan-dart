const int malaysiaTimeFieldCount = 8;

class MalaysiaZoneYear {
  final String zone;
  final int year;
  final List<List<int>> days;

  MalaysiaZoneYear(this.zone, this.year, this.days);
}

const String _deltaCells = 'abcdefg';

String encodeMalaysiaTimes(List<MalaysiaZoneYear> zoneYears) {
  final out = StringBuffer();
  for (final zoneYear in zoneYears) {
    out.write('${zoneYear.zone} ${zoneYear.year} ');
    List<int>? previous;
    for (final day in zoneYear.days) {
      if (day.length != malaysiaTimeFieldCount) {
        throw ArgumentError('${zoneYear.zone} ${zoneYear.year}: '
            'expected $malaysiaTimeFieldCount values per day');
      }
      for (var i = 0; i < day.length; i++) {
        final minutes = day[i];
        if (minutes < 0 || minutes > 1439) {
          throw ArgumentError('${zoneYear.zone} ${zoneYear.year}: '
              '$minutes is not a minute of the day');
        }
        final delta = previous == null ? null : minutes - previous[i];
        if (delta != null && delta >= -3 && delta <= 3) {
          out.write(_deltaCells[delta + 3]);
        } else {
          out.write(previous == null ? '' : '~');
          out.write(_formatHhmm(minutes));
        }
      }
      previous = day;
    }
    out.write('\n');
  }
  return out.toString();
}

List<MalaysiaZoneYear> decodeMalaysiaTimes(String text) {
  final zoneYears = <MalaysiaZoneYear>[];
  for (final line in text.split('\n')) {
    if (line.isEmpty) continue;
    final parts = line.split(' ');
    if (parts.length != 3) {
      throw FormatException('Expected "<zone> <year> <days>"', line);
    }
    final data = parts[2];
    var position = 0;
    int readHhmm() {
      if (position + 4 > data.length) {
        throw FormatException('Truncated time in ${parts[0]} ${parts[1]}');
      }
      final value = int.parse(data.substring(position, position + 4));
      position += 4;
      return (value ~/ 100) * 60 + value % 100;
    }

    final days = <List<int>>[
      [for (var i = 0; i < malaysiaTimeFieldCount; i++) readHhmm()],
    ];
    while (position < data.length) {
      final previous = days.last;
      final day = <int>[];
      for (var i = 0; i < malaysiaTimeFieldCount; i++) {
        if (position >= data.length) {
          throw FormatException('Truncated day in ${parts[0]} ${parts[1]}');
        }
        final cell = data[position++];
        if (cell == '~') {
          day.add(readHhmm());
        } else {
          final delta = _deltaCells.indexOf(cell) - 3;
          if (delta < -3) {
            throw FormatException(
                'Unexpected "$cell" in ${parts[0]} ${parts[1]}');
          }
          day.add(previous[i] + delta);
        }
      }
      days.add(day);
    }
    zoneYears.add(MalaysiaZoneYear(parts[0], int.parse(parts[1]), days));
  }
  return zoneYears;
}

String _formatHhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}'
    '${(minutes % 60).toString().padLeft(2, '0')}';
