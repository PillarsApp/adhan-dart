# London Prayer Times Implementation Guide

This document explains the detailed implementation of the JSON lookup-based "Unified London Times" feature in the Adhan Dart library, including architectural decisions, implementation steps, and considerations for similar features in other libraries.

## Overview

The goal was to add support for pre-calculated prayer times from a JSON lookup table, bypassing astronomical calculations for specific locations where authoritative prayer time data is available.

## Design Decisions & Alternatives Considered

### Plan Selection
Four implementation approaches were considered:

1. **✅ Plan 1: Enum Extension with Special Handling** (Selected)
   - Add new enum value to existing `CalculationMethod`
   - Modify `PrayerTimes` constructor to detect and handle specially
   - **Pros**: Minimal API changes, backward compatible, same interface
   - **Cons**: Mixed paradigms (calculation vs lookup)

2. **Plan 2: Separate Lookup-Based Class**
   - Create `LookupPrayerTimes` alongside `PrayerTimes`
   - **Pros**: Clean separation, no pollution of existing logic
   - **Cons**: Different APIs, code duplication

3. **Plan 3: Strategy Pattern Refactor**
   - Abstract calculation logic using strategy pattern
   - **Pros**: Most architecturally sound, extensible
   - **Cons**: Significant refactoring, potential breaking changes

4. **Plan 4: Hybrid Approach**
   - Extend enum with properties, minimal core changes
   - **Pros**: Balanced approach
   - **Cons**: Some mixing of concerns

**Rationale for Plan 1**: Prioritized maintaining API consistency and minimizing breaking changes while adding the new functionality cleanly.

## Implementation Architecture

### Core Components Added

```
lib/src/
├── calculation_method.dart          # Added unified_london_times enum
├── prayer_times.dart               # Added special handling logic
└── data/
    └── london_times_lookup.dart    # New: Lookup service & data models
```

### Data Flow

```
JSON Data → LondonTimesLookup → PrayerTimes → User
     ↓              ↓              ↓
  Initialize    Parse Times    Apply Adjustments
     ↓              ↓              ↓
  Validation   DateTime Objects  Local Timezone
```

## Step-by-Step Implementation

### Step 1: Extend Calculation Method Enum

**File**: `lib/src/calculation_method.dart`

```dart
enum CalculationMethod {
  // ... existing methods ...
  
  /// Unified London Times
  /// Uses pre-calculated prayer times from a JSON lookup table specifically for London
  unified_london_times,
  
  // ... other methods ...
}
```

**Added case in extension**:
```dart
case CalculationMethod.unified_london_times:
  {
    return CalculationParameters(
        fajrAngle: 0.0, ishaAngle: 0.0, method: this);
  }
```

**Key Considerations**:
- Used placeholder angles (0.0) since calculations are bypassed
- Maintained same return type for API consistency

### Step 2: Create Lookup Service

**File**: `lib/src/data/london_times_lookup.dart`

#### A. Data Models
```dart
class LondonPrayerTimes {
  final String date, fajr, sunrise, dhuhr, asr, maghrib, isha;
  
  factory LondonPrayerTimes.fromJson(Map<String, dynamic> json) {
    return LondonPrayerTimes(
      date: json['date'] as String,
      fajr: json['fajr'] as String,
      // ... other fields
      maghrib: json['magrib'] as String, // Note: JSON uses 'magrib' spelling
    );
  }
  
  DateTime parseTime(String timeStr, DateComponents date) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
```

#### B. Lookup Service
```dart
class LondonTimesLookup {
  static Map<String, dynamic>? _cachedData;
  
  static void initializeWithData(String jsonString) {
    _cachedData = json.decode(jsonString) as Map<String, dynamic>;
  }
  
  static void initializeWithParsedData(Map<String, dynamic> data) {
    _cachedData = data;
  }
  
  static LondonPrayerTimes? getTimesForDate(DateComponents date) {
    // Implementation details...
  }
}
```

**Key Design Decisions**:
- **Static service**: Singleton pattern for global state management
- **Flexible initialization**: Support both JSON string and parsed data
- **Platform agnostic**: No File I/O dependencies for web/Flutter compatibility
- **Defensive programming**: Null checks and error handling

### Step 3: Modify PrayerTimes Constructor

**File**: `lib/src/prayer_times.dart`

#### A. Early Detection
```dart
PrayerTimes._(this.coordinates, DateTime _date, this.calculationParameters,
    {this.utcOffset}) {
  final date = _date.toUtc();
  _dateComponents = DateComponents.from(date);

  // Special handling for London lookup times
  if (calculationParameters.method == CalculationMethod.unified_london_times) {
    _initializeFromLondonLookup(date);
    return;  // Bypass all astronomical calculations
  }
  
  // ... existing calculation logic continues ...
}
```

#### B. Lookup Implementation
```dart
void _initializeFromLondonLookup(DateTime date) {
  final dateComponents = DateComponents.from(date);
  final londonTimes = LondonTimesLookup.getTimesForDate(dateComponents);
  
  if (londonTimes == null) {
    throw ArgumentError('No London prayer times available for date...');
  }

  // Parse times and convert to UTC for processing
  final tempFajr = londonTimes.parseTime(londonTimes.fajr, dateComponents).toUtc();
  // ... parse other times ...

  // Apply adjustments and convert to local time (same as calculations)
  _fajr = CalendarUtil.roundedMinute(tempFajr
      .add(Duration(minutes: calculationParameters.adjustments.fajr))
      .add(Duration(minutes: calculationParameters.methodAdjustments.fajr))
      .toLocal());
  // ... apply to other times ...

  // Apply UTC offset if specified (same as calculations)
  if (utcOffset != null) {
    _fajr = fajr.toUtc().add(utcOffset!);
    // ... apply to other times ...
  }
}
```

**Critical Implementation Details**:
- **Early return**: Completely bypasses astronomical calculations
- **Consistent processing**: Uses same adjustment and timezone logic as calculations
- **Error handling**: Clear error messages for missing data
- **API consistency**: Results match existing `PrayerTimes` interface exactly

### Step 4: Update Exports

**File**: `lib/src/adhan_base.dart`

```dart
export 'data/london_times_lookup.dart';
```

## JSON Data Structure

### Expected Format
```json
{
  "city": "london",
  "times": {
    "2025-12-31": {
      "date": "2025-12-31",
      "fajr": "06:26",
      "sunrise": "08:03",
      "dhuhr": "12:09",
      "asr": "13:45",
      "magrib": "16:04",  // Note: 'magrib' spelling in JSON
      "isha": "17:41"
    }
  }
}
```

### Format Considerations
- **24-hour format**: Handles both 12-hour and 24-hour automatically
- **Date keys**: ISO format strings (YYYY-MM-DD)
- **Flexible structure**: Can include additional fields (jamat times, etc.)
- **Spelling variations**: Accommodates 'magrib' vs 'maghrib'

## Usage Patterns

### Basic Usage
```dart
// 1. Initialize lookup data
LondonTimesLookup.initializeWithData(jsonString);

// 2. Use like any other calculation method
final params = CalculationMethod.unified_london_times.getParameters();
final prayerTimes = PrayerTimes.today(coordinates, params);
```

### With Adjustments
```dart
final params = CalculationMethod.unified_london_times.getParameters();
params.adjustments.fajr = 5; // Add 5 minutes to Fajr
final prayerTimes = PrayerTimes(coordinates, date, params);
```

### Error Handling
```dart
try {
  final prayerTimes = PrayerTimes(coordinates, date, params);
} catch (ArgumentError e) {
  // Handle missing date in lookup table
  print('Date not available in lookup data: $e');
}
```

## Testing Strategy

### Test Coverage Areas

1. **Unit Tests**: Individual component functionality
   - Lookup service initialization
   - Time parsing and conversion
   - Error conditions

2. **Integration Tests**: End-to-end functionality
   - Full prayer time calculation flow
   - Adjustment applications
   - Timezone handling

3. **File-based Tests**: Real-world data validation
   - Actual JSON file loading
   - Data structure validation
   - Multiple date testing

### Test File Organization
```
test/
├── src/
│   ├── unified_london_times_test.dart     # Unit & integration tests
│   └── london_times_file_test.dart        # File-based tests
└── data/
    └── prayer-times/
        └── London-UnifiedTimes.json       # Test data
```

## Challenges & Solutions

### Challenge 1: Timezone Handling
**Problem**: JSON times need proper timezone interpretation
**Solution**: Parse as local time, convert to UTC for processing, apply same timezone logic as calculations

### Challenge 2: Platform Compatibility
**Problem**: File I/O doesn't work on web platforms
**Solution**: Separate initialization from data source - support both string and parsed data

### Challenge 3: API Consistency
**Problem**: Lookup should feel identical to calculations
**Solution**: Use same adjustment system, error patterns, and result formats

### Challenge 4: Data Validation
**Problem**: Invalid or missing JSON data could break calculations
**Solution**: Comprehensive validation with clear error messages

## Extending to Other Cities/Regions

### Generalization Strategy
1. **Abstract the lookup service**:
   ```dart
   abstract class PrayerTimeLookupService {
     PrayerTimes? getTimesForDate(DateComponents date);
   }
   ```

2. **City-specific implementations**:
   ```dart
   class LondonTimesLookup extends PrayerTimeLookupService { ... }
   class NewYorkTimesLookup extends PrayerTimeLookupService { ... }
   ```

3. **Configurable calculation method**:
   ```dart
   enum CalculationMethod {
     unified_london_times,
     unified_newyork_times,
     // ...
   }
   ```

### Configuration Approach
```dart
CalculationMethod.createLookupMethod(
  name: 'unified_paris_times',
  lookupService: ParisTimesLookup(),
);
```

## Performance Considerations

### Memory Management
- **Caching**: JSON data cached in memory after first load
- **Lazy loading**: Data loaded only when first accessed
- **Memory bounds**: Consider data size for large date ranges

### Lookup Efficiency
- **O(1) access**: HashMap lookup by date string
- **Pre-validation**: Check data availability before processing
- **Error short-circuiting**: Fast failure for missing dates

## Best Practices for Similar Implementations

### 1. Maintain API Consistency
- New features should feel like existing functionality
- Same error patterns and return types
- Consistent naming conventions

### 2. Separation of Concerns
- Keep data loading separate from business logic
- Abstract data sources (file, network, embedded)
- Isolate platform-specific code

### 3. Comprehensive Testing
- Test with real data, not just mocked data
- Cover error conditions thoroughly
- Validate data structure compliance

### 4. Documentation & Examples
- Clear usage examples
- Document data format requirements
- Explain limitations and assumptions

### 5. Backward Compatibility
- Existing code should continue working unchanged
- New features should be opt-in
- Deprecate gracefully if changes needed

## Conclusion

The JSON lookup implementation successfully demonstrates how to extend a calculation-based library with data-driven alternatives while maintaining API consistency and reliability. The approach prioritizes developer experience and backward compatibility while providing a clean foundation for future extensions.

Key success factors:
- **Minimal API surface changes**
- **Consistent behavior with existing features**
- **Comprehensive error handling**
- **Platform-agnostic design**
- **Thorough testing with real data**

This pattern can be applied to other prayer time libraries or similar calculation-based systems where authoritative pre-computed data should override algorithmic calculations.