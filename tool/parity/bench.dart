import 'dart:io';

import 'bench_base.dart' show printLondonMedian;
import 'grid.dart';

void main(List<String> arguments) {
  final GridOptions options;
  try {
    options = GridOptions.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\nusage: bench.dart ${GridOptions.usage}');
    exit(2);
  }
  printLondonMedian(options.parameters('mwl_mid'));
}
