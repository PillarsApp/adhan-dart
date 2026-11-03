import 'package:crypto/crypto.dart';

class ManifestEntry {
  final String kind;
  final String name;
  final String retrieved;
  final String url;
  final String sha256;

  ManifestEntry(this.kind, this.name, this.retrieved, this.url, this.sha256);
}

class DataBuild {
  final String output;
  final List<String> errors;
  final List<ManifestEntry> sources;
  final String summary;

  DataBuild(this.output, this.errors, this.sources, this.summary);
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String renderManifest(
    Map<String, List<int>> outputs, List<ManifestEntry> sources) {
  final rows = <List<String>>[
    ['kind', 'name', 'retrieved', 'url', 'sha256'],
    for (final file in outputs.keys)
      ['output', file, '', '', sha256Hex(outputs[file]!)],
    for (final source in sources)
      [source.kind, source.name, source.retrieved, source.url, source.sha256],
  ];
  return rows.map((row) => '${row.join('\t')}\n').join();
}
