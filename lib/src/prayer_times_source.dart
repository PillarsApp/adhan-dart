/// Where a set of prayer times came from.
enum PrayerTimesSource {
  /// Computed from the sun's position with the method's parameters.
  calculated,

  /// Read from a published timetable.
  official,

  /// Computed because no official zone covers the coordinates, or the manual
  /// zone code names no zone in the data.
  calculatedNoZone,

  /// Computed because the official zone is known but the data has no row for
  /// the date.
  calculatedNoRow;

  bool get isOfficial => this == PrayerTimesSource.official;
}
