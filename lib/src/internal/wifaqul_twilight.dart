import '../calculation_parameters.dart';
import '../coordinates.dart';
import '../data/time_components.dart';
import '../wifaqul_options.dart';
import 'solar_time.dart';

class WifaqulTwilight {
  final DateTime fajr;
  final DateTime isha;

  WifaqulTwilight._(this.fajr, this.isha);

  static final Map<_ReferenceKey, _References> _cache = {};

  /// Internal reference-cache diagnostic; no prayer calculation is triggered.
  static int get cachedReferenceCount => _cache.length;

  static WifaqulTwilight calculate(
      DateTime date,
      Coordinates coordinates,
      CalculationParameters parameters,
      SolarTime solar,
      DateTime sunrise,
      DateTime sunset) {
    if (parameters.fajrAngle != 18 ||
        parameters.ishaAngle != 18 ||
        parameters.ishaInterval != 0 ||
        parameters.maghribAngle != null) {
      throw ArgumentError('Wifaqul requires its preset angles and interval');
    }
    final options = parameters.wifaqulOptions ?? const WifaqulOptions();
    var fajr = _event(date, solar.twilightHourAngle(-18, false));
    if (fajr == null) {
      if (coordinates.latitude < 0) {
        throw ArgumentError('Missing southern twilight is unsupported');
      }
      if (options.fajrRule == WifaqulFajrRule.nisf_al_layl) {
        final previous = date.subtract(const Duration(days: 1));
        final previousSunset = _requiredEvent(previous,
            SolarTime(previous, coordinates, preserveSolarDate: true).sunset);
        fajr = previousSunset.add(Duration(
            seconds: sunrise.difference(previousSunset).inSeconds ~/ 2));
      } else {
        fajr = date.add(_dawnOffset(date, coordinates));
      }
    }
    var isha = _event(date,
        solar.twilightHourAngle(coordinates.latitude >= 48 ? -15 : -18, true));
    if (coordinates.latitude >= 48) {
      DateTime cap;
      if (isha != null &&
          options.ishaRule == WifaqulIshaRule.seventh_of_night) {
        final tomorrow = date.add(const Duration(days: 1));
        final nextSunrise = _requiredEvent(tomorrow,
            SolarTime(tomorrow, coordinates, preserveSolarDate: true).sunrise);
        cap = sunset.add(
            Duration(seconds: nextSunrise.difference(sunset).inSeconds ~/ 7));
      } else {
        cap = date.add(_solsticeOffset(date, coordinates));
      }
      if (isha == null || isha.isAfter(cap)) isha = cap;
    }
    if (isha == null) {
      throw ArgumentError('Missing Isha twilight is unsupported');
    }
    return WifaqulTwilight._(fajr, isha);
  }

  static DateTime? _event(DateTime date, double hours) => hours.isFinite
      ? TimeComponents.fromDouble(hours).dateComponents(date)
      : null;

  static DateTime _requiredEvent(DateTime date, double hours) {
    final event = _event(date, hours);
    if (event == null) throw ArgumentError('Required solar event unavailable');
    return event;
  }

  static _References _references(DateTime date, Coordinates coordinates) {
    final key =
        _ReferenceKey(coordinates.latitude, coordinates.longitude, date.year);
    final existing = _cache[key];
    if (existing != null) return existing;
    if (_cache.length >= 32) _cache.clear();
    final references = _References();
    _cache[key] = references;
    return references;
  }

  static Duration _dawnOffset(DateTime date, Coordinates coordinates) {
    final references = _references(date, coordinates);
    for (final season in references.seasons) {
      if (date.isAfter(season.previous) && date.isBefore(season.following)) {
        return season.offset;
      }
    }
    DateTime? previous;
    Duration? offset;
    DateTime? following;
    for (var distance = 1; distance <= 370; distance++) {
      final candidate = date.subtract(Duration(days: distance));
      final dawn = _event(
          candidate,
          SolarTime(candidate, coordinates, preserveSolarDate: true)
              .twilightHourAngle(-18, false));
      if (dawn != null) {
        previous = candidate;
        offset = dawn.difference(candidate);
        break;
      }
    }
    for (var distance = 1; distance <= 370; distance++) {
      final candidate = date.add(Duration(days: distance));
      if (SolarTime(candidate, coordinates, preserveSolarDate: true)
          .twilightHourAngle(-18, false)
          .isFinite) {
        following = candidate;
        break;
      }
    }
    if (previous == null || following == null || offset == null) {
      throw ArgumentError('No bounded Aqrabul Ayyam reference');
    }
    references.seasons.add(_DawnSeason(previous, following, offset));
    return offset;
  }

  static Duration _solsticeOffset(DateTime date, Coordinates coordinates) {
    final references = _references(date, coordinates);
    if (references.solstice != null) return references.solstice!;
    var longestDaylight = double.negativeInfinity;
    Duration? offset;
    for (var day = 15; day <= 25; day++) {
      final candidate = DateTime.utc(date.year, 6, day);
      final solar = SolarTime(candidate, coordinates, preserveSolarDate: true);
      final sunset = _requiredEvent(candidate, solar.sunset);
      _requiredEvent(candidate, solar.sunrise);
      final daylight = solar.sunset - solar.sunrise;
      if (daylight > longestDaylight) {
        longestDaylight = daylight;
        offset = sunset.difference(candidate) + const Duration(minutes: 65);
      }
    }
    references.solstice = offset!;
    return offset;
  }
}

class _ReferenceKey {
  final double latitude;
  final double longitude;
  final int year;

  _ReferenceKey(this.latitude, this.longitude, this.year);

  @override
  bool operator ==(Object other) =>
      other is _ReferenceKey &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      year == other.year;

  @override
  int get hashCode => Object.hash(latitude, longitude, year);
}

class _References {
  final List<_DawnSeason> seasons = [];
  Duration? solstice;
}

class _DawnSeason {
  final DateTime previous;
  final DateTime following;
  final Duration offset;

  _DawnSeason(this.previous, this.following, this.offset);
}
