import 'package:adhan/adhan.dart';

class City {
  final String name;
  final double latitude;
  final double longitude;

  const City(this.name, this.latitude, this.longitude);

  Coordinates get coordinates => Coordinates(latitude, longitude);
}

const cities = [
  City('KualaLumpur', 3.1390, 101.6869),
  City('London', 51.5074, -0.1278),
  City('NewYork', 40.7128, -74.0060),
  City('Oslo', 59.9139, 10.7522),
  City('Reykjavik', 64.1466, -21.9426),
  City('Sydney', -33.8688, 151.2093),
  City('Tromso', 69.6492, 18.9553),
  City('Auckland', -36.8485, 174.7633),
  City('Apia', -13.8333, -171.7500),
  City('BuenosAires', -34.6037, -58.3816),
];

const methodKeys = [
  'mwl_mid',
  'mwl_seventh',
  'mwl_twilight',
  'msc_mid',
  'isna_mid',
  'singapore_mid',
];

const prayerNames = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

final days2026 = List<DateTime>.generate(
    365, (offset) => DateTime.utc(2026, 1, 1).add(Duration(days: offset)));

String dayLabel(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

class GridOptions {
  final PolarCircleResolution? polarCircleResolution;
  final HourAngleCorrection? hourAngleCorrection;

  const GridOptions({this.polarCircleResolution, this.hourAngleCorrection});

  static const usage = '[--polar aqrabBalad|aqrabYaum|unresolved] '
      '[--correction iterative|singlePass]';

  static GridOptions parse(List<String> arguments, {List<String>? rest}) {
    PolarCircleResolution? polar;
    HourAngleCorrection? correction;
    final remaining = List.of(arguments);
    while (remaining.isNotEmpty) {
      final flag = remaining.first;
      if (flag == '--polar' && remaining.length >= 2) {
        polar = PolarCircleResolution.values.byName(remaining[1]);
        remaining.removeRange(0, 2);
      } else if (flag == '--correction' && remaining.length >= 2) {
        correction = HourAngleCorrection.values.byName(remaining[1]);
        remaining.removeRange(0, 2);
      } else if (rest != null) {
        rest.add(remaining.removeAt(0));
      } else {
        throw FormatException('unknown argument $flag');
      }
    }
    return GridOptions(
        polarCircleResolution: polar, hourAngleCorrection: correction);
  }

  CalculationParameters parameters(String methodKey) {
    final CalculationParameters p;
    switch (methodKey) {
      case 'mwl_mid':
        p = CalculationMethod.muslim_world_league.getParameters()
          ..highLatitudeRule = HighLatitudeRule.middle_of_the_night;
        break;
      case 'mwl_seventh':
        p = CalculationMethod.muslim_world_league.getParameters()
          ..highLatitudeRule = HighLatitudeRule.seventh_of_the_night;
        break;
      case 'mwl_twilight':
        p = CalculationMethod.muslim_world_league.getParameters()
          ..highLatitudeRule = HighLatitudeRule.twilight_angle;
        break;
      case 'msc_mid':
        p = CalculationMethod.moon_sighting_committee.getParameters()
          ..highLatitudeRule = HighLatitudeRule.middle_of_the_night;
        break;
      case 'isna_mid':
        p = CalculationMethod.north_america.getParameters()
          ..highLatitudeRule = HighLatitudeRule.middle_of_the_night;
        break;
      case 'singapore_mid':
        p = CalculationMethod.singapore.getParameters()
          ..highLatitudeRule = HighLatitudeRule.middle_of_the_night;
        break;
      default:
        throw ArgumentError.value(methodKey, 'methodKey');
    }
    final polar = polarCircleResolution;
    if (polar != null) {
      p.polarCircleResolution = polar;
    }
    final correction = hourAngleCorrection;
    if (correction != null) {
      p.hourAngleCorrection = correction;
    }
    return p;
  }
}

Iterable<String> gridRows(GridOptions options) sync* {
  for (final city in cities) {
    for (final day in days2026) {
      final components = DateComponents(day.year, day.month, day.day);
      for (final key in methodKeys) {
        final prefix = '${city.name},${dayLabel(day)},$key';
        try {
          final t = PrayerTimes.utc(
              city.coordinates, components, options.parameters(key));
          final values = [t.fajr, t.sunrise, t.dhuhr, t.asr, t.maghrib, t.isha]
              .map((d) => (d.millisecondsSinceEpoch ~/ 1000).toString());
          yield '$prefix,${values.join(',')}';
        } on ArgumentError {
          yield '$prefix,nil,nil,nil,nil,nil,nil';
        }
      }
    }
  }
}
