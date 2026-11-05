import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
const osmBorderFeaturesSha256 =
    '53338005b5238c1ac85fa1d9805a63e2b91c12983d2f7b0bd8257efb97606f4a';
const osmOffMapFeaturesSha256 =
    '1cf7c01ebfe31865809c28e00092a6092b61abba5198d3464d2931b72f1ca52a';
const osmExtractReachMetres = 150.0;
const osmOffMapMetres = 400.0;
const outlineSampleMetres = 5.0;
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
const osmExtractCareAndStudy = [
  'kindergarten',
  'college',
  'university',
  'hospital',
  'clinic',
];
const _header = 'osm_id\tlat\tlon\ttag\tname\toutline';

List<String> get osmExtractFilters => [
      'nwr/building',
      'nwr/place',
      'nwr/tourism=${osmExtractStays.join(',')}',
      'nwr/amenity=${[
        ...osmExtractAmenities,
        ...osmExtractCareAndStudy
      ].join(',')}',
      'nwr/leisure=resort',
      'nwr/landuse=residential',
      'nwr/addr:housenumber',
    ];

class OsmFeature {
  final String id;
  final int lat;
  final int lon;
  final String tag;
  final String name;
  final List<List<int>> outline;

  OsmFeature(this.id, this.lat, this.lon, this.tag, this.name, this.outline);

  List<int> get samples =>
      tag.startsWith('place=') ? [lat, lon] : outlineSamples(outline);
}

List<int> outlineSamples(List<List<int>> outline) {
  final seen = <int>{};
  final samples = <int>[];
  void add(int lat, int lon) {
    if (seen.add(vertexKey(lat, lon))) {
      samples
        ..add(lat)
        ..add(lon);
    }
  }

  for (final line in outline) {
    add(line[0], line[1]);
    for (var i = 2; i < line.length; i += 2) {
      final steps =
          (metresBetween(line[i - 2], line[i - 1], line[i], line[i + 1]) /
                  outlineSampleMetres)
              .ceil();
      for (var k = 1; k <= steps; k++) {
        add(line[i - 2] + ((line[i] - line[i - 2]) * k / steps).round(),
            line[i - 1] + ((line[i + 1] - line[i - 1]) * k / steps).round());
      }
    }
  }
  return samples;
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
  if (fields.length != 6 || fields[5].isEmpty) {
    throw FormatException('malformed row $line');
  }
  final outline = [
    for (final part in fields[5].split(' '))
      MalaysiaZoneMap.decodePolyline(part)
  ];
  if (outline.any((line) => line.isEmpty || line.length.isOdd)) {
    throw FormatException('malformed outline in row $line');
  }
  return OsmFeature(
      fields[0],
      MalaysiaZoneMap.quantize(double.parse(fields[1])),
      MalaysiaZoneMap.quantize(double.parse(fields[2])),
      fields[3],
      fields[4],
      outline);
}

String _encodeOutline(List<List<int>> outline) =>
    outline.map(MalaysiaZoneMap.encodePolyline).join(' ');

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
        'include_tags': [
          'building',
          'place',
          'tourism',
          'amenity',
          'leisure',
          'landuse',
          'addr:housenumber',
          'name',
        ],
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
      if (_nearLine(lines, feature)) {
        border.putIfAbsent(feature.id, () => feature);
      }
      if (snapshot.territoryAt(feature.lat, feature.lon) != null &&
          !land.contains(feature.lat, feature.lon) &&
          !near(coast, feature.lat, feature.lon, osmOffMapMetres)) {
        offMap.putIfAbsent(feature.id, () => feature);
      }
    }
    final pins = {
      osmBorderFeaturesFile: osmBorderFeaturesSha256,
      osmOffMapFeaturesFile: osmOffMapFeaturesSha256,
    };
    for (final file in pins.keys) {
      final features = file == osmBorderFeaturesFile ? border : offMap;
      final ids = features.keys.toList()..sort();
      final text = StringBuffer('$_header\n');
      for (final f in ids.map((id) => features[id]!)) {
        text.writeln([
          f.id,
          degrees(f.lat),
          degrees(f.lon),
          f.tag,
          f.name,
          _encodeOutline(f.outline)
        ].join('\t'));
      }
      final bytes = utf8.encode(text.toString());
      File('$tool/raw/$file')
          .writeAsBytesSync(GZipCodec(level: 9).encode(bytes));
      final digest = sha256.convert(bytes).toString();
      if (digest != pins[file]) {
        print('$file has SHA-256 $digest, not the pinned ${pins[file]}; '
            'build rejects it until the pin in tool/malaysia/src/'
            'osm_extract.dart names it');
      }
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

bool _nearLine(SegmentIndex lines, OsmFeature feature) {
  final box = [1 << 40, -(1 << 40), 1 << 40, -(1 << 40)];
  for (final line in feature.outline) {
    final b = ringBounds(line);
    box[0] = math.min(box[0], b[0]);
    box[1] = math.max(box[1], b[1]);
    box[2] = math.min(box[2], b[2]);
    box[3] = math.max(box[3], b[3]);
  }
  final reach = osmExtractReachMetres +
      metresBetween(box[0], box[2], box[1], box[3]) / 2 +
      1;
  bool within(int lat, int lon, double metres) =>
      lines.near(lat, lon, metres).any((s) =>
          pointSegmentMetres(lat, lon, s[0], s[1], s[2], s[3]) <= metres);
  if (!within(feature.lat, feature.lon, reach)) return false;
  final samples = feature.samples;
  for (var i = 0; i < samples.length; i += 2) {
    if (within(samples[i], samples[i + 1], osmExtractReachMetres)) return true;
  }
  return false;
}

OsmFeature? _feature(Map feature) {
  final properties = feature['properties'] as Map;
  final tag = _matchingTag(properties);
  if (tag == null) return null;
  final outline = <List<int>>[];
  final box = [
    double.infinity,
    -double.infinity,
    double.infinity,
    -double.infinity
  ];
  List<int> quantized(List points) {
    final line = <int>[];
    for (final point in points) {
      final lat = ((point as List)[1] as num).toDouble();
      final lon = (point[0] as num).toDouble();
      if (lat < box[0]) box[0] = lat;
      if (lat > box[1]) box[1] = lat;
      if (lon < box[2]) box[2] = lon;
      if (lon > box[3]) box[3] = lon;
      final quantizedLat = MalaysiaZoneMap.quantize(lat);
      final quantizedLon = MalaysiaZoneMap.quantize(lon);
      final n = line.length;
      if (n >= 2 &&
          line[n - 2] == quantizedLat &&
          line[n - 1] == quantizedLon) {
        continue;
      }
      line
        ..add(quantizedLat)
        ..add(quantizedLon);
    }
    return line;
  }

  void visit(List coordinates) {
    if (coordinates.first is num) {
      outline.add(quantized([coordinates]));
    } else if ((coordinates.first as List).first is num) {
      outline.add(quantized(coordinates));
    } else {
      for (final part in coordinates) {
        visit(part as List);
      }
    }
  }

  visit((feature['geometry'] as Map)['coordinates'] as List);
  final type = properties['@type'] as String;
  final name = (properties['name'] as String? ?? '')
      .replaceAll(RegExp(r'[\t\r\n]'), ' ');
  return OsmFeature(
      '${type[0]}${properties['@id']}',
      MalaysiaZoneMap.quantize((box[0] + box[1]) / 2),
      MalaysiaZoneMap.quantize((box[2] + box[3]) / 2),
      tag,
      name,
      outline);
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
  if (osmExtractCareAndStudy.contains(amenity)) return 'amenity=$amenity';
  if (properties['leisure'] == 'resort') return 'leisure=resort';
  final name = properties['name'];
  if (properties['landuse'] == 'residential' &&
      name is String &&
      name.isNotEmpty) {
    return 'landuse=residential';
  }
  if (properties['addr:housenumber'] is String) return 'addr:housenumber';
  return null;
}
