#!/usr/bin/env dart
/// CLI tool for managing London prayer times data.
///
/// Usage:
///   dart run bin/london_times_cli.dart <command> [options]
///
/// Commands:
///   info      Show statistics about the current data
///   validate  Validate the data file for errors
///   add       Fetch and add a year's data from the API
///   remove    Remove a year's data from the file
///
/// Run with --help for more details.

import 'dart:convert';
import 'dart:io';

const String defaultApiKey = '12181c35-b4c7-4b8b-9bab-1f7ea8fee28a';
const String dataFilePath = 'lib/src/data/london_times_data.dart';

// Prayer time fields that should be in chronological order
const List<String> chronologicalFields = [
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'asr_2',
  'magrib',
  'isha',
];


void main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    printUsage();
    return;
  }

  final command = args[0];
  final options = args.sublist(1);

  switch (command) {
    case 'info':
      await infoCommand();
      break;
    case 'validate':
      await validateCommand();
      break;
    case 'add':
      await addCommand(options);
      break;
    case 'remove':
      await removeCommand(options);
      break;
    default:
      print('Unknown command: $command');
      printUsage();
      exit(1);
  }
}

void printUsage() {
  print('''
London Prayer Times Data CLI

Usage:
  dart run bin/london_times_cli.dart <command> [options]

Commands:
  info                    Show statistics about the current data
  validate                Validate the data file for errors
  add <year> [options]    Fetch and add a year's data from the API
  remove <year> [options] Remove a year's data from the file

Add Options:
  --api-key=<key>    Use a custom API key (default: built-in key)
  --dry-run          Preview changes without writing to file
  --no-backup        Skip creating a backup file

Remove Options:
  --dry-run          Preview changes without writing to file
  --no-backup        Skip creating a backup file

Examples:
  dart run bin/london_times_cli.dart info
  dart run bin/london_times_cli.dart validate
  dart run bin/london_times_cli.dart add 2026
  dart run bin/london_times_cli.dart add 2026 --dry-run
  dart run bin/london_times_cli.dart remove 2024 --dry-run
''');
}

/// Parse the existing data file and extract the JSON
Map<String, dynamic> parseDataFile() {
  final file = File(dataFilePath);
  if (!file.existsSync()) {
    throw Exception('Data file not found: $dataFilePath');
  }

  final content = file.readAsStringSync();

  // Extract JSON from the Dart string constant
  final startMarker = "r'''";
  final endMarker = "'''";

  final startIndex = content.indexOf(startMarker);
  if (startIndex == -1) {
    throw Exception('Could not find start of JSON in data file');
  }

  final jsonStart = startIndex + startMarker.length;
  final endIndex = content.indexOf(endMarker, jsonStart);
  if (endIndex == -1) {
    throw Exception('Could not find end of JSON in data file');
  }

  final jsonString = content.substring(jsonStart, endIndex).trim();
  return jsonDecode(jsonString) as Map<String, dynamic>;
}

/// Write the data back to the file
void writeDataFile(Map<String, dynamic> data, {bool backup = true}) {
  final file = File(dataFilePath);

  if (backup && file.existsSync()) {
    final backupPath = '$dataFilePath.bak';
    file.copySync(backupPath);
    print('Backup created: $backupPath');
  }

  // Sort the times by date (newest first for readability)
  final times = data['times'] as Map<String, dynamic>;
  final sortedKeys = times.keys.toList()..sort((a, b) => b.compareTo(a));
  final sortedTimes = <String, dynamic>{};
  for (final key in sortedKeys) {
    sortedTimes[key] = times[key];
  }
  data['times'] = sortedTimes;

  final encoder = JsonEncoder.withIndent('  ');
  final jsonString = encoder.convert(data);

  final dartContent = '''const String londonPrayerTimesData = r\'\'\'
$jsonString
\'\'\';
''';

  file.writeAsStringSync(dartContent);
  print('Data file updated: $dataFilePath');
}

/// Get all years present in the data
Set<int> getYearsInData(Map<String, dynamic> data) {
  final times = data['times'] as Map<String, dynamic>;
  final years = <int>{};
  for (final dateStr in times.keys) {
    final year = int.tryParse(dateStr.split('-')[0]);
    if (year != null) {
      years.add(year);
    }
  }
  return years;
}

/// Date range result class (for Dart 2.x compatibility)
class DateRange {
  final DateTime? minDate;
  final DateTime? maxDate;
  DateRange(this.minDate, this.maxDate);
}

/// Get date range for a specific year in the data
DateRange getDateRangeForYear(Map<String, dynamic> data, int year) {
  final times = data['times'] as Map<String, dynamic>;
  DateTime? minDate;
  DateTime? maxDate;

  for (final dateStr in times.keys) {
    if (dateStr.startsWith('$year-')) {
      final date = DateTime.parse(dateStr);
      if (minDate == null || date.isBefore(minDate)) {
        minDate = date;
      }
      if (maxDate == null || date.isAfter(maxDate)) {
        maxDate = date;
      }
    }
  }

  return DateRange(minDate, maxDate);
}

/// Info command - show statistics
Future<void> infoCommand() async {
  print('Loading data file...\n');

  final data = parseDataFile();
  final times = data['times'] as Map<String, dynamic>;
  final years = getYearsInData(data);

  print('=== London Prayer Times Data Statistics ===\n');
  print('City: ${data['city']}');
  print('Total entries: ${times.length}');
  print('Years covered: ${years.toList()..sort()}');
  print('');

  for (final year in (years.toList()..sort())) {
    final range = getDateRangeForYear(data, year);
    final count =
        times.keys.where((d) => d.startsWith('$year-')).length;
    print(
        '  $year: $count entries (${_formatDate(range.minDate!)} to ${_formatDate(range.maxDate!)})');
  }

  // Check for overall date range
  final allDates = times.keys.map((d) => DateTime.parse(d)).toList()..sort();
  if (allDates.isNotEmpty) {
    print('\nOverall range: ${_formatDate(allDates.first)} to ${_formatDate(allDates.last)}');
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Validate command - check for errors
Future<void> validateCommand() async {
  print('Validating data file...\n');

  final data = parseDataFile();
  final errors = validateData(data);

  if (errors.isEmpty) {
    print('✓ No errors found! Data is valid.');
  } else {
    print('✗ Found ${errors.length} error(s):\n');
    for (final error in errors) {
      print('  - $error');
    }
    exit(1);
  }
}

/// Validate the data and return list of errors
List<String> validateData(Map<String, dynamic> data) {
  final errors = <String>[];
  final times = data['times'] as Map<String, dynamic>;

  // Get all dates and sort them
  final dates = times.keys.map((d) => DateTime.parse(d)).toList()..sort();

  if (dates.isEmpty) {
    errors.add('No dates found in data');
    return errors;
  }

  // Check for date gaps
  for (var i = 0; i < dates.length - 1; i++) {
    final current = dates[i];
    final next = dates[i + 1];
    final expectedNext = current.add(Duration(days: 1));

    if (next != expectedNext) {
      // Check if this is a gap within the same year range
      if (current.year == next.year ||
          (current.month == 12 && next.month == 1)) {
        final gapDays = next.difference(current).inDays - 1;
        if (gapDays > 0) {
          errors.add(
              'Gap of $gapDays day(s) between ${_formatDate(current)} and ${_formatDate(next)}');
        }
      }
    }
  }

  // Validate each entry
  for (final entry in times.entries) {
    final dateStr = entry.key;
    final dayData = entry.value as Map<String, dynamic>;

    // Check time format
    for (final field in dayData.entries) {
      if (field.key == 'date') continue;

      final value = field.value as String;
      if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
        errors.add('Invalid time format for $dateStr ${field.key}: $value');
        continue;
      }

      final parts = value.split(':');
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);

      if (hours < 0 || hours > 23) {
        errors.add('Invalid hours for $dateStr ${field.key}: $value');
      }
      if (minutes < 0 || minutes > 59) {
        errors.add('Invalid minutes for $dateStr ${field.key}: $value');
      }
    }

    // Check chronological order
    final chronoErrors = validateChronologicalOrder(dateStr, dayData);
    errors.addAll(chronoErrors);
  }

  return errors;
}

/// Validate that prayer times are in chronological order
List<String> validateChronologicalOrder(
    String dateStr, Map<String, dynamic> dayData) {
  final errors = <String>[];

  int? previousMinutes;
  String? previousField;

  for (final field in chronologicalFields) {
    final value = dayData[field] as String?;
    if (value == null) continue;

    final parts = value.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final totalMinutes = hours * 60 + minutes;

    if (previousMinutes != null && totalMinutes <= previousMinutes) {
      errors.add(
          '$dateStr: $field ($value) should be after $previousField (${dayData[previousField]})');
    }

    previousMinutes = totalMinutes;
    previousField = field;
  }

  return errors;
}

/// Add command - fetch and add a year
Future<void> addCommand(List<String> options) async {
  if (options.isEmpty) {
    print('Error: Year is required. Usage: add <year> [options]');
    exit(1);
  }

  final year = int.tryParse(options[0]);
  if (year == null || year < 2000 || year > 2100) {
    print('Error: Invalid year: ${options[0]}');
    exit(1);
  }

  // Parse options
  var apiKey = defaultApiKey;
  var dryRun = false;
  var backup = true;

  for (final opt in options.skip(1)) {
    if (opt.startsWith('--api-key=')) {
      apiKey = opt.substring('--api-key='.length);
    } else if (opt == '--dry-run') {
      dryRun = true;
    } else if (opt == '--no-backup') {
      backup = false;
    }
  }

  print('Fetching data for year $year...');

  // Fetch from API
  final apiData = await fetchYearData(year, apiKey);
  if (apiData == null) {
    print('Error: Failed to fetch data from API');
    exit(1);
  }

  print('Fetched ${(apiData['times'] as Map).length} entries');

  // Validate fetched data (API returns 24-hour format with &24hours=true)
  print('Validating fetched data...');
  final fetchErrors = validateData(apiData);
  if (fetchErrors.isNotEmpty) {
    print('Warning: Fetched data has ${fetchErrors.length} validation error(s):');
    for (final error in fetchErrors.take(5)) {
      print('  - $error');
    }
    if (fetchErrors.length > 5) {
      print('  ... and ${fetchErrors.length - 5} more');
    }
  }

  // Load existing data
  print('Loading existing data...');
  final existingData = parseDataFile();
  final existingYears = getYearsInData(existingData);

  if (existingYears.contains(year)) {
    print('Warning: Year $year already exists in data. Will be replaced.');
  }

  // Merge data
  print('Merging data...');
  final mergedData = mergeData(existingData, apiData, year);

  // Validate merged data
  print('Validating merged data...');
  final mergedErrors = validateData(mergedData);
  if (mergedErrors.isNotEmpty) {
    print('Warning: Merged data has ${mergedErrors.length} validation error(s):');
    for (final error in mergedErrors.take(5)) {
      print('  - $error');
    }
    if (mergedErrors.length > 5) {
      print('  ... and ${mergedErrors.length - 5} more');
    }
  }

  // Show summary
  final newCount = (mergedData['times'] as Map).length;
  final oldCount = (existingData['times'] as Map).length;
  print('\nSummary:');
  print('  Entries before: $oldCount');
  print('  Entries after: $newCount');
  print('  Net change: ${newCount - oldCount}');

  if (dryRun) {
    print('\n[DRY RUN] No changes written to disk.');
  } else {
    writeDataFile(mergedData, backup: backup);
    print('\nDone! Year $year data has been added.');
  }
}

/// Fetch year data from API
Future<Map<String, dynamic>?> fetchYearData(int year, String apiKey) async {
  final url = Uri.parse(
      'https://www.londonprayertimes.com/api/times/?format=json&key=$apiKey&year=$year&24hours=true');

  try {
    final client = HttpClient();
    final request = await client.getUrl(url);
    final response = await request.close();

    if (response.statusCode != 200) {
      print('API returned status code: ${response.statusCode}');
      return null;
    }

    final body = await response.transform(utf8.decoder).join();
    client.close();

    return jsonDecode(body) as Map<String, dynamic>;
  } catch (e) {
    print('Error fetching data: $e');
    return null;
  }
}

/// Merge new year data into existing data
Map<String, dynamic> mergeData(
    Map<String, dynamic> existing, Map<String, dynamic> newData, int year) {
  final existingTimes = Map<String, dynamic>.from(existing['times'] as Map);
  final newTimes = newData['times'] as Map<String, dynamic>;

  // Remove existing entries for the year
  existingTimes.removeWhere((key, _) => key.startsWith('$year-'));

  // Add new entries
  existingTimes.addAll(newTimes);

  return {
    'city': existing['city'],
    'times': existingTimes,
  };
}

/// Remove command - remove a year
Future<void> removeCommand(List<String> options) async {
  if (options.isEmpty) {
    print('Error: Year is required. Usage: remove <year> [options]');
    exit(1);
  }

  final year = int.tryParse(options[0]);
  if (year == null || year < 2000 || year > 2100) {
    print('Error: Invalid year: ${options[0]}');
    exit(1);
  }

  // Parse options
  var dryRun = false;
  var backup = true;

  for (final opt in options.skip(1)) {
    if (opt == '--dry-run') {
      dryRun = true;
    } else if (opt == '--no-backup') {
      backup = false;
    }
  }

  print('Loading existing data...');
  final existingData = parseDataFile();
  final existingYears = getYearsInData(existingData);

  if (!existingYears.contains(year)) {
    print('Error: Year $year not found in data');
    print('Available years: ${existingYears.toList()..sort()}');
    exit(1);
  }

  final existingTimes = Map<String, dynamic>.from(existingData['times'] as Map);
  final entriesToRemove =
      existingTimes.keys.where((k) => k.startsWith('$year-')).toList();

  print('Found ${entriesToRemove.length} entries to remove for year $year');

  // Remove entries
  for (final key in entriesToRemove) {
    existingTimes.remove(key);
  }

  final updatedData = {
    'city': existingData['city'],
    'times': existingTimes,
  };

  print('\nSummary:');
  print('  Entries before: ${(existingData['times'] as Map).length}');
  print('  Entries after: ${existingTimes.length}');
  print('  Removed: ${entriesToRemove.length}');

  if (dryRun) {
    print('\n[DRY RUN] No changes written to disk.');
  } else {
    writeDataFile(updatedData, backup: backup);
    print('\nDone! Year $year data has been removed.');
  }
}
