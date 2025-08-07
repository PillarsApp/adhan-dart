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
      final prayerTimes = PrayerTimes(
        coordinates,
        DateComponents.from(date),
        params,
      );
      
      // Verify the times are loaded correctly
      expect(prayerTimes.fajr, isNotNull);
      expect(prayerTimes.sunrise, isNotNull);
      expect(prayerTimes.dhuhr, isNotNull);
      expect(prayerTimes.asr, isNotNull);
      expect(prayerTimes.maghrib, isNotNull);
      expect(prayerTimes.isha, isNotNull);
      
      // Check specific times for 2025-12-31 (in UTC)
      // London is UTC+0 in winter, so these should match the JSON times
      expect(prayerTimes.fajr?.hour, equals(6));
      expect(prayerTimes.fajr?.minute, equals(26));
      expect(prayerTimes.dhuhr?.hour, equals(12));
      expect(prayerTimes.dhuhr?.minute, equals(9));
      expect(prayerTimes.asr?.hour, equals(13));
      expect(prayerTimes.asr?.minute, equals(45));
    });
    
    
    test('should work with factory method for available dates', () {
      // Test with a known date in the embedded data
      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateTime(2025, 12, 31);
      
      // This should auto-initialize and work
      final prayerTimes = PrayerTimes(
        coordinates,
        DateComponents.from(date),
        params,
      );
      
      expect(prayerTimes, isNotNull);
      expect(prayerTimes.fajr, isNotNull);
    });
    
    test('should check if data is available for a date', () {
      // Verify we can check data availability after auto-init
      final availableDate = DateComponents(2025, 12, 31);
      final futureDate = DateComponents(2030, 1, 1); // Far future date not in data
      
      // This will trigger auto-initialization
      expect(LondonTimesLookup.hasDataForDate(availableDate), isTrue);
      expect(LondonTimesLookup.hasDataForDate(futureDate), isFalse);
    });
  });
}