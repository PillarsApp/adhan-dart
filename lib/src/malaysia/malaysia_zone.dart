part of 'malaysia_zones.dart';

/// An official Malaysian prayer time zone.
class MalaysiaZone {
  final data.MalaysiaZone _record;

  MalaysiaZone._(this._record);

  /// The zone code, such as WLY01. e-Solat publishes it, except for the nine
  /// Selangor district zones, whose codes are provisional because JAKIM has
  /// not published any.
  String get code => _record.code;

  /// The state or federal territory the zone belongs to.
  String get state => _record.state;

  /// The districts and places the zone covers, as published.
  String get areas => _record.areas;

  /// The first day the zone is in force, or null when it has always been.
  DateComponents? get validFrom =>
      _record.validFromDay == 0 ? null : _date(_record.validFromDay);

  /// The last day the zone is in force, or null when it has no end.
  DateComponents? get validTo =>
      _record.validToDay == 99999999 ? null : _date(_record.validToDay);

  /// The GeoNames position of the zone's first named town, or the centre of
  /// its special area, such as a summit, a hill, an island or a pass. The
  /// Hanafi shift of Asr is calculated here. It need not resolve to this zone: the point of SWK09, which has no
  /// geometry, resolves to SWK01.
  Coordinates get referencePoint =>
      Coordinates(_record.referenceLatitude, _record.referenceLongitude);

  /// The zones that replace this one after [validTo], empty for a zone still
  /// in force.
  List<MalaysiaZone> get successors =>
      [for (final code in _record.successors) MalaysiaZones._byCode[code]!];

  bool inForceOn(DateComponents date) => _record.inForceOn(date);

  static DateComponents _date(int yyyymmdd) =>
      DateComponents(yyyymmdd ~/ 10000, yyyymmdd ~/ 100 % 100, yyyymmdd % 100);

  @override
  bool operator ==(Object other) => other is MalaysiaZone && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'MalaysiaZone($code)';
}
