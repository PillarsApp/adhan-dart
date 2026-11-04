/// How the time at which the sun reaches a given altitude (sunrise, sunset,
/// Fajr, Isha and Asr) is corrected, and how strictly the resulting times are
/// validated.
enum HourAngleCorrection {
  /// Repeats the hour angle correction until it converges or ten passes have
  /// run, rejects an Asr angle the sun does not reach that day, treats a day
  /// whose times come out of order, or less than five minutes apart, as one
  /// whose times cannot be computed, and at longitudes near 180 degrees picks
  /// the solar transit nearest the longitude's mean noon, so the times of
  /// consecutive days never jump by a day. This is the default.
  iterative,

  /// Applies the hour angle correction once and keeps every time it produces,
  /// as versions before 2.4.0 did.
  ///
  /// The two values differ most where the sun's altitude changes slowly.
  /// Measured for 2026 with the default `highLatitudeRule`,
  /// `middle_of_the_night`: Isha at London under `muslim_world_league`
  /// differs by 4 minutes on 16 July, Isha at Reykjavik under `north_america`
  /// by 41 minutes on 25 August, and Isha at Edmonton with 18 degree Fajr and
  /// Isha angles by 43 minutes on 13 May. With `seventh_of_the_night`, which
  /// [HighLatitudeRule.recommended] picks above 48 degrees, those three
  /// places do not differ on any day of 2026. At Tromso, Asr under
  /// `muslim_world_league` differs by 50 minutes on 21 January and Fajr under
  /// `moon_sighting_committee` by 116 minutes on 17 May, under either rule.
  ///
  /// [singlePass] also keeps the choice of day that versions before 2.4.0
  /// made at longitudes near 180 degrees, so on some days its times fall a
  /// day apart from those [iterative] returns. In 2026 that happens at Suva
  /// from 20 September to 12 December, where [singlePass] returns the next
  /// local day's times, and at the Chatham Islands from 4 to 19 February,
  /// where [iterative] returns the next local day's times as it does there on
  /// every other day.
  ///
  /// With the default `polarCircleResolution`, `aqrabBalad`, [singlePass] can
  /// return times out of order on polar days, because the search keeps the
  /// first latitude whose times compute without checking their order. At
  /// Tromso, on 162 of the 2,190 day and method pairs of the 2026 parity grid
  /// in `tool/parity/`, where versions before 2.4.0 threw, it returns Asr
  /// before Dhuhr or Maghrib before Asr. Set `polarCircleResolution` to
  /// `unresolved` as well to keep the behavior of those versions.
  singlePass,
}
