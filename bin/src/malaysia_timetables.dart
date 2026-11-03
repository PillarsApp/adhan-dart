import 'dart:io';

import 'malaysia_manifest.dart';

Future<void> fetchTimetables(Directory root, List<int> years,
    {bool refresh = false}) async {
  throw UnimplementedError('fetch');
}

void importSelangor(Directory root, List<String> pdfPaths) {
  throw UnimplementedError('import-selangor');
}

DataBuild buildTimetables(Directory root) =>
    DataBuild('', [], [], 'timetables: not built');
