part of 'published_timetable.dart';

const int _malaysiaOffsetMinutes = 480;

const List<PublishedColumn> _malaysiaColumns = [
  PublishedColumn.imsak,
  PublishedColumn.fajr,
  PublishedColumn.sunrise,
  PublishedColumn.dhuha,
  PublishedColumn.dhuhr,
  PublishedColumn.asr,
  PublishedColumn.maghrib,
  PublishedColumn.isha,
];

final class MalaysiaOfficialSource implements OfficialTimetableSource {
  const MalaysiaOfficialSource._();

  static const MalaysiaOfficialSource instance = MalaysiaOfficialSource._();

  static final Map<String, Locality> _localities = {
    for (final zone in MalaysiaZones.all)
      zone.code: Locality._(
          id: LocalityId(zone.code),
          group: zone.state,
          names: {'ms': zone.areas},
          referencePoint: zone.referencePoint,
          validFrom: zone.validFrom,
          validTo: zone.validTo,
          successors: [
            for (final successor in zone.successors) LocalityId(successor.code)
          ])
  };

  static final Map<String, _MalaysiaLine> _lines = _indexMalaysiaLines();

  static Map<String, _MalaysiaLine> _indexMalaysiaLines() {
    final lines = <String, _MalaysiaLine>{};
    var start = 0;
    while (start < malaysiaTimesData.length) {
      final end = malaysiaTimesData.indexOf('\n', start);
      final header = malaysiaTimesData.indexOf(
          ' ', malaysiaTimesData.indexOf(' ', start) + 1);
      lines[malaysiaTimesData.substring(start, header)] =
          _MalaysiaLine(start, end);
      start = end + 1;
    }
    return lines;
  }

  @override
  String get authority => 'jakim';

  @override
  String get revision => malaysiaDataRevision;

  @override
  Iterable<Locality> get localities => _localities.values;

  @override
  Locality? locality(LocalityId id) => _localities[id.value];

  @override
  Locality? localityAt(Coordinates coordinates, DateComponents date) {
    final zone = MalaysiaZones.resolve(coordinates, date);
    return zone == null ? null : _localities[zone.code];
  }

  @override
  OfficialLookup lookup(Coordinates coordinates, DateComponents date,
      {LocalityId? localityId}) {
    final zone = localityId == null
        ? MalaysiaZones.resolve(coordinates, date)
        : MalaysiaZones.zone(localityId.value);
    if (zone == null) return const NoLocality();
    final locality = _localities[zone.code]!;
    final line = _lines['${zone.code} ${date.year}'];
    final dayOfYear = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(date.year))
        .inDays;
    if (line == null || dayOfYear >= line.days.length) {
      return NoRow(locality);
    }
    return OfficialRow._(
        locality: locality,
        date: date,
        authority: authority,
        revision: revision,
        asrShadow: 1,
        columns: _malaysiaColumns,
        minutes: line.days[dayOfYear],
        offsetMinutes: _malaysiaOffsetMinutes);
  }
}

class _MalaysiaLine {
  final int start;
  final int end;
  List<List<int>>? _days;

  _MalaysiaLine(this.start, this.end);

  List<List<int>> get days => _days ??=
      decodeMalaysiaTimes(malaysiaTimesData.substring(start, end)).single.days;
}
