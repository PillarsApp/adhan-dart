import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

final _kualaLumpur = Coordinates(3.1390, 101.6869);
final _kotaKinabalu = Coordinates(5.9749, 116.0724);
final _singapore = Coordinates(1.3521, 103.8198);
final _nov2 = DateComponents(2026, 11, 2);

final _source = MalaysiaTimetable.source;

CalculationParameters _official({String? zone}) =>
    CalculationMethod.malaysia_official.getParameters()..malaysiaZone = zone;

void main() {
  test('the source names its authority and revision', () {
    expect(_source.authority, 'jakim');
    expect(_source.revision, MalaysiaTimetable.revision);
  });

  test('Kuala Lumpur on 2026-11-02 is the WLY01 row', () {
    final lookup = _source.lookup(_kualaLumpur, _nov2);
    expect(lookup, isA<OfficialRow>());
    final row = lookup as OfficialRow;
    expect(row.locality.id, LocalityId('WLY01'));
    expect(row.date, _nov2);
    expect(row.authority, 'jakim');
    expect(row.revision, MalaysiaTimetable.revision);
    expect(row.asrShadow, 1);
    expect(row.utcOffset, Duration(hours: 8));
    expect(row.columns.map((c) => c.name), [
      'imsak',
      'fajr',
      'sunrise',
      'dhuha',
      'dhuhr',
      'asr',
      'maghrib',
      'isha'
    ]);
    expect(row.published(PublishedColumn.asrHanafi), isNull);
    expect(row.published(PublishedColumn.eid), isNull);
    final day = MalaysiaTimetable.day(MalaysiaZones.zone('WLY01')!, _nov2,
        utcOffset: Duration())!;
    expect(row.published(PublishedColumn.imsak), day.imsak);
    expect(row.published(PublishedColumn.fajr), day.subuh);
    expect(row.published(PublishedColumn.sunrise), day.syuruk);
    expect(row.published(PublishedColumn.dhuha), day.dhuha);
    expect(row.published(PublishedColumn.dhuhr), day.zohor);
    expect(row.published(PublishedColumn.asr), day.asar);
    expect(row.published(PublishedColumn.maghrib), day.maghrib);
    expect(row.published(PublishedColumn.isha), day.isyak);
    expect(
        row.published(PublishedColumn.fajr), DateTime.utc(2026, 11, 1, 21, 48));
  });

  test('a manual unknown code is no locality', () {
    expect(_source.lookup(_kualaLumpur, _nov2, localityId: LocalityId('XXX00')),
        isA<NoLocality>());
    expect(_source.locality(LocalityId('XXX00')), isNull);
  });

  test('outside Malaysia is no locality', () {
    expect(_source.lookup(_singapore, _nov2), isA<NoLocality>());
    expect(_source.localityAt(_singapore, _nov2), isNull);
  });

  test('Kota Kinabalu in 2027 has no row for SBH07', () {
    final lookup = _source.lookup(_kotaKinabalu, DateComponents(2027, 1, 1));
    expect(lookup, isA<NoRow>());
    expect((lookup as NoRow).locality.id, LocalityId('SBH07'));
  });

  test('a retired zone is a locality with validity and successors', () {
    final selangor = _source.locality(LocalityId('SGR01'))!;
    expect(selangor.group, 'Selangor');
    expect(selangor.validFrom, isNull);
    expect(selangor.validTo, DateComponents(2026, 12, 31));
    expect(selangor.successors.map((id) => id.value),
        ['SGRGBK', 'SGRHLG', 'SGRHSL', 'SGRPTG', 'SGRSPG']);
    expect(selangor.name('ms'), MalaysiaZones.zone('SGR01')!.areas);
    expect(selangor.name('en'), 'SGR01');
    expect(selangor.referencePoint.latitude,
        MalaysiaZones.zone('SGR01')!.referencePoint.latitude);
    expect(selangor.inForceOn(_nov2), isTrue);
    expect(selangor.inForceOn(DateComponents(2027, 1, 1)), isFalse);
    expect(_source.localityAt(_kualaLumpur, _nov2),
        _source.locality(LocalityId('WLY01')));
  });

  test('localities is the whole catalog in catalog order', () {
    final localities = _source.localities.toList();
    expect(localities, hasLength(69));
    expect(localities.map((l) => l.id.value),
        MalaysiaZones.all.map((zone) => zone.code));
    expect(localities.map((l) => l.id.value), contains('SWK09'));
  });

  test('a manual retired zone is used and has no row after its last day', () {
    final lookup = _source.lookup(_kualaLumpur, DateComponents(2027, 3, 1),
        localityId: LocalityId('SGR01'));
    expect(lookup, isA<NoRow>());
    expect((lookup as NoRow).locality.id, LocalityId('SGR01'));
    final automatic = _source.lookup(_kualaLumpur, DateComponents(2027, 3, 1));
    expect(automatic, isA<OfficialRow>());
    expect((automatic as OfficialRow).locality.id, isNot(LocalityId('SGR01')));
  });

  group('the legacy method', () {
    test('exposes the row on an official day', () {
      final times = PrayerTimes.utc(_kualaLumpur, _nov2, _official());
      expect(times.source, PrayerTimesSource.official);
      final row = times.officialRow!;
      expect(row.locality.id, LocalityId('WLY01'));
      expect(times.malaysiaZone, MalaysiaZones.zone('WLY01'));
      expect(times.malaysiaDay!.subuh, row.published(PublishedColumn.fajr));
      expect(times.fajr, row.published(PublishedColumn.fajr));
      final generic = PrayerTimes.official(row,
          parameters: _official(), utcOffset: Duration());
      expect(generic.asr, times.asr);
      expect(generic.isha, times.isha);
    });

    test('has no row on a fallback day', () {
      final noRow = PrayerTimes.utc(
          _kotaKinabalu, DateComponents(2027, 1, 1), _official());
      expect(noRow.source, PrayerTimesSource.calculatedNoRow);
      expect(noRow.officialRow, isNull);
      expect(noRow.malaysiaZone, MalaysiaZones.zone('SBH07'));
      final noZone = PrayerTimes.utc(_singapore, _nov2, _official());
      expect(noZone.source, PrayerTimesSource.calculatedNoZone);
      expect(noZone.officialRow, isNull);
      expect(noZone.malaysiaZone, isNull);
    });
  });
}
