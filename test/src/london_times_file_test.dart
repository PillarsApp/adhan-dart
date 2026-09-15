import 'dart:convert';
import 'dart:io';
import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

void main() {
  group('London Times from File', () {
    test('should load and use actual JSON file data', () async {
      // Load the actual JSON file from test data
      final file = File('test/data/prayer-times/London-UnifiedTimes.json');
      expect(file.existsSync(), isTrue,
          reason: 'London-UnifiedTimes.json should exist');

      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      // Initialize the lookup service with the file data
      LondonTimesLookup.initializeWithParsedData(jsonData);
      expect(LondonTimesLookup.isInitialized, isTrue);

      // Test with coordinates for London
      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();

      // Test all dates available in the file
      final testDates = [
        DateComponents(2025, 12, 31),
        DateComponents(2025, 12, 30),
        DateComponents(2025, 12, 29),
        DateComponents(2025, 12, 28),
      ];

      for (final date in testDates) {
        final prayerTimes = PrayerTimes.utc(coordinates, date, params);

        // Verify chronological order
        expect(prayerTimes.fajr.isBefore(prayerTimes.sunrise), isTrue);
        expect(prayerTimes.sunrise.isBefore(prayerTimes.dhuhr), isTrue);
        expect(prayerTimes.dhuhr.isBefore(prayerTimes.asr), isTrue);
        expect(prayerTimes.asr.isBefore(prayerTimes.maghrib), isTrue);
        expect(prayerTimes.maghrib.isBefore(prayerTimes.isha), isTrue);

        // Verify reasonable time ranges for London in December
        expect(prayerTimes.fajr.hour, inInclusiveRange(0, 12));
        expect(prayerTimes.sunrise.hour, inInclusiveRange(6, 10));
        expect(prayerTimes.dhuhr.hour, inInclusiveRange(11, 13));
        expect(prayerTimes.asr.hour, inInclusiveRange(10, 16));
        expect(prayerTimes.maghrib.hour, inInclusiveRange(14, 20));
        expect(prayerTimes.isha.hour, inInclusiveRange(16, 22));
      }
    });

    test('should match file data directly via lookup service', () async {
      final file = File('test/data/prayer-times/London-UnifiedTimes.json');
      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      LondonTimesLookup.initializeWithParsedData(jsonData);

      // Test direct lookup for specific date
      final date = DateComponents(2025, 12, 31);
      final londonTimes = LondonTimesLookup.getTimesForDate(date);

      expect(londonTimes, isNotNull);
      expect(londonTimes!.date, equals('2025-12-31'));
      expect(londonTimes.fajr, equals('06:26'));
      expect(londonTimes.sunrise, equals('08:03'));
      expect(londonTimes.dhuhr, equals('12:09'));
      expect(londonTimes.asr, equals('13:45'));
      expect(londonTimes.maghrib, equals('16:04'));
      expect(londonTimes.isha, equals('17:41'));
    });

    test('should handle file data with JSON string initialization', () async {
      final file = File('test/data/prayer-times/London-UnifiedTimes.json');
      final jsonString = await file.readAsString();

      // Initialize directly with JSON string
      LondonTimesLookup.initializeWithData(jsonString);
      expect(LondonTimesLookup.isInitialized, isTrue);

      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateComponents(2025, 12, 28);

      final prayerTimes = PrayerTimes.utc(coordinates, date, params);

      // Verify specific values from the file for Dec 28
      expect(prayerTimes.fajr.minute, equals(25)); // 06:25
      expect(prayerTimes.dhuhr.minute, equals(7)); // 12:07
      expect(prayerTimes.asr.minute, equals(43)); // 13:43
      expect(prayerTimes.maghrib.minute, equals(2)); // 16:02
      expect(prayerTimes.isha.minute, equals(39)); // 17:39
    });

    test('should validate data availability for file dates', () async {
      final file = File('test/data/prayer-times/London-UnifiedTimes.json');
      final jsonString = await file.readAsString();

      LondonTimesLookup.initializeWithData(jsonString);

      // Test dates that should be available
      expect(LondonTimesLookup.hasDataForDate(DateComponents(2025, 12, 31)),
          isTrue);
      expect(LondonTimesLookup.hasDataForDate(DateComponents(2025, 12, 30)),
          isTrue);
      expect(LondonTimesLookup.hasDataForDate(DateComponents(2025, 12, 29)),
          isTrue);
      expect(LondonTimesLookup.hasDataForDate(DateComponents(2025, 12, 28)),
          isTrue);

      // Test dates that should NOT be available
      expect(LondonTimesLookup.hasDataForDate(DateComponents(2025, 1, 1)),
          isFalse);
      expect(LondonTimesLookup.hasDataForDate(DateComponents(2024, 12, 31)),
          isFalse);
      expect(LondonTimesLookup.hasDataForDate(DateComponents(2025, 12, 27)),
          isFalse);
    });
  });
}
