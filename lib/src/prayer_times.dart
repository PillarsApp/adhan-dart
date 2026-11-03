import 'package:adhan/src/data/calendar_util.dart';

import 'calculation_method.dart';
import 'calculation_parameters.dart';
import 'coordinates.dart';
import 'data/date_components.dart';
import 'data/london_times_lookup.dart';
import 'internal/day_times.dart';
import 'internal/present.dart';
import 'malaysia/malaysia_timetable.dart';
import 'malaysia/malaysia_zones.dart';
import 'polar_circle_resolution.dart';
import 'prayer.dart';
import 'prayer_times_source.dart';

class PrayerTimes {
  late DateTime _fajr;
  DateTime get fajr => _fajr;

  late DateTime _sunrise;
  DateTime get sunrise => _sunrise;

  late DateTime _dhuhr;
  DateTime get dhuhr => _dhuhr;

  late DateTime _asr;
  DateTime get asr => _asr;

  late DateTime _maghrib;
  DateTime get maghrib => _maghrib;

  late DateTime _isha;
  DateTime get isha => _isha;

  late PrayerTimesSource _source;

  PrayerTimesSource get source => _source;

  MalaysiaZone? _malaysiaZone;

  /// The official Malaysian zone the times were read for, or would have been:
  /// the manual zone when its code is known, else the zone resolved from the
  /// coordinates. Null for every other method, for an unknown code and outside
  /// every zone.
  MalaysiaZone? get malaysiaZone => _malaysiaZone;

  MalaysiaDay? _malaysiaDay;

  /// The published row behind the times, before adjustments and the Hanafi
  /// shift, presented like the six times. Null unless [source] is official
  /// and the method is [CalculationMethod.malaysia_official].
  MalaysiaDay? get malaysiaDay => _malaysiaDay;

  // If you give a UTC Offset then Prayer Times will convert local(with device timezone) time
  // to UTC and then add the offset.
  final Duration? utcOffset;

  final Coordinates coordinates;

  late DateComponents _dateComponents;

  DateComponents get dateComponents => _dateComponents;

  final CalculationParameters calculationParameters;

  /// Calculate PrayerTimes and Output Local Times By Default.
  /// If you provide utcOffset then it will Output UTC with Offset Applied Times.
  ///
  /// [coordinates] the coordinates of the location
  /// [dateComponents] the date components for that location
  /// [calculationParameters] the parameters for the calculation
  factory PrayerTimes(Coordinates coordinates, DateComponents dateComponents,
      CalculationParameters calculationParameters,
      {Duration? utcOffset}) {
    return PrayerTimes._(
        coordinates,
        CalendarUtil.resolveTimeByDateComponents(dateComponents),
        calculationParameters,
        utcOffset: utcOffset);
  }

  /// Calculate Today's PrayerTimes and Output Local Times By Default.
  /// If you provide utcOffset then it will Output UTC with Offset Applied Times.
  ///
  /// [coordinates] the coordinates of the location
  /// [calculationParameters] the parameters for the calculation
  factory PrayerTimes.today(
      Coordinates coordinates, CalculationParameters calculationParameters,
      {Duration? utcOffset}) {
    return PrayerTimes._(
        coordinates,
        CalendarUtil.resolveTimeByDateComponents(
            DateComponents.from(DateTime.now())),
        calculationParameters,
        utcOffset: utcOffset);
  }

  /// Calculate PrayerTimes and Output UTC Times.
  ///
  /// [coordinates] the coordinates of the location
  /// [dateComponents] the date components for that location
  /// [calculationParameters] the parameters for the calculation
  factory PrayerTimes.utc(
      Coordinates coordinates,
      DateComponents dateComponents,
      CalculationParameters calculationParameters) {
    return PrayerTimes._(
        coordinates,
        CalendarUtil.resolveTimeByDateComponents(dateComponents),
        calculationParameters,
        utcOffset: Duration());
  }

  /// Calculate PrayerTimes and Output UTC with Offset Applied Times.
  ///
  /// [coordinates] the coordinates of the location
  /// [dateComponents] the date components for that location
  /// [calculationParameters] the parameters for the calculation
  factory PrayerTimes.utcOffset(
      Coordinates coordinates,
      DateComponents dateComponents,
      CalculationParameters calculationParameters,
      Duration utcOffset) {
    return PrayerTimes._(
        coordinates,
        CalendarUtil.resolveTimeByDateComponents(dateComponents),
        calculationParameters,
        utcOffset: utcOffset);
  }

  PrayerTimes._(this.coordinates, DateTime _date, this.calculationParameters,
      {this.utcOffset}) {
    final date = _date.toUtc();
    _dateComponents = DateComponents.from(date);

    // Special handling for London lookup times
    if (calculationParameters.method ==
        CalculationMethod.unified_london_times) {
      _source = PrayerTimesSource.official;
      _initializeFromLondonLookup(date);
      return;
    }

    _source = PrayerTimesSource.calculated;
    if (calculationParameters.method == CalculationMethod.malaysia_official) {
      final official = MalaysiaOfficialTimes.lookup(
          coordinates, date, calculationParameters, utcOffset);
      _source = official.source;
      _malaysiaZone = official.zone;
      _malaysiaDay = official.day;
      final times = official.times;
      if (times != null) {
        _assign(times);
        return;
      }
    }

    if (!(coordinates.latitude.abs() <= 90)) {
      throw ArgumentError.value(coordinates.latitude, 'latitude',
          'must be a number between -90 and 90');
    }
    final times = DayTimes.compute(coordinates, date, calculationParameters) ??
        calculationParameters.polarCircleResolution
            .resolve(coordinates, date, calculationParameters);
    if (times == null) {
      throw ArgumentError(
          'Prayer times cannot be computed at $coordinates on $_dateComponents');
    }
    _assign(times);
  }

  void _assign(DayTimes times) {
    _fajr = _present(times.fajr);
    _sunrise = _present(times.sunrise);
    _dhuhr = _present(times.dhuhr);
    _asr = _present(times.asr);
    _maghrib = _present(times.maghrib);
    _isha = _present(times.isha);
  }

  DateTime _present(DateTime utc) => present(utc, utcOffset);

  Prayer currentPrayer() {
    return currentPrayerByDateTime(DateTime.now());
  }

  Prayer currentPrayerByDateTime(DateTime time) {
    final when = time.millisecondsSinceEpoch;
    if (isha.millisecondsSinceEpoch - when <= 0) {
      return Prayer.isha;
    } else if (maghrib.millisecondsSinceEpoch - when <= 0) {
      return Prayer.maghrib;
    } else if (asr.millisecondsSinceEpoch - when <= 0) {
      return Prayer.asr;
    } else if (dhuhr.millisecondsSinceEpoch - when <= 0) {
      return Prayer.dhuhr;
    } else if (sunrise.millisecondsSinceEpoch - when <= 0) {
      return Prayer.sunrise;
    } else if (fajr.millisecondsSinceEpoch - when <= 0) {
      return Prayer.fajr;
    } else {
      return Prayer.none;
    }
  }

  Prayer nextPrayer() {
    return nextPrayerByDateTime(DateTime.now());
  }

  Prayer nextPrayerByDateTime(DateTime time) {
    final when = time.millisecondsSinceEpoch;
    if (isha.millisecondsSinceEpoch - when <= 0) {
      return Prayer.none;
    } else if (maghrib.millisecondsSinceEpoch - when <= 0) {
      return Prayer.isha;
    } else if (asr.millisecondsSinceEpoch - when <= 0) {
      return Prayer.maghrib;
    } else if (dhuhr.millisecondsSinceEpoch - when <= 0) {
      return Prayer.asr;
    } else if (sunrise.millisecondsSinceEpoch - when <= 0) {
      return Prayer.dhuhr;
    } else if (fajr.millisecondsSinceEpoch - when <= 0) {
      return Prayer.sunrise;
    } else {
      return Prayer.fajr;
    }
  }

  DateTime? timeForPrayer(Prayer prayer) {
    switch (prayer) {
      case Prayer.fajr:
        return fajr;
      case Prayer.sunrise:
        return sunrise;
      case Prayer.dhuhr:
        return dhuhr;
      case Prayer.asr:
        return asr;
      case Prayer.maghrib:
        return maghrib;
      case Prayer.isha:
        return isha;
      case Prayer.none:
      default:
        return null;
    }
  }

  static int daysSinceSolstice(int dayOfYear, int year, double latitude) {
    return DayTimes.daysSinceSolstice(dayOfYear, year, latitude);
  }

  /// Initialize prayer times from London lookup table
  void _initializeFromLondonLookup(DateTime date) {
    final dateComponents = DateComponents.from(date);
    final londonTimes = LondonTimesLookup.getTimesForDate(dateComponents);

    if (londonTimes == null) {
      throw ArgumentError(
          'No London prayer times available for date ${dateComponents.year}-${dateComponents.month.toString().padLeft(2, '0')}-${dateComponents.day.toString().padLeft(2, '0')}');
    }

    DateTime finish(String time, int adjustment, int methodAdjustment) {
      final utc = londonTimes.parseTime(time, dateComponents).toUtc();
      return _present(CalendarUtil.roundedMinute(
          utc.add(Duration(minutes: adjustment + methodAdjustment)),
          calculationParameters.rounding));
    }

    final adjustments = calculationParameters.adjustments;
    final methodAdjustments = calculationParameters.methodAdjustments;
    _fajr = finish(londonTimes.fajr, adjustments.fajr, methodAdjustments.fajr);
    _sunrise = finish(
        londonTimes.sunrise, adjustments.sunrise, methodAdjustments.sunrise);
    _dhuhr =
        finish(londonTimes.dhuhr, adjustments.dhuhr, methodAdjustments.dhuhr);
    _asr = finish(londonTimes.asr, adjustments.asr, methodAdjustments.asr);
    _maghrib = finish(
        londonTimes.maghrib, adjustments.maghrib, methodAdjustments.maghrib);
    _isha = finish(londonTimes.isha, adjustments.isha, methodAdjustments.isha);
  }
}
