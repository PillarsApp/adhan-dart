import 'prayer_times.dart';
import 'data/calendar_util.dart';
import 'data/date_components.dart';
import 'internal/rounding_rule.dart';

class SunnahTimes {
  /// The midpoint between Maghrib and Fajr
  late DateTime _middleOfTheNight;

  /// The midpoint between Maghrib and Fajr
  DateTime get middleOfTheNight => _middleOfTheNight;

  /// The beginning of the last third of the period between Maghrib and Fajr,
  /// a recommended time to perform Qiyam
  late DateTime _lastThirdOfTheNight;

  /// The beginning of the last third of the period between Maghrib and Fajr,
  /// a recommended time to perform Qiyam
  DateTime get lastThirdOfTheNight => _lastThirdOfTheNight;

  /// Calculate SunnahTimes with PrayerTimes instance.
  ///
  /// [prayerTimes] a PrayerTimes instance
  SunnahTimes(PrayerTimes prayerTimes) {
    final currentPrayerTimesDate =
        CalendarUtil.resolveTimeByDateComponents(prayerTimes.dateComponents);
    final tomorrowPrayerTimesDate =
        currentPrayerTimesDate.add(Duration(days: 1));
    final tomorrowPrayerTimes = PrayerTimes(
        prayerTimes.coordinates,
        DateComponents.from(tomorrowPrayerTimesDate),
        prayerTimes.calculationParameters,
        utcOffset: prayerTimes.utcOffset);

    final night = tomorrowPrayerTimes.fajr.difference(prayerTimes.maghrib);
    final rule = RoundingRule.of(prayerTimes.calculationParameters.rounding);

    _middleOfTheNight = rule.start(prayerTimes.maghrib
        .add(Duration(microseconds: night.inMicroseconds ~/ 2)));

    _lastThirdOfTheNight = rule.start(prayerTimes.maghrib
        .add(Duration(microseconds: night.inMicroseconds * 2 ~/ 3)));
  }
}
