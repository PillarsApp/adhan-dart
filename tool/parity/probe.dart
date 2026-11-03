import 'dart:io';

import 'grid.dart';

/// Prints the parity grid as CSV, in the format of the adhan-swift probe at
/// `Tests/Probe`, so the two libraries can be compared cell by cell.
///
/// usage: dart run tool/parity/probe.dart [--polar aqrabBalad|aqrabYaum|unresolved] [--correction iterative|singlePass]
void main(List<String> arguments) {
  final GridOptions options;
  try {
    options = GridOptions.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\nusage: probe.dart ${GridOptions.usage}');
    exit(2);
  }
  final out = StringBuffer();
  for (final row in gridRows(options)) {
    out.writeln(row);
  }
  stdout.write(out.toString());
}
