import 'delta_cells_codec.dart';

const int malaysiaTimeFieldCount = 8;

class MalaysiaZoneYear {
  final String zone;
  final int year;
  final List<List<int>> days;

  MalaysiaZoneYear(this.zone, this.year, this.days);
}

String encodeMalaysiaTimes(List<MalaysiaZoneYear> zoneYears) {
  final out = StringBuffer();
  for (final zoneYear in zoneYears) {
    out.write('${zoneYear.zone} ${zoneYear.year} '
        '${encodeCells(zoneYear.days, malaysiaTimeFieldCount)}\n');
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
    try {
      zoneYears.add(MalaysiaZoneYear(parts[0], int.parse(parts[1]),
          decodeCells(parts[2], malaysiaTimeFieldCount)));
    } on FormatException catch (error) {
      throw FormatException('${error.message} in ${parts[0]} ${parts[1]}');
    }
  }
  return zoneYears;
}
