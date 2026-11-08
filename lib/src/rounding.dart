/// How a computed time is rounded to the minute.
enum Rounding {
  /// Round to the nearest minute. 30 seconds and above round up.
  nearest,

  /// Round up to the next minute whenever the time has any seconds.
  up,

  /// Keep the computed seconds.
  none,

  /// Keep each computed time to the microsecond. Round sunrise down to its
  /// minute, and round every other time, sunnah times included, up to the next
  /// minute when any part of a minute is past it.
  startsUpSunriseDown,
}
