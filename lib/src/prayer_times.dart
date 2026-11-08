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
import 'prayer_adjustments.dart';
import 'prayer_times_source.dart';
import 'published/official_row.dart';
import 'published/published_timetable.dart';

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

  final _Origin _origin;

  PrayerTimesSource get source => switch (_origin) {
        _Calculated() => PrayerTimesSource.calculated,
        _LondonLookup() ||
        _FromRow() ||
        _MalaysiaOfficial() =>
          PrayerTimesSource.official,
        _MalaysiaNoRow() => PrayerTimesSource.calculatedNoRow,
        _MalaysiaNoZone() => PrayerTimesSource.calculatedNoZone,
      };

  /// The official Malaysian zone the times were read for, or would have been:
  /// the manual zone when [CalculationParameters.malaysiaZone] is set, else the
  /// zone resolved from the coordinates. Null for every other method, for a
  /// manual code the data does not know and outside every zone.
  MalaysiaZone? get malaysiaZone => switch (_origin) {
        _MalaysiaOfficial(:final day) => day.zone,
        _MalaysiaNoRow(:final zone) => zone,
        _Calculated() ||
        _LondonLookup() ||
        _FromRow() ||
        _MalaysiaNoZone() =>
          null,
      };

  /// The published row behind the times, before adjustments and the Hanafi
  /// shift, presented like the six times. Null unless [source] is official
  /// and the method is [CalculationMethod.malaysia_official].
  MalaysiaDay? get malaysiaDay => switch (_origin) {
        _MalaysiaOfficial(:final day) => day,
        _Calculated() ||
        _LondonLookup() ||
        _FromRow() ||
        _MalaysiaNoRow() ||
        _MalaysiaNoZone() =>
          null,
      };

  /// The published row behind official times, before adjustments and the
  /// Hanafi shift. Null for calculated times and for the London lookup.
  OfficialRow? get officialRow => switch (_origin) {
        _FromRow(:final row) || _MalaysiaOfficial(:final row) => row,
        _Calculated() ||
        _LondonLookup() ||
        _MalaysiaNoRow() ||
        _MalaysiaNoZone() =>
          null,
      };

  // If you give a UTC Offset then Prayer Times will convert local(with device timezone) time
  // to UTC and then add the offset.
  final Duration? utcOffset;

  final Coordinates coordinates;

  final DateComponents _dateComponents;

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

  /// Times assembled from a published [row], presented like every other
  /// constructor: host local by default, else UTC plus [utcOffset].
  ///
  /// The madhab comes from [parameters]. When its shadow factor equals
  /// [OfficialRow.asrShadow], Asr is the published Asr. For a Hanafi madhab
  /// with a published `asrHanafi` column, Asr is that column. Otherwise Asr
  /// is the published Asr shifted by the solar difference between the two
  /// shadow factors at the locality's reference point. [adjustments], which
  /// default to the adjustments in [parameters], are added after that. The
  /// method adjustments in [parameters] are ignored.
  factory PrayerTimes.official(OfficialRow row,
          {required CalculationParameters parameters,
          PrayerAdjustments? adjustments,
          Duration? utcOffset}) =>
      PrayerTimes._from(
          row.locality.referencePoint,
          row.date,
          parameters,
          _FromRow(row),
          assembleOfficialDay(
              row, parameters, adjustments ?? parameters.adjustments),
          utcOffset: utcOffset);

  factory PrayerTimes._(Coordinates coordinates, DateTime date,
      CalculationParameters calculationParameters,
      {Duration? utcOffset}) {
    final utc = date.toUtc();
    final dateComponents = DateComponents.from(utc);
    final (origin, times) = _resolve(
        coordinates, utc, dateComponents, calculationParameters, utcOffset);
    return PrayerTimes._from(
        coordinates, dateComponents, calculationParameters, origin, times,
        utcOffset: utcOffset);
  }

  PrayerTimes._from(this.coordinates, this._dateComponents,
      this.calculationParameters, this._origin, DayTimes times,
      {this.utcOffset}) {
    _fajr = present(times.fajr, utcOffset);
    _sunrise = present(times.sunrise, utcOffset);
    _dhuhr = present(times.dhuhr, utcOffset);
    _asr = present(times.asr, utcOffset);
    _maghrib = present(times.maghrib, utcOffset);
    _isha = present(times.isha, utcOffset);
  }

  static (_Origin, DayTimes) _resolve(
      Coordinates coordinates,
      DateTime date,
      DateComponents dateComponents,
      CalculationParameters parameters,
      Duration? utcOffset) {
    if (parameters.method == CalculationMethod.unified_london_times) {
      return (const _LondonLookup(), _londonDay(dateComponents, parameters));
    }
    if (parameters.method == CalculationMethod.malaysia_official) {
      final code = parameters.malaysiaZone;
      switch (MalaysiaTimetable.source.lookup(coordinates, dateComponents,
          localityId: code == null ? null : LocalityId(code))) {
        case OfficialRow row:
          return (
            _MalaysiaOfficial(
                row, malaysiaDayFromRow(row, utcOffset: utcOffset)),
            assembleOfficialDay(row, parameters, parameters.adjustments)
          );
        case NoRow(:final locality):
          return (
            _MalaysiaNoRow(MalaysiaZones.zone(locality.id.value)!),
            _compute(coordinates, date, parameters)
          );
        case NoLocality():
          return (
            const _MalaysiaNoZone(),
            _compute(coordinates, date, parameters)
          );
      }
    }
    return (const _Calculated(), _compute(coordinates, date, parameters));
  }

  static DayTimes _compute(Coordinates coordinates, DateTime date,
      CalculationParameters parameters) {
    if (!(coordinates.latitude.abs() <= 90)) {
      throw ArgumentError.value(coordinates.latitude, 'latitude',
          'must be a number between -90 and 90');
    }
    final times = DayTimes.compute(coordinates, date, parameters) ??
        parameters.polarCircleResolution.resolve(coordinates, date, parameters);
    if (times == null) {
      throw ArgumentError('Prayer times cannot be computed at latitude '
          '${coordinates.latitude}, longitude ${coordinates.longitude} '
          'on ${DateComponents.from(date)}');
    }
    return times;
  }

  static DayTimes _londonDay(
      DateComponents date, CalculationParameters parameters) {
    final londonTimes = LondonTimesLookup.getTimesForDate(date);
    if (londonTimes == null) {
      throw ArgumentError(
          'No London prayer times available for date ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
    }

    DateTime finish(String time, int adjustment, int methodAdjustment) {
      final utc = londonTimes.parseTime(time, date).toUtc();
      return CalendarUtil.roundedMinute(
          utc.add(Duration(minutes: adjustment + methodAdjustment)),
          parameters.rounding);
    }

    final adjustments = parameters.adjustments;
    final methodAdjustments = parameters.methodAdjustments;
    return DayTimes(
        fajr:
            finish(londonTimes.fajr, adjustments.fajr, methodAdjustments.fajr),
        sunrise: finish(londonTimes.sunrise, adjustments.sunrise,
            methodAdjustments.sunrise),
        dhuhr: finish(
            londonTimes.dhuhr, adjustments.dhuhr, methodAdjustments.dhuhr),
        asr: finish(londonTimes.asr, adjustments.asr, methodAdjustments.asr),
        maghrib: finish(londonTimes.maghrib, adjustments.maghrib,
            methodAdjustments.maghrib),
        isha:
            finish(londonTimes.isha, adjustments.isha, methodAdjustments.isha));
  }

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
        return null;
    }
  }

  static int daysSinceSolstice(int dayOfYear, int year, double latitude) {
    return DayTimes.daysSinceSolstice(dayOfYear, year, latitude);
  }
}

sealed class _Origin {
  const _Origin();
}

final class _Calculated extends _Origin {
  const _Calculated();
}

final class _LondonLookup extends _Origin {
  const _LondonLookup();
}

final class _FromRow extends _Origin {
  final OfficialRow row;

  const _FromRow(this.row);
}

final class _MalaysiaOfficial extends _Origin {
  final OfficialRow row;
  final MalaysiaDay day;

  const _MalaysiaOfficial(this.row, this.day);
}

final class _MalaysiaNoRow extends _Origin {
  final MalaysiaZone zone;

  const _MalaysiaNoRow(this.zone);
}

final class _MalaysiaNoZone extends _Origin {
  const _MalaysiaNoZone();
}
