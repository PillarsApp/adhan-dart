import 'dart:io';

import 'package:adhan/src/data/date_components.dart';

import 'malaysia_manifest.dart';

DataBuild buildZones(Directory root) =>
    DataBuild('', [], [], 'zones: not built');

String? lookupZone(double latitude, double longitude, DateComponents date) =>
    throw UnimplementedError('lookup');
