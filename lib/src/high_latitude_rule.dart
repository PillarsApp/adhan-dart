import 'coordinates.dart';

/// Rules for dealing with Fajr and Isha at places with high latitudes
enum HighLatitudeRule {
  /// Fajr will never be earlier than the middle of the night, and Isha will never be later than
  /// the middle of the night.
  middle_of_the_night,

  /// Fajr will never be earlier than the beginning of the last seventh of the night, and Isha will
  /// never be later than the end of hte first seventh of the night.
  seventh_of_the_night,

  /// Similar to [HighLatitudeRule.seventh_of_the_night], but instead of 1/7th, the faction
  /// of the night used is fajrAngle / 60 and ishaAngle/60.
  twilight_angle;

  /// The recommended rule for [coordinates]: [seventh_of_the_night] beyond
  /// 48 degrees from the equator in either hemisphere, [middle_of_the_night]
  /// otherwise.
  static HighLatitudeRule recommended(Coordinates coordinates) {
    return coordinates.latitude.abs() > 48
        ? HighLatitudeRule.seventh_of_the_night
        : HighLatitudeRule.middle_of_the_night;
  }
}
