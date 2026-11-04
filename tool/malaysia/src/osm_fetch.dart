import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'gzip_input.dart';
import 'osm_snapshot.dart';

const _rounds = 3;

Future<bool> fetchOsmSnapshot(Directory root,
    {List<String> endpoints = overpassEndpoints,
    Duration pause = const Duration(seconds: 60)}) async {
  final target = File('${root.path}/tool/malaysia/raw/$osmSnapshotFile');
  Map<String, int>? committedRings;
  if (target.existsSync()) {
    try {
      committedRings =
          _ringCounts(OsmSnapshot.parse(utf8.decode(readGzipInput(target))));
    } on FormatException catch (error) {
      print('${target.path}: ${error.message}; kept it and fetched nothing');
      return false;
    }
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
  try {
    for (var round = 0; round < _rounds; round++) {
      for (final endpoint in endpoints) {
        final body = await _post(client, endpoint, osmSnapshotDate);
        if (body == null) continue;
        try {
          final snapshot = OsmSnapshot.parse(utf8.decode(body));
          print('$endpoint answered with ${snapshot.rings.length} rings, '
              'osm_base ${snapshot.timestamp}');
          _requireComplete(snapshot, committedRings);
        } on FormatException catch (error) {
          print('$endpoint: ${error.message}; wrote nothing');
          continue;
        }
        target.writeAsBytesSync(GZipCodec(level: 9).encode(body));
        print('wrote ${target.path}');
        return true;
      }
      final wait = pause * (round + 1);
      print('no endpoint returned a usable snapshot; '
          'waiting ${wait.inSeconds} s');
      await Future<void>.delayed(wait);
    }
    print('no Overpass endpoint returned a usable snapshot for '
        '$osmSnapshotDate');
    return false;
  } finally {
    client.close(force: true);
  }
}

Map<String, int> _ringCounts(OsmSnapshot snapshot) {
  final counts = <String, int>{};
  for (final ring in snapshot.rings) {
    final key = '${ring.iso} ${ring.inner ? 'inner' : 'outer'}';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

void _requireComplete(OsmSnapshot snapshot, Map<String, int>? committedRings) {
  final base = DateTime.tryParse(snapshot.timestamp);
  if (base == null || base.isBefore(DateTime.parse(osmSnapshotDate))) {
    throw FormatException('osm_base ${snapshot.timestamp} is before the '
        'pinned date $osmSnapshotDate');
  }
  final counts = _ringCounts(snapshot);
  committedRings?.forEach((key, committed) {
    final found = counts[key] ?? 0;
    if (found < committed) {
      throw FormatException('$key has $found rings where the committed '
          'snapshot has $committed');
    }
  });
}

Future<List<int>?> _post(
    HttpClient client, String endpoint, String date) async {
  final started = DateTime.now().toUtc().toIso8601String();
  try {
    final request = await client.postUrl(Uri.parse(endpoint));
    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    request.headers.set(HttpHeaders.userAgentHeader,
        'adhan-dart-malaysia-zones/1.0 (pinned snapshot of state boundaries)');
    request.write('data=${Uri.encodeQueryComponent(overpassQuery(date))}');
    final response = await request.close().timeout(const Duration(minutes: 20));
    final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    print('$started $endpoint HTTP ${response.statusCode}, '
        '${body.length} bytes');
    return response.statusCode == 200 ? body : null;
  } on IOException catch (error) {
    print('$started $endpoint failed: $error');
    return null;
  } on TimeoutException catch (error) {
    print('$started $endpoint failed: $error');
    return null;
  }
}
