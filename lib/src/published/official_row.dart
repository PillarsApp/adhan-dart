import '../calculation_parameters.dart';
import '../internal/day_times.dart';
import '../internal/shadow_length.dart';
import '../internal/solar_time.dart';
import '../madhab.dart';
import '../prayer_adjustments.dart';
import 'published_timetable.dart';

DayTimes assembleOfficialDay(OfficialRow row, CalculationParameters parameters,
    PrayerAdjustments adjustments) {
  DateTime at(PublishedColumn column, int adjustment) =>
      row.published(column)!.add(Duration(minutes: adjustment));
  return DayTimes(
      fajr: at(PublishedColumn.fajr, adjustments.fajr),
      sunrise: at(PublishedColumn.sunrise, adjustments.sunrise),
      dhuhr: at(PublishedColumn.dhuhr, adjustments.dhuhr),
      asr: _asr(row, parameters).add(Duration(minutes: adjustments.asr)),
      maghrib: at(PublishedColumn.maghrib, adjustments.maghrib),
      isha: at(PublishedColumn.isha, adjustments.isha));
}

DateTime _asr(OfficialRow row, CalculationParameters parameters) {
  final published = row.published(PublishedColumn.asr)!;
  final userShadow = parameters.madhab == Madhab.hanafi ? 2 : 1;
  if (userShadow == row.asrShadow) return published;
  final hanafi = row.published(PublishedColumn.asrHanafi);
  if (userShadow == 2 && hanafi != null) return hanafi;
  final date = row.date;
  final solar = SolarTime(DateTime.utc(date.year, date.month, date.day),
      row.locality.referencePoint, parameters.hourAngleCorrection);
  final shift = (solar.afternoon(_shadowLength(userShadow)) -
          solar.afternoon(_shadowLength(row.asrShadow))) *
      60;
  if (!shift.isFinite) {
    throw StateError('Asr with shadow factor $userShadow is undefined at '
        '${row.locality.referencePoint.latitude}, '
        '${row.locality.referencePoint.longitude} on ${row.date}: the sun '
        'does not reach one of the two shadow lengths there and the row '
        'publishes no Asr for factor $userShadow');
  }
  return published.add(Duration(minutes: (shift + 0.5).floor()));
}

ShadowLength _shadowLength(int factor) =>
    factor == 2 ? ShadowLength.double : ShadowLength.single;
