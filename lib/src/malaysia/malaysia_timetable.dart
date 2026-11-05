import '../calculation_parameters.dart';
import '../coordinates.dart';
import '../data/calendar_util.dart';
import '../data/date_components.dart';
import '../data/malaysia_times_codec.dart';
import '../data/malaysia_times_data.dart';
import '../internal/day_times.dart';
import '../internal/present.dart';
import '../internal/shadow_length.dart';
import '../internal/solar_time.dart';
import '../madhab.dart';
import '../prayer_times_source.dart';
import 'malaysia_zones.dart';

const Duration _malaysiaOffset = Duration(hours: 8);

enum _Column { imsak, subuh, syuruk, dhuha, zohor, asar, maghrib, isyak }

DateTime _instant(DateTime midnight, int minuteOfDay) =>
    midnight.add(Duration(minutes: minuteOfDay)).subtract(_malaysiaOffset);

/// One day of the official Malaysian timetable for a zone, as published and
/// after the reviewed corrections to it.
class MalaysiaDay {
  final MalaysiaZone zone;

  final DateComponents date;

  /// Imsak, the end of the pre-dawn meal.
  final DateTime imsak;

  /// Subuh, the dawn prayer.
  final DateTime subuh;

  /// Syuruk, sunrise.
  final DateTime syuruk;

  /// Dhuha, the forenoon prayer.
  final DateTime dhuha;

  /// Zohor, the noon prayer.
  final DateTime zohor;

  /// Asar, the afternoon prayer as published and corrected, by the Shafi rule.
  final DateTime asar;

  /// Maghrib, the sunset prayer.
  final DateTime maghrib;

  /// Isyak, the night prayer.
  final DateTime isyak;

  MalaysiaDay._(
      this.zone, DateTime midnight, List<int> minutes, Duration? utcOffset)
      : date = DateComponents.from(midnight),
        imsak = present(
            _instant(midnight, minutes[_Column.imsak.index]), utcOffset),
        subuh = present(
            _instant(midnight, minutes[_Column.subuh.index]), utcOffset),
        syuruk = present(
            _instant(midnight, minutes[_Column.syuruk.index]), utcOffset),
        dhuha = present(
            _instant(midnight, minutes[_Column.dhuha.index]), utcOffset),
        zohor = present(
            _instant(midnight, minutes[_Column.zohor.index]), utcOffset),
        asar =
            present(_instant(midnight, minutes[_Column.asar.index]), utcOffset),
        maghrib = present(
            _instant(midnight, minutes[_Column.maghrib.index]), utcOffset),
        isyak = present(
            _instant(midnight, minutes[_Column.isyak.index]), utcOffset);

  /// The revision of the embedded data the row came from.
  String get revision => MalaysiaTimetable.revision;

  /// Always official, because a day exists only for a published row.
  PrayerTimesSource get source => PrayerTimesSource.official;
}

/// The official Malaysian prayer timetable embedded in this package.
class MalaysiaTimetable {
  MalaysiaTimetable._();

  /// The revision of the embedded data: the first eight hexadecimal digits of
  /// the SHA-256 of the times file, a hyphen, and the same for the zones file.
  /// Update it with every data release; the revision test fails when it is
  /// stale.
  static const String revision = 'badfebbb-714bce11';

  static final Map<String, _ZoneYearLine> _lines = _index();

  static Map<String, _ZoneYearLine> _index() {
    final lines = <String, _ZoneYearLine>{};
    var start = 0;
    while (start < malaysiaTimesData.length) {
      final end = malaysiaTimesData.indexOf('\n', start);
      final header = malaysiaTimesData.indexOf(
          ' ', malaysiaTimesData.indexOf(' ', start) + 1);
      lines[malaysiaTimesData.substring(start, header)] =
          _ZoneYearLine(start, end);
      start = end + 1;
    }
    return lines;
  }

  /// The published row for [zone] on [date], or null when the embedded data
  /// has no row for that zone and year.
  ///
  /// Times are host local when [utcOffset] is null, else UTC plus the offset,
  /// as `PrayerTimes` presents them.
  static MalaysiaDay? day(MalaysiaZone zone, DateComponents date,
      {Duration? utcOffset}) {
    final midnight = CalendarUtil.resolveTimeByDateComponents(date);
    final row = _row(zone, midnight);
    return row == null ? null : MalaysiaDay._(zone, midnight, row, utcOffset);
  }

  static List<int>? _row(MalaysiaZone zone, DateTime midnight) {
    final line = _lines['${zone.code} ${midnight.year}'];
    if (line == null) return null;
    return line.days[midnight.difference(DateTime.utc(midnight.year)).inDays];
  }
}

class _ZoneYearLine {
  final int start;
  final int end;
  List<List<int>>? _days;

  _ZoneYearLine(this.start, this.end);

  List<List<int>> get days => _days ??=
      decodeMalaysiaTimes(malaysiaTimesData.substring(start, end)).single.days;
}

class MalaysiaOfficialTimes {
  final DayTimes? times;
  final PrayerTimesSource source;
  final MalaysiaZone? zone;
  final MalaysiaDay? day;

  MalaysiaOfficialTimes._(this.times, this.source, this.zone, this.day);

  static MalaysiaOfficialTimes lookup(
      Coordinates coordinates,
      DateTime midnight,
      CalculationParameters parameters,
      Duration? utcOffset) {
    final code = parameters.malaysiaZone;
    final zone = code == null
        ? MalaysiaZones.resolve(coordinates, DateComponents.from(midnight))
        : MalaysiaZones.zone(code);
    if (zone == null) {
      return MalaysiaOfficialTimes._(
          null, PrayerTimesSource.calculatedNoZone, null, null);
    }
    final row = MalaysiaTimetable._row(zone, midnight);
    if (row == null) {
      return MalaysiaOfficialTimes._(
          null, PrayerTimesSource.calculatedNoRow, zone, null);
    }
    final adjustments = parameters.adjustments;
    var asr = adjustments.asr;
    if (parameters.madhab == Madhab.hanafi) {
      final solar = SolarTime(
          midnight, zone.referencePoint, parameters.hourAngleCorrection);
      asr += ((solar.afternoon(ShadowLength.double) -
                  solar.afternoon(ShadowLength.single)) *
              60)
          .round();
    }
    DateTime at(_Column column, int minutes) =>
        _instant(midnight, row[column.index] + minutes);
    return MalaysiaOfficialTimes._(
        DayTimes(
            fajr: at(_Column.subuh, adjustments.fajr),
            sunrise: at(_Column.syuruk, adjustments.sunrise),
            dhuhr: at(_Column.zohor, adjustments.dhuhr),
            asr: at(_Column.asar, asr),
            maghrib: at(_Column.maghrib, adjustments.maghrib),
            isha: at(_Column.isyak, adjustments.isha)),
        PrayerTimesSource.official,
        zone,
        MalaysiaDay._(zone, midnight, row, utcOffset));
  }
}
