import '../calculation_method.dart';
import '../calculation_parameters.dart';
import '../coordinates.dart';
import '../data/calendar_util.dart';
import '../data/time_components.dart';
import '../extensions/datetime.dart';
import '../hour_angle_correction.dart';
import '../madhab.dart';
import '../rounding.dart';
import 'solar_time.dart';

/// The six times of one day, as UTC instants with adjustments and rounding
/// applied, computed from that day's own solar geometry.
class DayTimes {
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  const DayTimes({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  static const minimumPrayerGap = Duration(minutes: 5);

  /// Whether [second] follows [first] by at least [minimumPrayerGap].
  static bool timesInOrder(DateTime? first, DateTime? second) {
    if (first == null || second == null) {
      return false;
    }
    return second.difference(first) >= minimumPrayerGap;
  }

  /// The same times moved by a whole number of days, used to relabel a polar
  /// circle result onto the requested date.
  DayTimes shifted(int days) {
    if (days == 0) {
      return this;
    }
    final offset = Duration(days: days);
    return DayTimes(
      fajr: fajr.add(offset),
      sunrise: sunrise.add(offset),
      dhuhr: dhuhr.add(offset),
      asr: asr.add(offset),
      maghrib: maghrib.add(offset),
      isha: isha.add(offset),
    );
  }

  /// Computes the times for [date], a UTC midnight, with no polar circle
  /// resolution. Returns null when a time cannot be computed or, under
  /// [HourAngleCorrection.iterative], when the times come out of order.
  static DayTimes? compute(Coordinates coordinates, DateTime date,
      CalculationParameters parameters) {
    final correction = parameters.hourAngleCorrection;
    final solarTime = SolarTime(date, coordinates, correction);
    final tomorrow = date.add(Duration(days: 1));
    final tomorrowSolarTime = SolarTime(tomorrow, coordinates, correction);

    final sunrise = _time(date, solarTime.sunrise);
    final sunset = _time(date, solarTime.sunset);
    final transit = _time(date, solarTime.transit);
    final tomorrowSunrise = _time(tomorrow, tomorrowSolarTime.sunrise);
    if (sunrise == null ||
        sunset == null ||
        transit == null ||
        tomorrowSunrise == null) {
      return null;
    }

    final asr =
        _time(date, solarTime.afternoon(parameters.madhab.getShadowLength()));

    final night = tomorrowSunrise.difference(sunset);
    final year = date.year;
    final dayOfYear = date.dayOfYear;
    final latitude = coordinates.latitude;
    final moonsighting =
        parameters.method == CalculationMethod.moon_sighting_committee;
    final nightPortions = parameters.nightPortions();

    var fajr = _time(date, solarTime.hourAngle(-parameters.fajrAngle, false));
    if (moonsighting && latitude >= 55) {
      fajr = sunrise.subtract(_fraction(night, 1 / 7));
    }
    final safeFajr = moonsighting
        ? _seasonAdjustedMorningTwilight(latitude, dayOfYear, year, sunrise)
        : sunrise.subtract(_fraction(night, nightPortions.fajr));
    if (fajr == null ||
        fajr.isBefore(safeFajr) ||
        (correction.validatesTimes && !timesInOrder(fajr, sunrise))) {
      fajr = safeFajr;
    }

    DateTime isha;
    if (parameters.ishaInterval > 0) {
      isha = sunset.add(Duration(minutes: parameters.ishaInterval));
    } else {
      final ishaAngle = parameters.ishaAngle;
      DateTime? angleIsha;
      if (ishaAngle != null) {
        angleIsha = _time(date, solarTime.hourAngle(-ishaAngle, true));
      }
      if (moonsighting && latitude >= 55) {
        angleIsha = sunset.add(_fraction(night, 1 / 7));
      }
      final safeIsha = moonsighting
          ? _seasonAdjustedEveningTwilight(latitude, dayOfYear, year, sunset)
          : sunset.add(_fraction(night, nightPortions.isha));
      if (angleIsha == null ||
          (correction.validatesTimes && !timesInOrder(sunset, angleIsha)) ||
          angleIsha.isAfter(safeIsha)) {
        angleIsha = safeIsha;
      }
      isha = angleIsha;
    }

    var maghrib = sunset;
    final maghribAngle = parameters.maghribAngle;
    if (maghribAngle != null) {
      final angleMaghrib =
          _time(date, solarTime.hourAngle(-maghribAngle, true));
      if (angleMaghrib != null &&
          sunset.isBefore(angleMaghrib) &&
          isha.isAfter(angleMaghrib)) {
        maghrib = angleMaghrib;
      }
    }

    if (correction.validatesTimes &&
        !(timesInOrder(fajr, sunrise) &&
            timesInOrder(sunrise, transit) &&
            timesInOrder(transit, asr) &&
            timesInOrder(asr, maghrib) &&
            timesInOrder(maghrib, isha))) {
      return null;
    }
    if (asr == null) {
      return null;
    }

    final adjustments = parameters.adjustments;
    final methodAdjustments = parameters.methodAdjustments;
    final rounding = parameters.rounding;
    return DayTimes(
      fajr: _finish(fajr, adjustments.fajr, methodAdjustments.fajr, rounding),
      sunrise: _finish(
          sunrise, adjustments.sunrise, methodAdjustments.sunrise, rounding),
      dhuhr: _finish(
          transit, adjustments.dhuhr, methodAdjustments.dhuhr, rounding),
      asr: _finish(asr, adjustments.asr, methodAdjustments.asr, rounding),
      maghrib: _finish(
          maghrib, adjustments.maghrib, methodAdjustments.maghrib, rounding),
      isha: _finish(isha, adjustments.isha, methodAdjustments.isha, rounding),
    );
  }

  static DateTime? _time(DateTime date, double hours) {
    if (hours.isNaN || hours.isInfinite) {
      return null;
    }
    return TimeComponents.fromDouble(hours).dateComponents(date);
  }

  static Duration _fraction(Duration night, double portion) {
    return Duration(seconds: (portion * night.inMilliseconds) ~/ 1000);
  }

  static DateTime _finish(
      DateTime time, int adjustment, int methodAdjustment, Rounding rounding) {
    return CalendarUtil.roundedMinute(
        time.add(Duration(minutes: adjustment + methodAdjustment)), rounding);
  }

  static DateTime _seasonAdjustedMorningTwilight(
      double latitude, int day, int year, DateTime sunrise) {
    final a = 75 + ((28.65 / 55.0) * (latitude).abs());
    final b = 75 + ((19.44 / 55.0) * (latitude).abs());
    final c = 75 + ((32.74 / 55.0) * (latitude).abs());
    final d = 75 + ((48.10 / 55.0) * (latitude).abs());

    final adjustment =
        _seasonAdjustment(a, b, c, d, daysSinceSolstice(day, year, latitude));
    return sunrise.add(Duration(seconds: -(adjustment * 60.0).round()));
  }

  static DateTime _seasonAdjustedEveningTwilight(
      double latitude, int day, int year, DateTime sunset) {
    final a = 75 + ((25.60 / 55.0) * (latitude).abs());
    final b = 75 + ((2.050 / 55.0) * (latitude).abs());
    final c = 75 - ((9.210 / 55.0) * (latitude).abs());
    final d = 75 + ((6.140 / 55.0) * (latitude).abs());

    final adjustment =
        _seasonAdjustment(a, b, c, d, daysSinceSolstice(day, year, latitude));
    return sunset.add(Duration(seconds: (adjustment * 60.0).round()));
  }

  static double _seasonAdjustment(
      double a, double b, double c, double d, int dyy) {
    if (dyy < 91) {
      return a + (b - a) / 91.0 * dyy;
    } else if (dyy < 137) {
      return b + (c - b) / 46.0 * (dyy - 91);
    } else if (dyy < 183) {
      return c + (d - c) / 46.0 * (dyy - 137);
    } else if (dyy < 229) {
      return d + (c - d) / 46.0 * (dyy - 183);
    } else if (dyy < 275) {
      return c + (b - c) / 46.0 * (dyy - 229);
    } else {
      return b + (a - b) / 91.0 * (dyy - 275);
    }
  }

  static int daysSinceSolstice(int dayOfYear, int year, double latitude) {
    int daysSinceSolistice;
    final northernOffset = 10;
    final isLeapYear = CalendarUtil.isLeapYear(year);
    final southernOffset = isLeapYear ? 173 : 172;
    final daysInYear = isLeapYear ? 366 : 365;

    if (latitude >= 0) {
      daysSinceSolistice = dayOfYear + northernOffset;
      if (daysSinceSolistice >= daysInYear) {
        daysSinceSolistice = daysSinceSolistice - daysInYear;
      }
    } else {
      daysSinceSolistice = dayOfYear - southernOffset;
      if (daysSinceSolistice < 0) {
        daysSinceSolistice = daysSinceSolistice + daysInYear;
      }
    }
    return daysSinceSolistice;
  }
}
