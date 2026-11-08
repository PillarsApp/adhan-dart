import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../coordinates.dart';
import '../data/date_components.dart';
import '../data/delta_cells_codec.dart';
import '../data/malaysia_times_codec.dart';
import '../data/malaysia_times_data.dart';
import '../data/malaysia_zone_map.dart' show MalaysiaZoneMap;
import '../malaysia/malaysia_timetable.dart';
import '../malaysia/malaysia_zones.dart';

part '../malaysia/malaysia_source.dart';
part 'format.dart';
part 'locality_index.dart';

/// The id of a locality as its authority publishes it.
extension type const LocalityId(String value) {}

/// A column a published row may carry. The six core columns are always
/// present; the wire name of a column is its [name].
enum PublishedColumn {
  imsak,
  fajr,
  sunrise,
  dhuha,
  dhuhr,
  asr,
  asrHanafi,
  maghrib,
  isha,
  eid;

  bool get isCore => switch (this) {
        fajr || sunrise || dhuhr || asr || maghrib || isha => true,
        _ => false,
      };
}

/// A place an authority publishes times for.
final class Locality {
  final LocalityId id;

  /// A region key for grouped pickers, such as a KACST region or a Malaysian
  /// state.
  final String group;

  /// Localized names by language code. May be empty.
  final Map<String, String> names;

  /// The point of a point locality, or the declared centre of an area. The
  /// Hanafi shift of Asr is computed here.
  final Coordinates referencePoint;

  /// The first day the locality is in force, or null when it always has been.
  final DateComponents? validFrom;

  /// The last day the locality is in force, or null when it has no end.
  final DateComponents? validTo;

  /// The localities that replace this one after [validTo].
  final List<LocalityId> successors;

  Locality._({
    required this.id,
    required this.group,
    required Map<String, String> names,
    required this.referencePoint,
    required this.validFrom,
    required this.validTo,
    required List<LocalityId> successors,
  })  : names = Map.unmodifiable(names),
        successors = List.unmodifiable(successors);

  /// The name in [languageCode], else English, else the id.
  String name(String languageCode) =>
      names[languageCode] ?? names['en'] ?? id.value;

  bool inForceOn(DateComponents date) {
    final key = _dateKey(date);
    final from = validFrom;
    final to = validTo;
    return (from == null || _dateKey(from) <= key) &&
        (to == null || key <= _dateKey(to));
  }

  @override
  bool operator ==(Object other) => other is Locality && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Locality(${id.value})';
}

/// The outcome of asking a source for one date at one place.
sealed class OfficialLookup {
  const OfficialLookup();
}

/// A published row exists. Only a source constructs one, so holding an
/// [OfficialRow] proves the row came from published data.
final class OfficialRow extends OfficialLookup {
  final Locality locality;
  final DateComponents date;
  final String authority;
  final String revision;

  /// The shadow factor of the published [PublishedColumn.asr]: 1 or 2.
  final int asrShadow;

  /// The columns the row carries, in wire order.
  final List<PublishedColumn> columns;
  final List<int> _minutes;
  final int _offsetMinutes;

  OfficialRow._(
      {required this.locality,
      required this.date,
      required this.authority,
      required this.revision,
      required this.asrShadow,
      required this.columns,
      required List<int> minutes,
      required int offsetMinutes})
      : _minutes = minutes,
        _offsetMinutes = offsetMinutes;

  /// The offset east of UTC the authority published the row's wall times in.
  Duration get utcOffset => Duration(minutes: _offsetMinutes);

  /// The published instant of [column] in UTC, before adjustments and the
  /// Hanafi shift, or null when the row has no such column.
  DateTime? published(PublishedColumn column) {
    final index = columns.indexOf(column);
    if (index < 0) return null;
    return DateTime.utc(date.year, date.month, date.day)
        .add(Duration(minutes: _minutes[index] - _offsetMinutes));
  }
}

/// No locality covers the coordinates on the date, or a manual id is unknown.
final class NoLocality extends OfficialLookup {
  const NoLocality();
}

/// The locality is known but the data has no row for the date.
final class NoRow extends OfficialLookup {
  final Locality locality;

  const NoRow(this.locality);
}

/// Anything that can answer "the published times here, on this date".
abstract interface class OfficialTimetableSource {
  String get authority;

  String get revision;

  /// Every locality the source knows, in force or not.
  Iterable<Locality> get localities;

  /// The locality with [id], in force or not, or null for an unknown id.
  Locality? locality(LocalityId id);

  /// The locality in force at [coordinates] on [date], or null when none
  /// covers them. Throws [ArgumentError] for a non-finite coordinate.
  Locality? localityAt(Coordinates coordinates, DateComponents date);

  /// The row at [coordinates] on [date]. A [localityId] skips resolution and
  /// never reads the coordinates: an unknown id is [NoLocality], a known id
  /// is used whether or not it is in force on [date].
  OfficialLookup lookup(Coordinates coordinates, DateComponents date,
      {LocalityId? localityId});
}

/// A timetable decoded from `OTT 1` bytes.
///
/// [decode] reads the header and indexes the row lines. A line's cells are
/// decoded on first use and cached, so a process that needs one row never
/// pays for the whole file. [validateAllRows] decodes every line once.
final class PublishedTimetable implements OfficialTimetableSource {
  final Uint8List _bytes;
  final _Header _header;
  final List<List<_RowLine>> _lines;

  PublishedTimetable._(this._bytes, this._header, this._lines);

  /// Throws [FormatException] unless line 1 and the header are valid `OTT 1`
  /// and every row line names a known locality, starts on a date inside
  /// coverage and opens with a full first day of digits.
  factory PublishedTimetable.decode(Uint8List bytes) {
    if (bytes.isEmpty) throw FormatException('the file is empty');
    if (bytes.last != _lf) throw FormatException('the last line has no LF');
    if (bytes.contains(_cr)) throw FormatException('the file contains a CR');
    final firstBreak = bytes.indexOf(_lf);
    if (String.fromCharCodes(bytes, 0, firstBreak) != _magicLine) {
      throw FormatException('line 1 is not "$_magicLine"');
    }
    final secondBreak = bytes.indexOf(_lf, firstBreak + 1);
    if (secondBreak < 0) throw FormatException('the header line is absent');
    final header = _Header.parse(
        utf8.decode(Uint8List.sublistView(bytes, firstBreak + 1, secondBreak)));
    return PublishedTimetable._(
        bytes, header, _indexLines(bytes, secondBreak + 1, header));
  }

  /// Decodes every line once and throws [FormatException] unless every minute
  /// is 0 to 2879, the core columns strictly increase on every day, no line
  /// crosses 1 January or leaves coverage, and no two lines of one locality
  /// share a day.
  void validateAllRows() {
    for (final lines in _lines) {
      _RowLine? previous;
      for (final line in lines) {
        _days(line);
        if (previous != null &&
            previous.firstDay + previous.days!.length > line.firstDay) {
          throw FormatException(
              'two lines of ${_id(line)} share ${_dateOfDay(line.firstDay)}');
        }
        previous = line;
      }
    }
  }

  /// The first and last covered date.
  (DateComponents, DateComponents) get coverage =>
      (_header.coverageFrom, _header.coverageTo);

  List<PublishedColumn> get columns => _header.columns;

  /// The shadow factor of the published Asr: 1 or 2.
  int get asrShadow => _header.asrShadow;

  @override
  String get authority => _header.authority;

  @override
  String get revision => _header.revision.toString();

  @override
  Iterable<Locality> get localities =>
      _header.localities.map((record) => record.locality);

  @override
  Locality? locality(LocalityId id) => _record(id)?.locality;

  @override
  Locality? localityAt(Coordinates coordinates, DateComponents date) =>
      _resolveLocality(_header.localities, coordinates, date)?.locality;

  @override
  OfficialLookup lookup(Coordinates coordinates, DateComponents date,
      {LocalityId? localityId}) {
    final record = localityId == null
        ? _resolveLocality(_header.localities, coordinates, date)
        : _record(localityId);
    if (record == null) return const NoLocality();
    final day = _dayNumber(date);
    final line = _lineCovering(
        _lines[_header.localityIndex[record.locality.id.value]!], day);
    if (line == null) return NoRow(record.locality);
    return OfficialRow._(
        locality: record.locality,
        date: date,
        authority: authority,
        revision: revision,
        asrShadow: asrShadow,
        columns: columns,
        minutes: line.days![day - line.firstDay],
        offsetMinutes: _header.zones[record.zone].offsetOn(day));
  }

  _LocalityRecord? _record(LocalityId id) {
    final index = _header.localityIndex[id.value];
    return index == null ? null : _header.localities[index];
  }

  _RowLine? _lineCovering(List<_RowLine> lines, int day) {
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].firstDay <= day) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return null;
    final line = lines[low - 1];
    return day - line.firstDay < _days(line).length ? line : null;
  }

  List<List<int>> _days(_RowLine line) {
    final cached = line.days;
    if (cached != null) return cached;
    final List<List<int>> days;
    try {
      days = decodeCells(
          String.fromCharCodes(_bytes, line.cellsStart, line.cellsEnd),
          _header.columns.length);
    } on FormatException catch (error) {
      throw FormatException('${error.message} in ${_label(line)}');
    }
    for (final day in days) {
      for (var i = 1; i < _header.coreIndices.length; i++) {
        if (day[_header.coreIndices[i]] <= day[_header.coreIndices[i - 1]]) {
          throw FormatException(
              'core columns are not increasing in ${_label(line)}');
        }
      }
    }
    final lastDay = line.firstDay + days.length - 1;
    if (_dateOfDay(lastDay).year != line.year) {
      throw FormatException('${_label(line)} crosses 1 January');
    }
    if (lastDay > _header.lastDay) {
      throw FormatException('${_label(line)} ends after coverage');
    }
    return line.days = days;
  }

  String _id(_RowLine line) =>
      _header.localities[line.locality].locality.id.value;

  String _label(_RowLine line) =>
      'the row of ${_id(line)} starting ${_dateOfDay(line.firstDay)}';
}
