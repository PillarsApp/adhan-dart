import 'dart:math';

import 'calculation_parameters.dart';
import 'coordinates.dart';
import 'internal/day_times.dart';

/// How prayer times are resolved for locations inside the polar circles, where
/// daylight or night may persist for more than 24 hours depending on the
/// season.
enum PolarCircleResolution {
  /// Finds the closest location, moving toward the equator at the same
  /// longitude, for which prayer times can be computed. This is the default.
  aqrabBalad,

  /// Finds the closest date, forward or backward, for which prayer times can
  /// be computed, and relabels its times onto the requested date.
  aqrabYaum,

  /// Leaves prayer times unresolved. [PrayerTimes] throws an [ArgumentError]
  /// when they cannot be computed.
  unresolved,
}

extension PolarCircleResolver on PolarCircleResolution {
  static const latitudeVariationStep = 0.5;

  static const maximumDaysSearched = 183;

  DayTimes? resolve(Coordinates coordinates, DateTime date,
      CalculationParameters parameters) {
    switch (this) {
      case PolarCircleResolution.aqrabYaum:
        return _nearestDay(coordinates, date, parameters);
      case PolarCircleResolution.aqrabBalad:
        return _nearestLatitude(coordinates, date, parameters);
      case PolarCircleResolution.unresolved:
        return null;
    }
  }

  static DayTimes? _nearestDay(Coordinates coordinates, DateTime date,
      CalculationParameters parameters) {
    for (var daysAdded = 1; daysAdded <= maximumDaysSearched; daysAdded++) {
      for (final direction in [1, -1]) {
        final offset = direction * daysAdded;
        final candidate = date.add(Duration(days: offset));
        final times = DayTimes.compute(coordinates, candidate, parameters);
        if (times != null) {
          return times.shifted(-offset);
        }
      }
    }
    return null;
  }

  static DayTimes? _nearestLatitude(Coordinates coordinates, DateTime date,
      CalculationParameters parameters) {
    var latitude = _towardEquator(coordinates.latitude);
    while (true) {
      final times = DayTimes.compute(
          Coordinates(latitude, coordinates.longitude), date, parameters);
      if (times != null) {
        return times;
      }
      if (latitude == 0) {
        return null;
      }
      latitude = _towardEquator(latitude);
    }
  }

  static double _towardEquator(double latitude) {
    final magnitude = max(0.0, latitude.abs() - latitudeVariationStep);
    return latitude.isNegative ? -magnitude : magnitude;
  }
}
