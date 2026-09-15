import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

void main() {
  group('Unified London Times', () {
    // Sample test data matching the example JSON structure
    final sampleLondonData = {
      'city': 'london',
      'times': {
        '2025-12-31': {
          'date': '2025-12-31',
          'fajr': '06:26',
          'sunrise': '08:03',
          'dhuhr': '12:09',
          'asr': '13:45',
          'magrib': '16:04',
          'isha': '17:41',
        },
        '2025-12-30': {
          'date': '2025-12-30',
          'fajr': '06:26',
          'sunrise': '08:03',
          'dhuhr': '12:08',
          'asr': '13:45',
          'magrib': '16:03',
          'isha': '17:40',
        },
        '2025-01-01': {
          'date': '2025-01-01',
          'fajr': '06:26',
          'sunrise': '08:03',
          'dhuhr': '12:10',
          'asr': '13:46',
          'magrib': '16:05',
          'isha': '17:42',
        }
      }
    };

    setUp(() {
      // Initialize lookup data before each test
      LondonTimesLookup.initializeWithParsedData(sampleLondonData);
    });

    test('should return correct prayer times from lookup', () {
      final coordinates = Coordinates(51.5074, -0.1278); // London coordinates
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateComponents(2025, 12, 31);

      final prayerTimes = PrayerTimes.utc(coordinates, date, params);

      expect(prayerTimes.fajr.minute, equals(26));
      expect(prayerTimes.sunrise.minute, equals(3));
      expect(prayerTimes.dhuhr.minute, equals(9));
      expect(prayerTimes.asr.minute, equals(45));
      expect(prayerTimes.maghrib.minute, equals(4));
      expect(prayerTimes.isha.minute, equals(41));

      // Verify the times are in chronological order
      expect(prayerTimes.fajr.isBefore(prayerTimes.sunrise), isTrue);
      expect(prayerTimes.sunrise.isBefore(prayerTimes.dhuhr), isTrue);
      expect(prayerTimes.dhuhr.isBefore(prayerTimes.asr), isTrue);
      expect(prayerTimes.asr.isBefore(prayerTimes.maghrib), isTrue);
      expect(prayerTimes.maghrib.isBefore(prayerTimes.isha), isTrue);
    });

    test('should work with different dates', () {
      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateComponents(2025, 12, 30);

      final prayerTimes = PrayerTimes.utc(coordinates, date, params);

      // Verify different date has different times
      expect(prayerTimes.dhuhr.minute, equals(8)); // 12:08 vs 12:09 on Dec 31
      expect(prayerTimes.maghrib.minute, equals(3)); // 16:03 vs 16:04 on Dec 31
    });

    test('should apply prayer adjustments correctly', () {
      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();

      // Add 10 minutes to Fajr
      params.adjustments.fajr = 10;

      final date = DateComponents(2025, 12, 31);
      final prayerTimes = PrayerTimes.utc(coordinates, date, params);

      // Fajr should be 06:26 + 10 minutes = 06:36
      expect(prayerTimes.fajr.minute, equals(36));
    });

    test('should throw error for missing date', () {
      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final missingDate = DateComponents(2020, 1, 1); // Not in our sample data

      expect(
        () => PrayerTimes(coordinates, missingDate, params),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should handle UTC offset correctly', () {
      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateComponents(2025, 12, 31);
      final utcOffset = Duration(hours: 5); // +5 hours

      final prayerTimes =
          PrayerTimes(coordinates, date, params, utcOffset: utcOffset);

      expect(prayerTimes.fajr, DateTime.utc(2025, 12, 31, 11, 26));
    });

    test('should initialize with JSON string', () {
      final jsonString = '''
      {
        "city": "london",
        "times": {
          "2025-06-01": {
            "date": "2025-06-01",
            "fajr": "03:30",
            "sunrise": "05:15",
            "dhuhr": "12:30",
            "asr": "16:45",
            "magrib": "20:00",
            "isha": "21:30"
          }
        }
      }
      ''';

      LondonTimesLookup.initializeWithData(jsonString);
      expect(LondonTimesLookup.isInitialized, isTrue);

      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateComponents(2025, 6, 1);

      final prayerTimes = PrayerTimes.utc(coordinates, date, params);
      expect(prayerTimes.fajr.minute, equals(30));
    });

    test('should throw error when not initialized', () {
      // Reset the lookup service
      LondonTimesLookup.initializeWithParsedData({});

      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateComponents(2025, 12, 31);

      expect(
        () => PrayerTimes(coordinates, date, params),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should handle method adjustments', () {
      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();

      // Add method adjustments (these are typically set by the calculation method)
      params.methodAdjustments.dhuhr = 5; // Add 5 minutes to Dhuhr

      final date = DateComponents(2025, 12, 31);
      final prayerTimes = PrayerTimes.utc(coordinates, date, params);

      // Dhuhr should be 12:09 + 5 minutes = 12:14
      expect(prayerTimes.dhuhr.minute, equals(14));
    });

    test('should work with LondonPrayerTimes.getTimesForDate directly', () {
      final date = DateComponents(2025, 12, 31);
      final londonTimes = LondonTimesLookup.getTimesForDate(date);

      expect(londonTimes, isNotNull);
      expect(londonTimes!.fajr, equals('06:26'));
      expect(londonTimes.dhuhr, equals('12:09'));
      expect(londonTimes.maghrib, equals('16:04'));
    });

    test('should return null for missing dates in direct lookup', () {
      final missingDate = DateComponents(2020, 1, 1);
      final londonTimes = LondonTimesLookup.getTimesForDate(missingDate);

      expect(londonTimes, isNull);
    });

    test('should check data availability correctly', () {
      final availableDate = DateComponents(2025, 12, 31);
      final missingDate = DateComponents(2020, 1, 1);

      expect(LondonTimesLookup.hasDataForDate(availableDate), isTrue);
      expect(LondonTimesLookup.hasDataForDate(missingDate), isFalse);
    });

    test('should handle 24-hour time format correctly', () {
      // Test with explicit 24-hour format data
      final twentyFourHourData = {
        'city': 'london',
        'times': {
          '2025-06-15': {
            'date': '2025-06-15',
            'fajr': '03:30', // Early morning
            'sunrise': '05:15',
            'dhuhr': '12:30', // Noon
            'asr': '16:45', // 4:45 PM in 24-hour format
            'magrib': '20:00', // 8:00 PM in 24-hour format
            'isha': '21:30', // 9:30 PM in 24-hour format
          }
        }
      };

      LondonTimesLookup.initializeWithParsedData(twentyFourHourData);

      final coordinates = Coordinates(51.5074, -0.1278);
      final params = CalculationMethod.unified_london_times.getParameters();
      final date = DateComponents(2025, 6, 15);

      final prayerTimes = PrayerTimes.utc(coordinates, date, params);

      // Verify 24-hour times are parsed correctly
      expect(prayerTimes.fajr.minute, equals(30)); // 03:30
      expect(prayerTimes.sunrise.minute, equals(15)); // 05:15
      expect(prayerTimes.dhuhr.minute, equals(30)); // 12:30
      expect(prayerTimes.asr.minute, equals(45)); // 16:45 (4:45 PM)
      expect(prayerTimes.maghrib.minute, equals(0)); // 20:00 (8:00 PM)
      expect(prayerTimes.isha.minute, equals(30)); // 21:30 (9:30 PM)

      // Verify chronological order is maintained
      expect(prayerTimes.fajr.isBefore(prayerTimes.sunrise), isTrue);
      expect(prayerTimes.sunrise.isBefore(prayerTimes.dhuhr), isTrue);
      expect(prayerTimes.dhuhr.isBefore(prayerTimes.asr), isTrue);
      expect(prayerTimes.asr.isBefore(prayerTimes.maghrib), isTrue);
      expect(prayerTimes.maghrib.isBefore(prayerTimes.isha), isTrue);

      // Test direct lookup to verify JSON parsing
      final londonTimes = LondonTimesLookup.getTimesForDate(date);
      expect(
          londonTimes!.asr, equals('16:45')); // Should remain as 24-hour format
      expect(londonTimes.maghrib,
          equals('20:00')); // Should remain as 24-hour format
      expect(
          londonTimes.isha, equals('21:30')); // Should remain as 24-hour format
    });
  });
}
