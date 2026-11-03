/// How the time at which the sun reaches a given altitude (sunrise, sunset,
/// Fajr, Isha and Asr) is corrected, and how strictly the resulting times are
/// validated.
enum HourAngleCorrection {
  /// Repeats the hour angle correction until it converges or ten passes have
  /// run, rejects an Asr angle the sun does not reach that day, and treats a
  /// day whose times come out of order, or less than five minutes apart, as
  /// one whose times cannot be computed. This is the default.
  iterative,

  /// Applies the hour angle correction once and keeps every time it produces,
  /// without anchoring the transit to the longitude's mean noon, as versions
  /// before 2.4.0 did. Isha can differ from [iterative] by a few minutes above about 48
  /// degrees latitude.
  singlePass,
}
