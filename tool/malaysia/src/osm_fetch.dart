import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'osm_snapshot.dart';

const _rounds = 3;

Future<bool> fetchOsmSnapshot(Directory root) async {
  final target = File('${root.path}/tool/malaysia/raw/$osmSnapshotFile');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
  try {
    for (var round = 0; round < _rounds; round++) {
      for (final endpoint in overpassEndpoints) {
        final body = await _post(client, endpoint, osmSnapshotDate);
        if (body == null) continue;
        try {
          final snapshot = OsmSnapshot.parse(utf8.decode(body));
          print('$endpoint answered with ${snapshot.rings.length} rings, '
              'osm_base ${snapshot.timestamp}');
        } on FormatException catch (error) {
          print('$endpoint: ${error.message}');
          continue;
        }
        target.writeAsBytesSync(GZipCodec(level: 9).encode(body));
        print('wrote ${target.path}');
        return true;
      }
      final pause = Duration(seconds: 60 * (round + 1));
      print('every endpoint refused; waiting ${pause.inSeconds} s');
      await Future<void>.delayed(pause);
    }
    print('no Overpass endpoint answered the pinned query for '
        '$osmSnapshotDate');
    return false;
  } finally {
    client.close(force: true);
  }
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
