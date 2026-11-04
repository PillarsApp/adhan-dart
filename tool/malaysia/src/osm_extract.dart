import 'dart:convert';
import 'dart:io';

import 'package:adhan/src/data/malaysia_zone_map.dart';
import 'package:crypto/crypto.dart';

import 'geometry.dart';
import 'gzip_input.dart';
import 'osm_snapshot.dart';

const osmBorderFeaturesFile = 'openstreetmap-MYS-border-features.tsv.gz';
const osmOffMapFeaturesFile = 'openstreetmap-MYS-offmap-features.tsv.gz';
const osmExtractUrl = 'https://download.geofabrik.de/asia/'
    'malaysia-singapore-brunei-261103.osm.pbf';
const osmExtractSha256 =
    '4807c977d1cf559928f41ca004f6e0a51722db0e994d06ab4597088189c60668';
const osmExtractTimestamp = '2026-11-03T21:24:23Z';
const osmExtractReachMetres = 150.0;
const osmOffMapMetres = 400.0;
const osmExtractStays = [
  'hotel',
  'motel',
  'guest_house',
  'hostel',
  'chalet',
  'apartment',
  'camp_site',
  'caravan_site',
  'alpine_hut',
  'wilderness_hut',
];
const osmExtractAmenities = ['school', 'place_of_worship'];
const _header = 'osm_id\tlat\tlon\ttag\tname';

List<String> get osmExtractFilters => [
      'nwr/building',
      'nwr/place',
      'nwr/tourism=${osmExtractStays.join(',')}',
      'nwr/amenity=${osmExtractAmenities.join(',')}',
    ];

class OsmFeature {
  final String id;
  final int lat;
  final int lon;
  final String tag;
  final String name;

  OsmFeature(this.id, this.lat, this.lon, this.tag, this.name);
}

List<OsmFeature> readOsmFeatures(List<int> gzipped) {
  final lines = const LineSplitter().convert(utf8.decode(gzipped));
  if (lines.isEmpty || lines.first != _header) {
    throw const FormatException('not an OpenStreetMap feature extract');
  }
  return [
    for (final line in lines.skip(1))
      if (line.isNotEmpty) _parseRow(line),
  ];
}

OsmFeature _parseRow(String line) {
  final fields = line.split('\t');
  if (fields.length != 5) throw FormatException('malformed row $line');
  return OsmFeature(
      fields[0],
      MalaysiaZoneMap.quantize(double.parse(fields[1])),
      MalaysiaZoneMap.quantize(double.parse(fields[2])),
      fields[3],
      fields[4]);
}

Future<bool> importOsmExtract(Directory root, String pbfPath) async {
  final pbf = File(pbfPath);
  final digest = await sha256.bind(pbf.openRead()).first;
  if (digest.toString() != osmExtractSha256) {
    print('$pbfPath has SHA-256 $digest, not the pinned $osmExtractSha256 '
        'of $osmExtractUrl');
    return false;
  }
  final tool = '${root.path}/tool/malaysia';
  final snapshot = OsmSnapshot.parse(
      utf8.decode(readGzipInput(File('$tool/raw/$osmSnapshotFile'))),
      exceptions: readStateLineExceptions(tool));
  final lines = snapshot.stateLines();
  final districts = readShapes(utf8.decode(readGzipInput(
      File('$tool/raw/geoBoundaries-MYS-ADM2_simplified.geojson.gz'))));
  final land =
      PolygonIndex([for (final shape in districts.values) ...shape.rings]);
  final coast = SegmentIndex();
  for (final shape in districts.values) {
    for (final ring in shape.rings) {
      coast.addRing(ring, 0);
    }
  }
  bool near(SegmentIndex index, int lat, int lon, double metres) =>
      index.near(lat, lon, metres).any((s) =>
          pointSegmentMetres(lat, lon, s[0], s[1], s[2], s[3]) <= metres);

  final work = Directory.systemTemp.createTempSync('osm_extract');
  try {
    final filtered = '${work.path}/filtered.osm.pbf';
    final exported = '${work.path}/features.geojsonseq';
    final config = File('${work.path}/export.json')
      ..writeAsStringSync(jsonEncode({
        'attributes': {'type': true, 'id': true},
        'include_tags': ['building', 'place', 'tourism', 'amenity', 'name'],
      }));
    for (final args in [
      ['tags-filter', pbfPath, ...osmExtractFilters, '-o', filtered],
      [
        'export',
        filtered,
        '-c',
        config.path,
        '-f',
        'geojsonseq',
        '--geometry-types=point,linestring,polygon',
        '-o',
        exported,
      ],
    ]) {
      final ProcessResult result;
      try {
        result = Process.runSync('osmium', args);
      } on ProcessException catch (error) {
        print('osmium is needed to filter the extract: ${error.message}');
        return false;
      }
      if (result.exitCode != 0) {
        print('osmium ${args.first} failed: ${result.stderr}');
        return false;
      }
    }

    final border = <String, OsmFeature>{};
    final offMap = <String, OsmFeature>{};
    var read = 0;
    await for (final line in File(exported)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final json = line.startsWith('\u001e') ? line.substring(1) : line;
      if (json.isEmpty) continue;
      read++;
      final feature = _feature(jsonDecode(json) as Map);
      if (feature == null) continue;
      if (near(lines, feature.lat, feature.lon, osmExtractReachMetres)) {
        border.putIfAbsent(feature.id, () => feature);
      }
      if (snapshot.territoryAt(feature.lat, feature.lon) != null &&
          !land.contains(feature.lat, feature.lon) &&
          !near(coast, feature.lat, feature.lon, osmOffMapMetres)) {
        offMap.putIfAbsent(feature.id, () => feature);
      }
    }
    for (final file in [osmBorderFeaturesFile, osmOffMapFeaturesFile]) {
      final features = file == osmBorderFeaturesFile ? border : offMap;
      final ids = features.keys.toList()..sort();
      final text = StringBuffer('$_header\n');
      for (final f in ids.map((id) => features[id]!)) {
        text.writeln(
            [f.id, degrees(f.lat), degrees(f.lon), f.tag, f.name].join('\t'));
      }
      File('$tool/raw/$file').writeAsBytesSync(
          GZipCodec(level: 9).encode(utf8.encode(text.toString())));
    }
    print('$read features in $pbfPath: ${border.length} within '
        '${osmExtractReachMetres.round()} m of a state line, '
        '${offMap.length} inside a state and more than '
        '${osmOffMapMetres.round()} m outside every district; wrote '
        '$osmBorderFeaturesFile and $osmOffMapFeaturesFile');
    return true;
  } finally {
    work.deleteSync(recursive: true);
  }
}

OsmFeature? _feature(Map feature) {
  final properties = feature['properties'] as Map;
  final tag = _matchingTag(properties);
  if (tag == null) return null;
  final box = [
    double.infinity,
    -double.infinity,
    double.infinity,
    -double.infinity
  ];
  void visit(Object? coordinates) {
    final list = coordinates as List;
    if (list.isNotEmpty && list.first is num) {
      final lon = (list[0] as num).toDouble();
      final lat = (list[1] as num).toDouble();
      if (lat < box[0]) box[0] = lat;
      if (lat > box[1]) box[1] = lat;
      if (lon < box[2]) box[2] = lon;
      if (lon > box[3]) box[3] = lon;
      return;
    }
    list.forEach(visit);
  }

  visit((feature['geometry'] as Map)['coordinates']);
  final lat = MalaysiaZoneMap.quantize((box[0] + box[1]) / 2);
  final lon = MalaysiaZoneMap.quantize((box[2] + box[3]) / 2);
  final type = properties['@type'] as String;
  final name = (properties['name'] as String? ?? '')
      .replaceAll(RegExp(r'[\t\r\n]'), ' ');
  return OsmFeature('${type[0]}${properties['@id']}', lat, lon, tag, name);
}

String? _matchingTag(Map properties) {
  final tourism = properties['tourism'];
  if (osmExtractStays.contains(tourism)) return 'tourism=$tourism';
  final amenity = properties['amenity'];
  if (osmExtractAmenities.contains(amenity)) return 'amenity=$amenity';
  for (final key in const ['place', 'building']) {
    final value = properties[key];
    if (value is String && value != 'no') return '$key=$value';
  }
  return null;
}
