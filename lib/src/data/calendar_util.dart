import '../rounding.dart';
import 'date_components.dart';

class CalendarUtil {
  /// Whether or not a year is a leap year (has 366 days)
  ///
  /// [year] the year
  /// return [bool] whether or not its a leap year
  static bool isLeapYear(int year) {
    return year % 4 == 0 && !(year % 100 == 0 && year % 400 != 0);
  }

  static DateTime roundedMinute(DateTime when,
      [Rounding rounding = Rounding.nearest]) {
    final utc = when.toUtc();
    final int minute;
    final int second;
    switch (rounding) {
      case Rounding.nearest:
        minute = utc.minute + (utc.second / 60).round();
        second = 0;
        break;
      case Rounding.up:
        minute = utc.minute + (utc.second / 60).ceil();
        second = 0;
        break;
      case Rounding.none:
        minute = utc.minute;
        second = utc.second;
        break;
    }
    final rounded =
        DateTime.utc(utc.year, utc.month, utc.day, utc.hour, minute, second);
    return when.isUtc ? rounded : rounded.toLocal();
  }

  /// Gets a UTC DateTime for the particular date
  ///
  /// [components] the date components
  /// return [DateTime] with a time set to 00:00:00 at utc
  static DateTime resolveTimeByDateComponents(DateComponents components) {
    return resolveTime(components.year, components.month, components.day);
  }

  /// Gets UTC DateTime for the particular date
  ///
  /// [year] the year
  /// [month] the month
  /// [day] the day
  /// return [DateTime] with a time set to 00:00:00 at utc
  static DateTime resolveTime(int year, int month, int day) {
    return DateTime.utc(year, month, day, 0, 0, 0);
  }
}
