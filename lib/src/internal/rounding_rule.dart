import '../data/time_components.dart';
import '../rounding.dart';

enum MinuteRounding { nearest, up, down, none }

enum TimePrecision { wholeSeconds, microseconds }

final class RoundingRule {
  final TimePrecision _precision;
  final MinuteRounding _start;
  final MinuteRounding _sunrise;

  const RoundingRule._(this._precision, this._start, this._sunrise);

  factory RoundingRule.of(Rounding rounding) => switch (rounding) {
        Rounding.nearest => const RoundingRule._(TimePrecision.wholeSeconds,
            MinuteRounding.nearest, MinuteRounding.nearest),
        Rounding.up => const RoundingRule._(
            TimePrecision.wholeSeconds, MinuteRounding.up, MinuteRounding.up),
        Rounding.none => const RoundingRule._(TimePrecision.wholeSeconds,
            MinuteRounding.none, MinuteRounding.none),
        Rounding.startsUpSunriseDown => const RoundingRule._(
            TimePrecision.microseconds, MinuteRounding.up, MinuteRounding.down),
      };

  DateTime? instant(DateTime midnight, double hours) {
    if (hours.isNaN || hours.isInfinite) {
      return null;
    }
    return switch (_precision) {
      TimePrecision.wholeSeconds =>
        TimeComponents.fromDouble(hours).dateComponents(midnight),
      TimePrecision.microseconds => midnight.add(Duration(
          microseconds: (hours * Duration.microsecondsPerHour).floor())),
    };
  }

  DateTime start(DateTime when) => _rounded(when, _start);

  DateTime sunrise(DateTime when) => _rounded(when, _sunrise);

  DateTime _rounded(DateTime when, MinuteRounding direction) {
    final exact = when.microsecondsSinceEpoch;
    final kept = switch (_precision) {
      TimePrecision.wholeSeconds =>
        exact - exact % Duration.microsecondsPerSecond,
      TimePrecision.microseconds => exact,
    };
    final past = kept % Duration.microsecondsPerMinute;
    final minute = kept - past;
    final rounded = switch (direction) {
      MinuteRounding.nearest => past >= 30 * Duration.microsecondsPerSecond
          ? minute + Duration.microsecondsPerMinute
          : minute,
      MinuteRounding.up =>
        past > 0 ? minute + Duration.microsecondsPerMinute : minute,
      MinuteRounding.down => minute,
      MinuteRounding.none => kept,
    };
    return DateTime.fromMicrosecondsSinceEpoch(rounded, isUtc: when.isUtc);
  }
}
