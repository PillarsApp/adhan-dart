import 'dart:io';

import 'grid.dart';

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
