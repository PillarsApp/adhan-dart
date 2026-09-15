import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

void main() {
  group('London Times Auto-Initialization', () {
    test('should auto-initialize from embedded data without manual setup', () {
      // This test verifies that the London times work without any manual initialization
      // The library should automatically load the embedded data when needed

      final coordinates = Coordinates(51.5074, -0.1278); // London coordinates
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateTime(2025, 12, 31);

      // This should work without calling LondonTimesLookup.initializeWithData()
      final prayerTimes = PrayerTimes.utc(
        coordinates,
        DateComponents.from(date),
        params,
      );

      // Check specific times for 2025-12-31 (in UTC)
      // London is UTC+0 in winter, so these should match the JSON times
      expect(prayerTimes.fajr, DateTime.utc(2025, 12, 31, 6, 26));
      expect(prayerTimes.dhuhr, DateTime.utc(2025, 12, 31, 12, 9));
      expect(prayerTimes.asr, DateTime.utc(2025, 12, 31, 13, 45));
    });

    test('should check if data is available for a date', () {
      // Verify we can check data availability after auto-init
      final availableDate = DateComponents(2025, 12, 31);
      final futureDate =
          DateComponents(2030, 1, 1); // Far future date not in data

      // This will trigger auto-initialization
      expect(LondonTimesLookup.hasDataForDate(availableDate), isTrue);
      expect(LondonTimesLookup.hasDataForDate(futureDate), isFalse);
    });
  });
}
