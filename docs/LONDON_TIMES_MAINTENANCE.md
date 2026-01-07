# London Prayer Times Data Maintenance Guide

This document describes the CLI tooling and data management approach for the London Unified Prayer Times feature. It is intended as a reference for engineers implementing similar functionality in other language versions of this package.

## Overview

The London Unified Prayer Times feature provides pre-calculated prayer times from [londonprayertimes.com](https://www.londonprayertimes.com) rather than using astronomical calculations. This is useful for users who want times that match local mosque timetables in London.

The times are embedded directly in the library as a JSON string constant, eliminating the need for runtime API calls.

## Data Structure

### Embedded Data Format

The data is stored in `lib/src/data/london_times_data.dart` as a raw string constant:

```dart
const String londonPrayerTimesData = r'''
{
  "city": "london",
  "times": {
    "2026-12-31": {
      "date": "2026-12-31",
      "fajr": "06:26",
      "fajr_jamat": "06:46",
      "sunrise": "08:03",
      "dhuhr": "12:09",
      "dhuhr_jamat": "12:45",
      "asr": "13:45",
      "asr_2": "14:16",
      "asr_jamat": "14:30",
      "magrib": "16:04",
      "magrib_jamat": "16:11",
      "isha": "17:41",
      "isha_jamat": "19:30"
    },
    ...
  }
}
''';
```

### Field Descriptions

| Field | Description |
|-------|-------------|
| `date` | Date in `YYYY-MM-DD` format |
| `fajr` | Fajr prayer start time |
| `fajr_jamat` | Fajr congregation time |
| `sunrise` | Sunrise time |
| `dhuhr` | Dhuhr prayer start time |
| `dhuhr_jamat` | Dhuhr congregation time |
| `asr` | Asr prayer start time (Shafi/standard) |
| `asr_2` | Asr prayer start time (Hanafi) |
| `asr_jamat` | Asr congregation time |
| `magrib` | Maghrib prayer start time |
| `magrib_jamat` | Maghrib congregation time |
| `isha` | Isha prayer start time |
| `isha_jamat` | Isha congregation time |

All times are in 24-hour format (`HH:MM`).

## London Prayer Times API

### Endpoint

```
https://www.londonprayertimes.com/api/times/
```

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `format` | Response format. Use `json` |
| `key` | API key for authentication |
| `year` | Year to fetch (e.g., `2026`) |
| `24hours` | Set to `true` to get times in 24-hour format |

### Example Request

```bash
curl "https://www.londonprayertimes.com/api/times/?format=json&key=YOUR_API_KEY&year=2026&24hours=true"
```

### Important: The `24hours` Parameter

**Always use `&24hours=true`** when fetching data. Without this parameter, the API returns times in an inconsistent format where afternoon/evening times appear as 12-hour times without AM/PM indicators:

```json
// WITHOUT 24hours=true (incorrect for our use)
{
  "dhuhr": "01:06",   // Should be 13:06
  "asr": "05:24",     // Should be 17:24
  "magrib": "09:23"   // Should be 21:23
}

// WITH 24hours=true (correct)
{
  "dhuhr": "13:06",
  "asr": "17:24",
  "magrib": "21:23"
}
```

### Response Structure

The API returns JSON with the same structure as our embedded data:

```json
{
  "city": "london",
  "times": {
    "2026-12-31": { ... },
    "2026-12-30": { ... },
    ...
  }
}
```

The `times` object is keyed by date string (`YYYY-MM-DD`), with 365 (or 366) entries per year.

## CLI Tool (Dart Implementation)

The Dart implementation includes a CLI tool at `bin/london_times_cli.dart` for data maintenance.

### Commands

#### `info` - Show Data Statistics

```bash
dart run bin/london_times_cli.dart info
```

Output:
```
=== London Prayer Times Data Statistics ===

City: london
Total entries: 730
Years covered: [2025, 2026]

  2025: 365 entries (2025-01-01 to 2025-12-31)
  2026: 365 entries (2026-01-01 to 2026-12-31)

Overall range: 2025-01-01 to 2026-12-31
```

#### `validate` - Check Data Integrity

```bash
dart run bin/london_times_cli.dart validate
```

Performs these checks:
1. **Date gaps**: Ensures no missing days within the data range
2. **Time format**: Validates `HH:MM` format with valid hours (0-23) and minutes (0-59)
3. **Chronological order**: Ensures `fajr < sunrise < dhuhr < asr < asr_2 < magrib < isha`

#### `add <year>` - Add a Year's Data

```bash
dart run bin/london_times_cli.dart add 2027
dart run bin/london_times_cli.dart add 2027 --dry-run      # Preview without writing
dart run bin/london_times_cli.dart add 2027 --no-backup    # Skip backup file
dart run bin/london_times_cli.dart add 2027 --api-key=XXX  # Custom API key
```

This command:
1. Fetches the year's data from the API (with `&24hours=true`)
2. Validates the fetched data
3. Merges with existing data (replaces if year already exists)
4. Validates the merged data
5. Creates a `.bak` backup file (unless `--no-backup`)
6. Writes the updated data file

#### `remove <year>` - Remove a Year's Data

```bash
dart run bin/london_times_cli.dart remove 2024
dart run bin/london_times_cli.dart remove 2024 --dry-run
```

### File Format After Writing

The CLI writes the data file with:
- Dates sorted in descending order (newest first) for readability
- 2-space JSON indentation
- Wrapped in Dart raw string constant syntax

## Implementation Notes for Other Languages

When implementing this feature in other languages, consider:

### 1. Data Storage

Store the JSON as an embedded string constant in your language's equivalent format:
- **Swift**: Multi-line string literal
- **Kotlin**: Raw string (`"""..."""`)
- **JavaScript/TypeScript**: Template literal or JSON file
- **Python**: Multi-line string or separate JSON file

### 2. CLI Tool Structure

Implement these core functions:
- **Parse data file**: Extract JSON from the language-specific wrapper
- **Write data file**: Re-wrap JSON in language-specific format
- **Fetch from API**: HTTP GET with proper parameters
- **Validate data**: Check gaps, format, chronological order
- **Merge data**: Combine existing + new, handling year replacement

### 3. Validation Rules

Chronological order check (all times should be strictly increasing):
```
fajr < sunrise < dhuhr < asr < asr_2 < magrib < isha
```

Time format regex: `^\d{2}:\d{2}$` with hours 0-23 and minutes 0-59.

### 4. API Key

The current API key is embedded in the CLI tool. For other implementations, you may want to:
- Use the same key (if permitted by the API provider)
- Request your own key from londonprayertimes.com
- Support environment variable or config file for the key

### 5. Backup Strategy

Before modifying the data file, create a backup (e.g., `.bak` extension) to allow easy rollback if something goes wrong.

## Annual Maintenance Process

Each year, typically in December or early January:

1. Run `info` to check current data coverage
2. Run `add <next_year>` to fetch and add new year's data
3. Run `validate` to confirm data integrity
4. Run tests to ensure nothing broke
5. Commit and release

Optionally, remove old years that are no longer needed:
```bash
dart run bin/london_times_cli.dart remove 2023
```

## Troubleshooting

### API Returns Empty or Error

- Check if the API key is valid
- Verify the year is available (API may not have future years until late in the current year)
- Check network connectivity

### Validation Errors After Fetch

- If chronological order errors occur, the API data may have issues
- Report to londonprayertimes.com if data appears incorrect
- As a workaround, manually fix specific entries if needed

### Large File Size

Each year adds ~5,500 lines to the data file. If size becomes a concern:
- Consider removing years older than 2 years
- Or split into separate files per year (requires code changes)
