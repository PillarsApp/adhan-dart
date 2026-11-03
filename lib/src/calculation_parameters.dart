import 'calculation_method.dart';
import 'high_latitude_rule.dart';
import 'hour_angle_correction.dart';
import 'madhab.dart';
import 'polar_circle_resolution.dart';
import 'prayer_adjustments.dart';
import 'rounding.dart';

/// Parameters used for PrayerTime calculation customization
///
/// Note that, for many cases, you can use [CalculationMethod.getParameters] to get a
/// pre-computed set of calculation parameters depending on one of the available
/// [CalculationMethod].
class CalculationParameters {
  /// The method used to do the calculation
  CalculationMethod method;

  /// The angle of the sun used to calculate fajr
  double fajrAngle;

  /// The angle of the sun used to calculate Maghrib
  double? maghribAngle;

  /// The angle of the sun used to calculate isha
  double? ishaAngle;

  /// Minutes after Maghrib (if set, the time for Isha will be Maghrib plus IshaInterval)
  int ishaInterval;

  /// The madhab used to calculate Asr
  Madhab madhab;

  /// Rules for placing bounds on Fajr and Isha for high latitude areas
  HighLatitudeRule highLatitudeRule;

  /// Used to optionally add or subtract a set amount of time from each prayer time
  PrayerAdjustments adjustments;

  /// Used for method adjustments
  PrayerAdjustments methodAdjustments;

  /// How each computed time is rounded to the minute
  Rounding rounding;

  /// How the hour angle correction runs and how strictly the times are validated
  HourAngleCorrection hourAngleCorrection;

  /// How days inside the polar circles without computable times are resolved
  PolarCircleResolution polarCircleResolution;

  /// The code of the official Malaysian zone to read, such as WLY01, when the
  /// method is [CalculationMethod.malaysia_official]. Null resolves the zone
  /// from the coordinates.
  String? malaysiaZone;

  CalculationParameters(
      {this.method = CalculationMethod.other,
      required this.fajrAngle,
      this.maghribAngle,
      this.ishaAngle,
      this.ishaInterval = 0,
      this.madhab = Madhab.shafi,
      this.highLatitudeRule = HighLatitudeRule.middle_of_the_night,
      PrayerAdjustments? adjustments,
      PrayerAdjustments? methodAdjustments,
      this.rounding = Rounding.nearest,
      this.hourAngleCorrection = HourAngleCorrection.iterative,
      this.polarCircleResolution = PolarCircleResolution.aqrabBalad,
      this.malaysiaZone})
      : adjustments = adjustments ?? PrayerAdjustments(),
        methodAdjustments = methodAdjustments ?? PrayerAdjustments();

  /// Set the method adjustments for the current calculation parameters
  /// [adjustments] the prayer adjustments
  /// return this calculation parameters instance
  CalculationParameters withMethodAdjustments(PrayerAdjustments adjustments) {
    methodAdjustments = adjustments;
    return this;
  }

  _NightPortions nightPortions() {
    switch (highLatitudeRule) {
      case HighLatitudeRule.middle_of_the_night:
        {
          return _NightPortions(1.0 / 2.0, 1.0 / 2.0);
        }
      case HighLatitudeRule.seventh_of_the_night:
        {
          return _NightPortions(1.0 / 7.0, 1.0 / 7.0);
        }
      case HighLatitudeRule.twilight_angle:
        {
          if (ishaAngle == null) {
            throw FormatException('ishaAngle\'s value isn\'t define');
          }
          return _NightPortions(fajrAngle / 60.0, ishaAngle! / 60.0);
        }
      default:
        {
          throw FormatException('Invalid high latitude rule');
        }
    }
  }
}

class _NightPortions {
  final double fajr;
  final double isha;

  _NightPortions(this.fajr, this.isha);
}
