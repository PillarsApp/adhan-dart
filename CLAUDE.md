# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Adhan Dart** library - a well-tested library for calculating Islamic prayer times in Dart/Flutter. It provides high-precision astronomical calculations based on "Astronomical Algorithms" by Jean Meeus, compatible with all Dart platforms (Flutter, Web, Native, etc.).

## Development Commands

### Testing
- `dart test` - Run all tests
- `dart test test/src/prayer_times_test.dart` - Run specific test file

### Analysis & Linting  
- `dart analyze` - Analyze code for issues
- `dart format .` - Format all Dart files
- `dart format lib/` - Format library files only

### Dependencies
- `dart pub get` - Install dependencies
- `dart pub upgrade` - Upgrade dependencies

### Running Examples
- `dart run bin/adhan.dart` - Quick test with Hanafi/Karachi parameters
- `dart run example/adhan_example.dart` - Run basic example

## Architecture

### Core Components

**PrayerTimes** (`lib/src/prayer_times.dart`): Main class that calculates all five daily prayer times plus sunrise. Supports multiple factory constructors for different use cases:
- `PrayerTimes.today()` - Calculate for current date
- `PrayerTimes.utc()` - Output UTC times  
- `PrayerTimes.utcOffset()` - Apply specific timezone offset

**CalculationMethod** (`lib/src/calculation_method.dart`): Enum with preset calculation methods (Muslim World League, Karachi, Egyptian, etc.) and their corresponding parameters. Also includes `unified_london_times` for JSON lookup-based times.

**Coordinates** (`lib/src/coordinates.dart`): Represents geographic location with optional validation.

**Internal Calculations** (`lib/src/internal/`): Astronomical calculations including:
- `solar_time.dart` - Solar position calculations
- `astronomical.dart` - Core astronomical functions
- `solar_coordinates.dart` - Sun coordinate calculations

### Data Structures

- **DateComponents** (`lib/src/data/date_components.dart`): Date representation for calculations
- **TimeComponents** (`lib/src/data/time_components.dart`): Time representation utilities
- **Prayer** (`lib/src/prayer.dart`): Enum for different prayer types
- **Madhab** (`lib/src/madhab.dart`): Hanafi vs Shafi calculation differences

### Additional Features

- **Qibla** (`lib/src/qibla.dart`): Calculate direction to Mecca
- **SunnahTimes** (`lib/src/sunnah_times.dart`): Calculate recommended prayer times
- **PrayerAdjustments** (`lib/src/prayer_adjustments.dart`): Manual time adjustments
- **LondonTimesLookup** (`lib/src/data/london_times_lookup.dart`): JSON-based prayer time lookup service for London

## Key Implementation Notes

- All times are calculated in UTC then converted to local timezone or specified offset
- High-latitude locations use special rules for extreme seasons
- Seasonal adjustments available for Moon Sighting Committee method
- Prayer times are rounded to nearest minute
- Comprehensive test coverage with JSON test data for various global locations
- **Unified London Times**: Uses JSON lookup instead of calculations - requires `LondonTimesLookup.initializeWithData()` before use

## Testing Data

Test files in `test/data/prayer-times/` contain expected prayer times for various cities and calculation methods, used for validation against known correct values. This includes:
- Standard calculation method test data for various global locations
- `London-UnifiedTimes.json` - Example JSON lookup data for testing the Unified London Times feature