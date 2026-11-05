# Adhan Dart / Flutter
[![Pub](https://img.shields.io/pub/v/adhan?include_prereleases)](https://pub.dev/packages/adhan/versions/2.0.0-nullsafety.1)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/iamriajul/adhan-dart/tests.yml?branch=master)](https://github.com/iamriajul/adhan-dart/actions?query=branch:v2)
[![codecov](https://codecov.io/gh/iamriajul/adhan-dart/branch/v2/graph/badge.svg)](https://codecov.io/gh/iamriajul/adhan-dart/branch/v2)
[![GitHub issues](https://img.shields.io/github/issues/iamriajul/adhan-dart)][tracker]
[![Star on GitHub](https://img.shields.io/github/stars/iamriajul/adhan-dart.svg?style=flat&logo=github&colorB=deeppink&label=stars)][repo]
[![GitHub top language](https://img.shields.io/github/languages/top/iamriajul/adhan-dart)][repo]
[![Gitpod ready-to-code](https://img.shields.io/badge/Gitpod-ready--to--code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/iamriajul/adhan-dart/tree/v2)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/iamriajul/adhan-dart/blob/master/LICENSE)

[repo]: https://github.com/iamriajul/adhan-dart

Adhan Dart is a well tested and well documented library for calculating Islamic prayer times. Adhan Dart is written to
be compatible with Dart and Dart Native / Flutter / Android / iOS / Web etc... devices of all api versions. It has a
small method overhead, and has no external dependencies.

All astronomical calculations are high precision equations directly from the
book [“Astronomical Algorithms” by Jean Meeus](https://www.willbell.com/math/mc1.htm). This book is recommended by the
Astronomical Applications Department of the U.S. Naval Observatory and the Earth System Research Laboratory of the
National Oceanic and Atmospheric Administration.

Implementations of Adhan in other languages can be found in the parent repo [Adhan](https://github.com/batoulapps/Adhan)
.

## Usage

A simple usage example:

```dart
import 'package:adhan/adhan.dart';

main() {
  print('My Prayer Times');
  final myCoordinates = Coordinates(23.9088, 89.1220); // Replace with your own location lat, lng.
  final params = CalculationMethod.karachi.getParameters();
  params.madhab = Madhab.hanafi;
  final prayerTimes = PrayerTimes.today(myCoordinates, params);

  print("---Today's Prayer Times in Your Local Timezone(${prayerTimes.fajr.timeZoneName})---");
  print(DateFormat.jm().format(prayerTimes.fajr));
  print(DateFormat.jm().format(prayerTimes.sunrise));
  print(DateFormat.jm().format(prayerTimes.dhuhr));
  print(DateFormat.jm().format(prayerTimes.asr));
  print(DateFormat.jm().format(prayerTimes.maghrib));
  print(DateFormat.jm().format(prayerTimes.isha));

  print('---');

  // Custom Timezone Usage. (Most of you won't need this).
  print('NewYork Prayer Times');
  final newYork = Coordinates(35.7750, -78.6336);
  final nyUtcOffset = Duration(hours: -4);
  final nyDate = DateComponents(2015, 7, 12);
  final nyParams = CalculationMethod.north_america.getParameters();
  nyParams.madhab = Madhab.hanafi;
  final nyPrayerTimes = PrayerTimes(newYork, nyDate, nyParams, utcOffset: nyUtcOffset);

  print(nyPrayerTimes.fajr.timeZoneName);
  print(DateFormat.jm().format(nyPrayerTimes.fajr));
  print(DateFormat.jm().format(nyPrayerTimes.sunrise));
  print(DateFormat.jm().format(nyPrayerTimes.dhuhr));
  print(DateFormat.jm().format(nyPrayerTimes.asr));
  print(DateFormat.jm().format(nyPrayerTimes.maghrib));
  print(DateFormat.jm().format(nyPrayerTimes.isha));
}
```
##### See [Flutter Example](https://github.com/iamriajul/adhan-dart/tree/master/example/adhan_example_flutter_app) Folder for Flutter Usage Example with Dynamic Location From GPS.

also, you can run `pub run adhan` to test quickly based on Hanafi, Karachi parameters.
*alternatively, without installing in project, you can run `pub global activate adhan` and then run `pub global run adhan` to test quickly.

### Initialization parameters

#### Coordinates

Create a `Coordinates` object with the latitude and longitude for the location you want prayer times for.

```dart
final coordinates = new Coordinates(35.78056, -78.6389);

/// Coordinates Validation Support [Optional],
/// to Support validation, use [validate: true] param, default: false

final validateTrue = new Coordinates(91.78056, -78.6389, validate: true); // Invalid Coordinates, will throw ArgumentError

final validateFalse = new Coordinates(91.78056, -78.6389, validate: false); // Invalid Coordinates, won't throw ArgumentError
```

#### Date

The date parameter passed in should be an instance of the `DateComponents` object. The year, month, and day values need to be populated. All other values will be ignored. The year, month and day values should be for the  local date that you want prayer times for. These date values are expected to be for the Gregorian calendar. There's also a convenience method for converting a `DateTime` to `DateComponents`.

```dart
final date = DateComponents(2015, 11, 1);
// or
final date = DateComponents.from(DateTime.now());
```

#### Calculation parameters

The rest of the needed information is contained within the `CalculationParameters` class. Instead of manually initializing this class, it is recommended to use one of the pre-populated instances in the `CalculationMethod` class. You can then further customize the calculation parameters if needed.

```dart
final params = CalculationMethod.muslim_world_league.getParameters();
params.madhab = Madhab.hanafi;
params.adjustments.fajr = 2;
```

| Parameter | Description |
| --------- | ----------- |
| `method`    | CalculationMethod name |
| `fajrAngle` | Angle of the sun used to calculate Fajr |
| `maghribAngle` | The angle of the sun used to calculate Maghrib |
| `ishaAngle` | Angle of the sun used to calculate Isha. With neither `ishaAngle` nor `ishaInterval` set, Isha falls at the safe bound that would otherwise cap it, the middle of the night by default |
| `ishaInterval` | Minutes after Maghrib (if set, the time for Isha will be Maghrib plus ishaInterval) |
| `madhab` | Value from the Madhab object, used to calculate Asr |
| `highLatitudeRule` | Value from the HighLatitudeRule object, used to set a minimum time for Fajr and a max time for Isha |
| `adjustments` | `PrayerAdjustments` object with custom prayer time adjustments in minutes for each prayer time |
| `rounding` | Value from the Rounding object, how each time is rounded to the minute. Default `nearest` |
| `polarCircleResolution` | Value from the PolarCircleResolution object, how days inside the polar circles without computable times are resolved. Default `aqrabBalad` |
| `hourAngleCorrection` | Value from the HourAngleCorrection object, how the time the sun reaches each prayer's angle is corrected and validated. Default `iterative` |

**CalculationMethod**

| Value | Description |
| ----- | ----------- |
| `muslim_world_league` | Muslim World League. Fajr angle: 18, Isha angle: 17 |
| `egyptian` | Egyptian General Authority of Survey. Fajr angle: 19.5, Isha angle: 17.5 |
| `karachi` | University of Islamic Sciences, Karachi. Fajr angle: 18, Isha angle: 18 |
| `umm_al_qura` | Umm al-Qura University, Makkah. Fajr angle: 18, Isha interval: 90. *Note: you should add a +30 minute custom adjustment for Isha during Ramadan.* |
| `dubai` | Method used in UAE. Fajr and Isha angles of 18.2 degrees. |
| `qatar` | Modified version of Umm al-Qura used in Qatar. Fajr angle: 18, Isha interval: 90. |
| `kuwait` | Method used by the country of Kuwait. Fajr angle: 18, Isha angle: 17.5 |
| `moonsighting_committee` | Moonsighting Committee. Fajr angle: 18, Isha angle: 18. Also uses seasonal adjustment values. |
| `singapore` | Method used by Singapore. Fajr angle: 20, Isha angle: 18. |
| `north_america` | Referred to as the ISNA method. This method is included for completeness but is not recommended. Fajr angle: 15, Isha angle: 15 |
| `turkey` | Turkey. Fajr angle: 18, Isha angle: 17 |
| `tehran` | Tehran. Fajr angle: 17.7, Isha angle: 14, Maghrib Angle: 4.5 |
| `unified_london_times` | Unified London Prayer Times. Uses pre-calculated prayer times for London from embedded JSON data. No astronomical calculations are performed. |
| `malaysia_official` | Official Malaysian timetable published by JAKIM and the state muftis, read per prayer zone from embedded data. Where no row covers the zone and date, calculates with Fajr angle 18, Isha angle 18 and the offsets Fajr +1, Sunrise −1, Dhuhr +3, Asr +1, Maghrib +2, Isha +1. |
| `other` | Fajr angle: 0, Isha angle: 0. This is the default value for `method` when initializing a `CalculationParameters` object. |

**Madhab**

| Value | Description |
| ----- | ----------- |
| `shafi` | Earlier Asr time |
| `hanafi` | Later Asr time |

**HighLatitudeRule**

| Value | Description |
| ----- | ----------- |
| `middle_of_the_night` | Fajr will never be earlier than the middle of the night and Isha will never be later than the middle of the night |
| `seventh_of_the_night` | Fajr will never be earlier than the beginning of the last seventh of the night and Isha will never be later than the end of the first seventh of the night |
| `twilight_angle` | Similar to `SEVENTH_OF_THE_NIGHT`, but instead of 1/7, the fraction of the night used is fajrAngle/60 and ishaAngle/60 |

`HighLatitudeRule.recommended(coordinates)` returns `seventh_of_the_night` beyond 48 degrees from the equator in either hemisphere and `middle_of_the_night` otherwise.

**Rounding**

| Value | Description |
| ----- | ----------- |
| `nearest` | Round to the nearest minute. This is the default |
| `up` | Round up to the next minute whenever the time has any seconds |
| `none` | Keep the computed seconds |

**PolarCircleResolution**

Inside the polar circles the sun may not rise or set, or may not reach the angle a prayer needs, on some days of the year.

| Value | Description |
| ----- | ----------- |
| `aqrabBalad` | Finds the closest location, moving toward the equator at the same longitude, for which prayer times can be computed. This is the default |
| `aqrabYaum` | Finds the closest date, forward or backward, for which prayer times can be computed, and relabels its times onto the requested date |
| `unresolved` | Leaves prayer times unresolved. `PrayerTimes` throws an `ArgumentError` when they cannot be computed, as versions before 2.4.0 did |

**HourAngleCorrection**

| Value | Description |
| ----- | ----------- |
| `iterative` | Repeats the hour angle correction until it converges or ten passes have run, rejects an Asr angle the sun does not reach that day, treats a day whose times come out of order, or less than five minutes apart, as one whose times cannot be computed, and at longitudes near 180 degrees picks the solar transit nearest the longitude's mean noon, so consecutive days never jump by a day. This is the default |
| `singlePass` | Applies the hour angle correction once and keeps every time it produces, as versions before 2.4.0 did |

#### Keeping the times of version 2.3.0

The default, `iterative`, moves times most where the sun's altitude changes slowly. Measured for 2026 with the default `highLatitudeRule`, `middle_of_the_night`: Isha at London under `muslim_world_league` moves 4 minutes on 16 July, Isha at Reykjavik under `north_america` 41 minutes on 25 August, and Isha at Edmonton with 18 degree Fajr and Isha angles 43 minutes on 13 May. With `seventh_of_the_night`, which `HighLatitudeRule.recommended` picks above 48 degrees, those three places do not move on any day of 2026. At Tromso, Asr under `muslim_world_league` moves 50 minutes on 21 January and Fajr under `moon_sighting_committee` 116 minutes on 17 May, under either rule.

Near longitude 180 the day can move. At Suva, version 2.3.0 returned the next local day's times from 20 September to 12 December 2026, and `iterative` returns the requested day. At the Chatham Islands, `iterative` returns the next local day's times on every day of 2026, because mean noon at that longitude on the requested date, counted in UTC, already falls on the next local day there. Version 2.3.0 did the same except from 4 to 19 February 2026, where it returned the requested day, so `iterative` moves those 16 days one day later.

Inside the polar circles, days that threw now resolve through `polarCircleResolution`. To keep the times version 2.3.0 computed, set `hourAngleCorrection` to `singlePass` and `polarCircleResolution` to `unresolved`. With `singlePass` alone, the default `aqrabBalad` search keeps the first latitude whose times compute without checking their order. At Tromso, on 162 of the 2,190 day and method pairs of the 2026 parity grid in `tool/parity/`, where version 2.3.0 threw, it returns Asr before Dhuhr or Maghrib before Asr.

With both set, these changes since version 2.3.0 still apply:

- Rounding runs in UTC, so a clock change in the host's time zone no longer moves a time by an hour.
- The night fractions behind the safe Fajr and Isha bounds keep sub-second precision, as adhan-swift does. On the 12 city, 365 day, 6 method grid in `tool/parity/`, 39 Fajr times move one minute earlier.
- A latitude outside -90 to 90 throws an `ArgumentError`. Version 2.3.0 returned meaningless times for some of them, such as 180.
- A Maghrib angle the sun does not reach, as with the `tehran` method in a polar summer, leaves Maghrib at sunset instead of throwing.
- With neither `ishaAngle` nor `ishaInterval` set, Isha falls at the safe bound that would otherwise cap it, the middle of the night by default, instead of throwing. Under `twilight_angle`, a null `ishaAngle` throws a `FormatException`, as before.
- `SunnahTimes` honours `rounding`. At the default, `nearest`, rounding alone changes none of its times. A middle or last third of the night that ends at one of those 39 Fajr times can move with it, one minute earlier, which is 38 values on the same grid.


### Prayer Times

Once the `PrayerTimes` object has been initialized it will contain values for all five prayer times and the time for sunrise. The prayer times will be DateTime object instances initialized with Local values (converted from UTC via .toLocal method). To display these times for a different timezone than local a UTC Offset should be used, for example `Duration`.

```dart
final kushtiaUtcOffset = Duration(hours: 6);
final newYorkUtcOffset = Duration(hours: -4);
// then pass your offset to PrayerTimes like this:
final prayerTimes = PrayerTimes(coordinates, date, params, utcOffset: newYorkUtcOffset);
```


**Methods**

| name | return |
| ----- | ----------- |
| `timeForPrayer` | DateTime instance |
| `currentPrayer` | Prayer enum instance |
| `currentPrayerByDateTime` | Prayer enum instance |
| `nextPrayer` | Prayer enum instance |
| `nextPrayerByDateTime` | Prayer enum instance |

### Sunnah Times

```dart
final prayerTimes = PrayerTimes(coordinates, date, params, utcOffset: newYorkUtcOffset);
final sunnahTimes = SunnahTimes(prayerTimes);
// and then access
/// The midpoint between Maghrib and Fajr
sunnahTimes.middleOfTheNight
/// The beginning of the last third of the period between Maghrib and Fajr,
/// a recommended time to perform Qiyam
sunnahTimes.lastThirdOfTheNight
```

### Qibla

```dart
final qibla = Qibla(coordinates);
/// Qibla direction degree (Compass/Clockwise)
qibla.direction
```

### Unified London Prayer Times

The library includes embedded prayer times data for London, which can be used instead of astronomical calculations:

```dart
// Using the unified London times calculation method
final londonCoordinates = Coordinates(51.5074, -0.1278);
final params = CalculationMethod.unified_london_times.getParameters();
final prayerTimes = PrayerTimes.today(londonCoordinates, params);

// The prayer times are automatically loaded from embedded JSON data
// No manual initialization required!
```

This method is useful when you need consistent prayer times that match a specific timetable for London, rather than calculated times. The data covers the entire year and is embedded directly in the library.

### Official Malaysian Timetable

The library embeds the prayer timetables that JAKIM publishes through e-Solat, the Selangor district timetables from 2027, and a map of the prayer zones. `CalculationMethod.malaysia_official` reads the published row for the zone and date:

```dart
final params = CalculationMethod.malaysia_official.getParameters();
final times = PrayerTimes(Coordinates(3.1390, 101.6869),
    DateComponents(2026, 11, 2), params, utcOffset: Duration(hours: 8));

times.fajr;                 // 05:48, the published Subuh for zone WLY01
times.source;               // PrayerTimesSource.official
times.malaysiaZone!.code;   // WLY01, resolved from the coordinates
times.malaysiaDay!.imsak;   // 05:38; the row also carries Dhuha
```

The zone comes from the coordinates unless `params.malaysiaZone` names one, such as `'WLY02'`. Times are built at UTC+8, so the host time zone never changes a result. User `adjustments` apply on top of the published row. With `Madhab.hanafi`, Asr is the published Asr plus the calculated difference between the Hanafi and Shafi Asr at the zone's reference point.

When no zone covers the coordinates, or the data has no row for the zone and date, `PrayerTimes` calculates instead and `source` says why: `calculatedNoZone` or `calculatedNoRow`. The zone catalog is available through `MalaysiaZones.resolve`, `MalaysiaZones.on(date)` and `MalaysiaZones.zone(code)`; a retired zone lists its `successors`. District polygons run past the country border in places and a point within 500 metres of a district snaps to it, so a point up to 3.0 km outside Malaysia's land borders can resolve to a zone. A caller that cares should also check the country. `MalaysiaTimetable.revision` names the embedded data. See [docs/MALAYSIA_TIMES_MAINTENANCE.md](docs/MALAYSIA_TIMES_MAINTENANCE.md) for the sources, the formats, the yearly update and the notes for the public API.

Data sources and credits:

- Prayer timetables: JAKIM e-Solat ([www.e-solat.gov.my](https://www.e-solat.gov.my)) and, for the Selangor districts from 2027, the Selangor State Mufti Department ([www.muftiselangor.gov.my](https://www.muftiselangor.gov.my/takwim-solat/)).
- State boundaries: [OpenStreetMap](https://www.openstreetmap.org/copyright), © OpenStreetMap contributors, from a pinned snapshot of the `admin_level=4` relations as they stood at 2026-11-04T00:00:00Z (`tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz`). Every border between states, the Putrajaya ring, the Melaka exclave at Tanjung Tuan and the Pahang island Pulau Aceh come from it. The build checks the map against the outlines of OpenStreetMap buildings and places near the state lines, filtered from the Geofabrik extract of 2026-11-03 (`tool/malaysia/raw/openstreetmap-MYS-*-features.tsv.gz`). The snapshot, those extracts, the zone map `data/malaysia/malaysia_zones.txt`, its Dart string `lib/src/data/malaysia_zones_data.dart`, and `islands.csv`, `town_fixtures.csv`, `state_line_exceptions.csv` and `no_zone_areas.csv` under `tool/malaysia/` hold OpenStreetMap-derived data and are offered under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/); see [data/malaysia/LICENSE-ODbL.md](data/malaysia/LICENSE-ODbL.md). Anyone who copies the zone map must keep that file and this credit with it.
- District boundaries inside each state: [geoBoundaries](https://www.geoboundaries.org) gbOpen MYS ADM2 (sources: geoBoundaries, citypopulation.de), licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Runfola, D. et al. (2020) geoBoundaries: A global database of political administrative boundaries. PLoS ONE 15(4): e0231866, https://doi.org/10.1371/journal.pone.0231866. The centres of 20 of the islands in `tool/malaysia/islands.csv` were measured on the geoBoundaries ADM0 layer, which geoBoundaries records as a 2017 OpenStreetMap export under ODbL. The polygons are simplified to 100 metres, or 80 metres on state borders between zones whose times differ by 2 minutes or more, keep every raw segment within 150 metres of a test fixture, and are quantized to 1e-5 degrees. On a state border the build also keeps, for each point of a mapped OpenStreetMap feature's outline that the simplification would put on the other state's zone, the raw vertex nearest the point in each simplified span that holds a raw segment within reach of it, one vertex per span. Outline points lie at most 5 metres apart, a `place=*` area counts only at its centre, and no point inside an area is tested, so a narrow strip or an area's inside can still resolve to the other side; the guide's Known limits list the cases.
- Place coordinates for most zone test fixtures, the zone reference points, and the centres of the special areas and of the other 17 islands in `islands.csv`: [GeoNames](https://www.geonames.org), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Other fixtures use OpenStreetMap coordinates, points that verifiers chose on each side of a boundary or outside Malaysia, and, for Layang-Layang, Wikipedia.
- The library code is under the MIT licence in `LICENSE`. The data files above carry their own licences.

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/iamriajul/adhan-dart/issues

## Inspired / Adopted From

- [adhan-java](https://github.com/batoulapps/adhan-java/blob/master/README.md)

# Adhan Java

Adhan Java is a well tested and well documented library for calculating Islamic prayer times. Adhan Java is written to be compatible with Java and Android devices of all api versions. It compiles against Java 7 to ensure compatibility with Android. It has a small method overhead, and has no external dependencies.

All astronomical calculations are high precision equations directly from the book [“Astronomical Algorithms” by Jean Meeus](https://www.willbell.com/math/mc1.htm). This book is recommended by the Astronomical Applications Department of the U.S. Naval Observatory and the Earth System Research Laboratory of the National Oceanic and Atmospheric Administration.

Implementations of Adhan in other languages can be found in the [Adhan](https://github.com/batoulapps/Adhan) repo.

![Alt](https://repobeats.axiom.co/api/embed/e8675b24cea4b3ca1f0359e428a0457d259994a1.svg "Repobeats analytics image")

