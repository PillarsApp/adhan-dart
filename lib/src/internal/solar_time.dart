import 'dart:math';

import '../coordinates.dart';
import 'astronomical.dart';
import 'calendrical_helper.dart';
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

  SolarTime(DateTime _today, Coordinates coordinates,
      {bool preserveSolarDate = false}) {
    final today = _today;

    final tomorrow = today.add(Duration(days: 1));

    final yesterday = today.subtract(Duration(days: 1));

    _prevSolar = SolarCoordinates(CalendricalHelper.julianDayByDate(yesterday));
    _solar = SolarCoordinates(CalendricalHelper.julianDayByDate(today));
    _nextSolar = SolarCoordinates(CalendricalHelper.julianDayByDate(tomorrow));

    _approximateTransit = Astronomical.approximateTransit(coordinates.longitude,
        _solar.apparentSiderealTime, _solar.rightAscension);
    if (preserveSolarDate) {
      // Keep solar noon on the requested local solar date across the date line.
      final expectedTransit = 0.5 - coordinates.longitude / 360;
      if (_approximateTransit - expectedTransit > 0.5) {
        _approximateTransit -= 1;
      } else if (expectedTransit - _approximateTransit > 0.5) {
        _approximateTransit += 1;
      }
    }
    final solarAltitude = -50.0 / 60.0;

    _observer = coordinates;
    _transit = Astronomical.correctedTransit(
        _approximateTransit,
        coordinates.longitude,
        _solar.apparentSiderealTime,
        _solar.rightAscension,
        _prevSolar.rightAscension,
        _nextSolar.rightAscension);
    _sunrise = Astronomical.correctedHourAngle(
        _approximateTransit,
        solarAltitude,
        coordinates,
        false,
        _solar.apparentSiderealTime,
        _solar.rightAscension,
        _prevSolar.rightAscension,
        _nextSolar.rightAscension,
        _solar.declination,
        _prevSolar.declination,
        _nextSolar.declination);
    _sunset = Astronomical.correctedHourAngle(
        _approximateTransit,
        solarAltitude,
        coordinates,
        true,
        _solar.apparentSiderealTime,
        _solar.rightAscension,
        _prevSolar.rightAscension,
        _nextSolar.rightAscension,
        _solar.declination,
        _prevSolar.declination,
        _nextSolar.declination);
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
        _nextSolar.declination);
  }

  /// Brackets the nightly minimum before solving twilight near tangency.
  /// Used only by Wifaqul; the legacy single-correction solver is unchanged.
  double twilightHourAngle(double angle, bool afterTransit) {
    if (!angle.isFinite ||
        !_transit.isFinite ||
        !_observer.latitude.isFinite ||
        !_observer.longitude.isFinite ||
        !_solar.apparentSiderealTime.isFinite ||
        !_solar.rightAscension.isFinite ||
        !_prevSolar.rightAscension.isFinite ||
        !_nextSolar.rightAscension.isFinite ||
        !_solar.declination.isFinite ||
        !_prevSolar.declination.isFinite ||
        !_nextSolar.declination.isFinite) {
      return double.nan;
    }
    var left = _transit + (afterTransit ? 11 : -13);
    var right = _transit + (afterTransit ? 13 : -11);
    for (var iteration = 0; iteration < 32; iteration++) {
      final first = left + (right - left) / 3;
      final second = right - (right - left) / 3;
      final firstAltitude = _twilightAltitude(first);
      final secondAltitude = _twilightAltitude(second);
      if (!firstAltitude.isFinite || !secondAltitude.isFinite) {
        return double.nan;
      }
      if (firstAltitude < secondAltitude) {
        right = second;
      } else {
        left = first;
      }
    }
    final minimum = (left + right) / 2;
    final minimumAltitude = _twilightAltitude(minimum);
    final transitAltitude = _twilightAltitude(_transit);
    if (!minimumAltitude.isFinite ||
        !transitAltitude.isFinite ||
        minimumAltitude > angle ||
        transitAltitude < angle) {
      return double.nan;
    }
    left = afterTransit ? _transit : minimum;
    right = afterTransit ? minimum : _transit;
    while ((right - left) * 3600 > 0.05) {
      final midpoint = (left + right) / 2;
      final altitude = _twilightAltitude(midpoint);
      if (!altitude.isFinite) return double.nan;
      if ((altitude < angle) == afterTransit) {
        right = midpoint;
      } else {
        left = midpoint;
      }
    }
    return (left + right) / 2;
  }

  double _twilightAltitude(double hours) {
    final fraction = hours / 24;
    final rightAscension = Astronomical.interpolateAngles(_solar.rightAscension,
        _prevSolar.rightAscension, _nextSolar.rightAscension, fraction);
    final declination = Astronomical.interpolate(_solar.declination,
        _prevSolar.declination, _nextSolar.declination, fraction);
    final hourAngle = _solar.apparentSiderealTime +
        360.985647 * fraction +
        _observer.longitude -
        rightAscension;
    return Astronomical.altitudeOfCelestialBody(
        _observer.latitude, declination, hourAngle);
  }

  // hours from transit
  double afternoon(ShadowLength shadowLength) {
    // TODO (from Swift version) source shadow angle calculation
    final tangent = (_observer.latitude - _solar.declination).abs();
    final inverse = shadowLength.getShadowLength() + tan(radians(tangent));
    final angle = degrees(atan(1.0 / inverse));

    return hourAngle(angle, true);
  }
}
