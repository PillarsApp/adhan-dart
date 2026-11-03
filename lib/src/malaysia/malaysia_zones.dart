import '../coordinates.dart';
import '../data/date_components.dart';
import '../data/malaysia_zone_map.dart' as data;
import '../data/malaysia_zones_data.dart';

part 'malaysia_zone.dart';

/// The catalog of official Malaysian prayer time zones.
class MalaysiaZones {
  MalaysiaZones._();

  static final data.MalaysiaZoneMap _map =
      data.MalaysiaZoneMap.parse(malaysiaZonesData);

  static final List<MalaysiaZone> _all = [
    for (final record in _map.zones) MalaysiaZone._(record)
  ];

  static final Map<String, MalaysiaZone> _byCode = {
    for (final zone in _all) zone.code: zone
  };

  /// The zone in force at [coordinates] on [date], or null outside every zone.
  /// A manual-only zone such as SWK09 is never returned here.
  /// Points up to 3.0 km outside Malaysia's land borders can resolve to a
  /// zone, so a caller that must not serve a neighbouring country should also
  /// check the country. See the notes for the public API in
  /// docs/MALAYSIA_TIMES_MAINTENANCE.md.
  static MalaysiaZone? resolve(Coordinates coordinates, DateComponents date) {
    final code = _map.zoneAt(coordinates.latitude, coordinates.longitude, date);
    return code == null ? null : _byCode[code];
  }

  /// Every zone in force on [date], in catalog order, manual-only zones
  /// included.
  static List<MalaysiaZone> on(DateComponents date) => [
        for (final zone in _all)
          if (zone.inForceOn(date)) zone
      ];

  /// The zone with [code], whether or not it is still in force, or null for a
  /// code the data does not know.
  static MalaysiaZone? zone(String code) => _byCode[code];
}
