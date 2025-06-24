import 'dart:convert';

import '../data/date_components.dart';

/// Service for looking up pre-calculated London prayer times from JSON data
class LondonTimesLookup {
  static Map<String, dynamic>? _cachedData;
  
  /// Initialize with JSON data (call this first before using getTimesForDate)
  static void initializeWithData(String jsonString) {
    _cachedData = json.decode(jsonString) as Map<String, dynamic>;
  }
  
  /// Initialize with pre-parsed data
  static void initializeWithParsedData(Map<String, dynamic> data) {
    _cachedData = data;
  }
  
  /// Synchronous version that uses cached data or throws if not loaded
  static Map<String, dynamic> _getCachedData() {
    if (_cachedData == null) {
      throw StateError('London times data not initialized. Call initializeWithData() or initializeWithParsedData() first.');
    }
    return _cachedData!;
  }
  
  /// Check if data has been loaded
  static bool get isInitialized => _cachedData != null;
  
  /// Get prayer times for a specific date
  /// Returns null if date not found in lookup table
  static LondonPrayerTimes? getTimesForDate(DateComponents date) {
    try {
      final data = _getCachedData();
      final dateKey = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      final times = data['times'] as Map<String, dynamic>?;
      if (times == null) return null;
      
      final dayData = times[dateKey] as Map<String, dynamic>?;
      if (dayData == null) return null;
      
      return LondonPrayerTimes.fromJson(dayData);
    } catch (e) {
      return null;
    }
  }
  
  /// Check if data is available for a specific date
  static bool hasDataForDate(DateComponents date) {
    return getTimesForDate(date) != null;
  }
}

/// Represents prayer times from the London lookup table
class LondonPrayerTimes {
  final String date;
  final String fajr;
  final String sunrise;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;
  
  LondonPrayerTimes({
    required this.date,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });
  
  factory LondonPrayerTimes.fromJson(Map<String, dynamic> json) {
    return LondonPrayerTimes(
      date: json['date'] as String,
      fajr: json['fajr'] as String,
      sunrise: json['sunrise'] as String,
      dhuhr: json['dhuhr'] as String,
      asr: json['asr'] as String,
      maghrib: json['magrib'] as String, // Note: using 'magrib' as in your JSON
      isha: json['isha'] as String,
    );
  }
  
  /// Parse time string (HH:MM) and create DateTime for given date
  /// The returned DateTime represents the time in London timezone
  DateTime parseTime(String timeStr, DateComponents date) {
    final parts = timeStr.split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid time format: $timeStr');
    }
    
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    
    // Create as local DateTime representing London time
    // The JSON times are assumed to be in London local time
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}