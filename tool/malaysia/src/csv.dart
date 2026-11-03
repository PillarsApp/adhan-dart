import 'dart:io';

List<Map<String, String>> readCsv(File file) {
  final rows = parseCsv(file.readAsStringSync());
  final header = rows.first;
  return [
    for (final row in rows.skip(1))
      if (row.length != header.length)
        throw FormatException('${file.path}: expected ${header.length} '
            'fields, found ${row.length} in ${row.join(',')}')
      else
        {for (var i = 0; i < header.length; i++) header[i]: row[i]},
  ];
}

List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (char == '"') {
        quoted = false;
      } else {
        field.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (char != '\r') {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows.where((row) => row.length > 1 || row.first.isNotEmpty).toList();
}
