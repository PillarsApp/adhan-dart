import 'dart:io';

import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

final _riyadh = Coordinates(24.7136, 46.6753);
final _firstDay = DateComponents(2026, 1, 1);

CalculationParameters _parameters({Madhab madhab = Madhab.shafi}) =>
    CalculationMethod.umm_al_qura.getParameters()..madhab = madhab;

List<DateTime> _six(PrayerTimes times) => [
      times.fajr,
      times.sunrise,
      times.dhuhr,
      times.asr,
      times.maghrib,
      times.isha
    ];

void main() {
  final timetable = PublishedTimetable.decode(
      File('test/published/vectors/valid/kacst-like.ott').readAsBytesSync());
  final row = timetable.lookup(_riyadh, _firstDay) as OfficialRow;

  test('official times carry their source and row', () {
    final times = PrayerTimes.official(row, parameters: _parameters());
    expect(times.source, PrayerTimesSource.official);
    expect(times.source.isOfficial, isTrue);
    expect(times.officialRow, same(row));
    expect(times.coordinates, row.locality.referencePoint);
    expect(times.dateComponents, _firstDay);
    expect(times.malaysiaZone, isNull);
    expect(times.malaysiaDay, isNull);
  });

  test('user adjustments move only their prayer', () {
    final plain = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    final adjusted = PrayerTimes.official(row,
        parameters: _parameters(),
        adjustments: PrayerAdjustments(
            fajr: 1, sunrise: -2, dhuhr: 3, asr: -4, maghrib: 5, isha: -6),
        utcOffset: Duration());
    final shifts = [1, -2, 3, -4, 5, -6];
    for (var i = 0; i < 6; i++) {
      expect(
          _six(adjusted)[i], _six(plain)[i].add(Duration(minutes: shifts[i])));
    }
  });

  test('the Asr adjustment is added after the Hanafi shift', () {
    final hanafi = PrayerTimes.official(row,
        parameters: _parameters(madhab: Madhab.hanafi), utcOffset: Duration());
    final adjusted = PrayerTimes.official(row,
        parameters: _parameters(madhab: Madhab.hanafi),
        adjustments: PrayerAdjustments(asr: 7),
        utcOffset: Duration());
    expect(hanafi.asr, DateTime.utc(2026, 1, 1, 12, 41));
    expect(adjusted.asr, hanafi.asr.add(Duration(minutes: 7)));
  });

  test('adjustments default to the adjustments in the parameters', () {
    final shifts = PrayerAdjustments(fajr: 2, isha: -3);
    final fromParameters = PrayerTimes.official(row,
        parameters: _parameters()..adjustments = shifts, utcOffset: Duration());
    final explicit = PrayerTimes.official(row,
        parameters: _parameters(), adjustments: shifts, utcOffset: Duration());
    expect(_six(fromParameters), _six(explicit));
    expect(fromParameters.fajr,
        row.published(PublishedColumn.fajr)!.add(Duration(minutes: 2)));
  });

  test('method adjustments move nothing', () {
    final plain = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    final withMethod = PrayerTimes.official(row,
        parameters: _parameters().withMethodAdjustments(PrayerAdjustments(
            fajr: 10, sunrise: 10, dhuhr: 10, asr: 10, maghrib: 10, isha: 10)),
        utcOffset: Duration());
    expect(_six(withMethod), _six(plain));
  });

  test('SunnahTimes works on official times, with tomorrow calculated', () {
    final times = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    final sunnah = SunnahTimes(times);
    final tomorrow = PrayerTimes.utc(
        row.locality.referencePoint, DateComponents(2026, 1, 2), _parameters());
    final night = tomorrow.fajr.difference(times.maghrib);
    final midpoint =
        times.maghrib.add(Duration(microseconds: night.inMicroseconds ~/ 2));
    expect(sunnah.middleOfTheNight.second, 0);
    expect(sunnah.middleOfTheNight.difference(midpoint).inSeconds.abs(),
        lessThanOrEqualTo(30));
    expect(sunnah.lastThirdOfTheNight.isAfter(sunnah.middleOfTheNight), isTrue);
    expect(sunnah.lastThirdOfTheNight.isBefore(tomorrow.fajr), isTrue);
  });

  test('prayer navigation reads the published instants', () {
    final times = PrayerTimes.official(row,
        parameters: _parameters(), utcOffset: Duration());
    expect(times.currentPrayerByDateTime(DateTime.utc(2026, 1, 1, 9)),
        Prayer.dhuhr);
    expect(times.nextPrayerByDateTime(DateTime.utc(2026, 1, 1, 9)), Prayer.asr);
    expect(
        times.timeForPrayer(Prayer.maghrib), DateTime.utc(2026, 1, 1, 14, 17));
  });
}
