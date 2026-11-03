import 'dart:math';

import '../coordinates.dart';
import '../data/time_components.dart';
import '../hour_angle_correction.dart';
import 'astronomical.dart';
import 'calendrical_helper.dart';
import 'hour_angle_correction_rules.dart';
import 'math.dart';
import 'shadow_length.dart';
import 'solar_coordinates.dart';

class SolarTime {
  late double _transit;
  double get transit => _transit;

  late double _sunrise;
  double get sunrise => _sunrise;

  late double _sunset;
  double get sunset => _sunset;

  late Coordinates _observer;
  late SolarCoordinates _solar;
  late SolarCoordinates _prevSolar;
  late SolarCoordinates _nextSolar;
  late double _approximateTransit;
  final HourAngleCorrection _hourAngleCorrection;

  SolarTime(DateTime _today, Coordinates coordinates,
      [this._hourAngleCorrection = HourAngleCorrection.iterative]) {
    final today = _today;

    final tomorrow = today.add(Duration(days: 1));

    final yesterday = today.subtract(Duration(days: 1));

    _prevSolar = SolarCoordinates(CalendricalHelper.julianDayByDate(yesterday));
    _solar = SolarCoordinates(CalendricalHelper.julianDayByDate(today));
    _nextSolar = SolarCoordinates(CalendricalHelper.julianDayByDate(tomorrow));

    _approximateTransit = Astronomical.approximateTransit(coordinates.longitude,
        _solar.apparentSiderealTime, _solar.rightAscension);
    final solarAltitude = -50.0 / 60.0;

    _observer = coordinates;
    _transit = Astronomical.correctedTransit(
        _approximateTransit,
        coordinates.longitude,
        _solar.apparentSiderealTime,
        _solar.rightAscension,
        _prevSolar.rightAscension,
        _nextSolar.rightAscension);
    _sunrise = hourAngle(solarAltitude, false);
    _sunset = hourAngle(solarAltitude, true);
  }

  double hourAngle(double angle, bool afterTransit) {
    return Astronomical.correctedHourAngle(
        _approximateTransit,
        angle,
        _observer,
        afterTransit,
        _solar.apparentSiderealTime,
        _solar.rightAscension,
        _prevSolar.rightAscension,
        _nextSolar.rightAscension,
        _solar.declination,
        _prevSolar.declination,
        _nextSolar.declination,
        correction: _hourAngleCorrection);
  }

  double afternoon(ShadowLength shadowLength) {
    final tangent = (_observer.latitude - _solar.declination).abs();
    final inverse = shadowLength.getShadowLength() + tan(radians(tangent));
    final angle = degrees(atan(1.0 / inverse));

    if (!_hourAngleCorrection.validatesTimes) {
      return hourAngle(angle, true);
    }

    const solarAngularDiameter = 32.0 / 60.0;
    if (angle <= solarAngularDiameter / 2) {
      return double.nan;
    }

    final maxAltitude = Astronomical.altitudeOfCelestialBody(
        _observer.latitude, _solar.declination, 0);
    if (maxAltitude < angle) {
      return double.nan;
    }

    final result = hourAngle(angle, true);
    if (!result.isFinite || _wholeSeconds(result) <= _wholeSeconds(_transit)) {
      return double.nan;
    }
    return result;
  }

  static int _wholeSeconds(double hours) {
    final components = TimeComponents.fromDouble(hours);
    return components.hours * 3600 +
        components.minutes * 60 +
        components.seconds;
  }
}
