import '../data/date_components.dart';
import '../internal/present.dart';
import '../prayer_times_source.dart';
import '../published/published_timetable.dart';
import 'malaysia_zones.dart';

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

  MalaysiaDay._(OfficialRow row, Duration? utcOffset)
      : zone = MalaysiaZones.zone(row.locality.id.value)!,
        date = row.date,
        imsak = present(row.published(PublishedColumn.imsak)!, utcOffset),
        subuh = present(row.published(PublishedColumn.fajr)!, utcOffset),
        syuruk = present(row.published(PublishedColumn.sunrise)!, utcOffset),
        dhuha = present(row.published(PublishedColumn.dhuha)!, utcOffset),
        zohor = present(row.published(PublishedColumn.dhuhr)!, utcOffset),
        asar = present(row.published(PublishedColumn.asr)!, utcOffset),
        maghrib = present(row.published(PublishedColumn.maghrib)!, utcOffset),
        isyak = present(row.published(PublishedColumn.isha)!, utcOffset);

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

  /// The embedded data as a generic [OfficialTimetableSource].
  static const OfficialTimetableSource source = MalaysiaOfficialSource.instance;

  /// The published row for [zone] on [date], or null when the embedded data
  /// has no row for that zone and year.
  ///
  /// Times are host local when [utcOffset] is null, else UTC plus the offset,
  /// as `PrayerTimes` presents them.
  static MalaysiaDay? day(MalaysiaZone zone, DateComponents date,
      {Duration? utcOffset}) {
    final lookup = source.lookup(zone.referencePoint, date,
        localityId: LocalityId(zone.code));
    return lookup is OfficialRow ? MalaysiaDay._(lookup, utcOffset) : null;
  }
}
