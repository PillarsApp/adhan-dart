import 'date_components.dart';

class CalendarUtil {
  /// Whether or not a year is a leap year (has 366 days)
  ///
  /// [year] the year
  /// return [bool] whether or not its a leap year
  static bool isLeapYear(int year) {
    return year % 4 == 0 && !(year % 100 == 0 && year % 400 != 0);
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
