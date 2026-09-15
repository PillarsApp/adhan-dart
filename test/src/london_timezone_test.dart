import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

void main() {
  group('London timetable instants', () {
    final expectedNoonInstants = [
      DateTime.utc(2026, 1, 15, 12),
      DateTime.utc(2026, 3, 28, 12),
      DateTime.utc(2026, 3, 29, 11),
      DateTime.utc(2026, 7, 15, 11),
      DateTime.utc(2026, 10, 24, 11),
      DateTime.utc(2026, 10, 25, 12),
    ];

    for (final expectedNoon in expectedNoonInstants) {
      test('uses Europe/London offset on ${expectedNoon.toIso8601String()}',
          () {
        final date = DateComponents.from(expectedNoon);
        final dateKey = expectedNoon.toIso8601String().substring(0, 10);
        LondonTimesLookup.initializeWithParsedData({
          'times': {
            dateKey: {
              'date': dateKey,
              'fajr': '04:00',
              'sunrise': '06:00',
              'dhuhr': '12:00',
              'asr': '15:00',
              'magrib': '18:00',
              'isha': '20:00',
            },
          },
        });
        final coordinates = Coordinates(51.5074, -0.1278);
        final parameters =
            CalculationMethod.unified_london_times.getParameters();
        final utcPrayers = PrayerTimes.utc(coordinates, date, parameters);
        final localPrayers = PrayerTimes(coordinates, date, parameters);
        final offsetPrayers = PrayerTimes.utcOffset(
          coordinates,
          date,
          parameters,
          Duration(hours: 5, minutes: 30),
        );

        expect(utcPrayers.dhuhr, expectedNoon);
        expect(localPrayers.dhuhr, expectedNoon.toLocal());
        expect(offsetPrayers.dhuhr,
            expectedNoon.add(Duration(hours: 5, minutes: 30)));
      });
    }
  });
}
