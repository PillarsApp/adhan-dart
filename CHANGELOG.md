## 3.0.0

- Add `PublishedTimetable.decode`, which reads a prayer timetable published in the `OTT 1` text format at runtime, and `validateAllRows`, which checks every row once. `docs/PUBLISHED_TIMETABLE_FORMAT.md` defines the format and `test/published/vectors/` pins it.
- Add `OfficialTimetableSource` with `localityAt` and `lookup`, the sealed `OfficialLookup` (`OfficialRow`, `NoLocality`, `NoRow`), `Locality`, `LocalityId` and `PublishedColumn`.
- Add `PrayerTimes.official`, which assembles prayer times from a published row with the caller's madhab and adjustments, and `PrayerTimes.officialRow`.
- Add `MalaysiaTimetable.source`, the bundled Malaysian data behind the same interface. `CalculationMethod.malaysia_official` reads its rows through it and produces the same times as 2.5.0 on every zone and day of 2026 and 2027, which `test/malaysia_parity_test.dart` checks against a golden recorded at 2.5.0.
- Breaking: the SDK constraint is now `>=3.3.0 <4.0.0`. Dart 2 consumers stay on 2.5.0.

## 2.5.0

- Add `CalculationMethod.malaysia_official`, which reads the official Malaysian prayer timetable for the zone and date from embedded data, with instants built at UTC+8. Where no row covers them, it calculates with Fajr 18, Isha 18 and the offsets Fajr +1, Sunrise −1, Dhuhr +3, Asr +1, Maghrib +2, Isha +1.
- Add `CalculationParameters.malaysiaZone` to pick a zone by code instead of resolving it from the coordinates.
- Add `PrayerTimes.source`, `malaysiaZone` and `malaysiaDay`. `source` is `official` for a published row (Malaysia and London), `calculated` for every other method, and `calculatedNoZone` or `calculatedNoRow` when the Malaysian method had to calculate.
- Add `MalaysiaZones` (`resolve`, `on`, `zone`), `MalaysiaZone` with validity dates and successors, and `MalaysiaTimetable.day` with Imsak and Dhuha.
- Add `tool/parity/bench_malaysia.dart`.
- Breaking for Dart 3 consumers: the new `CalculationMethod.malaysia_official` value makes an exhaustive `switch` over `CalculationMethod` a compile error until it handles the value. Existing indices do not move.

## 2.4.0

- Add `polarCircleResolution` with `aqrabBalad` (default), `aqrabYaum` and `unresolved`, so days inside the polar circles resolve to usable times instead of throwing.
- Add `hourAngleCorrection` with `iterative` (default) and `singlePass`. `iterative` repeats the hour angle correction until it converges and validates Asr and the order of the times. The times move most where the sun's altitude changes slowly. Measured for 2026 with the default `middle_of_the_night`, Isha moves 4 minutes at London under `muslim_world_league` on 16 July and 41 minutes at Reykjavik under `north_america` on 25 August, and Fajr under `moon_sighting_committee` moves 116 minutes at Tromso on 17 May. `singlePass` keeps the single-pass correction of 2.3.0. Set `polarCircleResolution` to `unresolved` as well to keep the 2.3.0 times, because `singlePass` with `aqrabBalad` can return the times of a polar day out of order.
- Add `rounding` with `nearest` (default), `up` and `none`, and honour it in sunnah times.
- Add `HighLatitudeRule.recommended`, which treats both hemispheres alike.
- Throw `ArgumentError` for a latitude outside -90 to 90. The error thrown when no times can be computed names the latitude and longitude.
- Under `iterative`, pick the solar transit nearest the longitude's mean noon, so consecutive days never jump by a day, as adhan-swift does. Suva gets the requested day's times from 20 September to 12 December 2026, where 2.3.0 returned the next local day's. At the Chatham Islands the times for 4 to 19 February 2026 move one day later, to the next local day, as on every other day of the year there. `singlePass` keeps the 2.3.0 transit.
- Round in UTC, so a daylight saving day in the host time zone no longer moves a result by an hour.
- Keep sub-second precision in the night fractions behind the safe Fajr and Isha bounds, matching adhan-swift to the minute. With `singlePass` and `unresolved`, 39 Fajr times of the 12 city, 365 day, 6 method grid in `tool/parity/` move one minute earlier than in 2.3.0.
- A Maghrib angle the sun does not reach, as with the Tehran method in a polar summer, leaves Maghrib at sunset instead of throwing.
- With neither `ishaAngle` nor `ishaInterval` set, Isha falls at the safe bound that would otherwise cap it, the middle of the night by default, instead of throwing.
- Add `tool/parity/`: a grid probe, a comparison against the adhan-swift probe output that fails on any differing, duplicate or malformed row, and a benchmark with a variant that also compiles at 2.3.0.

## 2.3.0

- Rebase the Pillars fork onto upstream master.
- Interpret London timetables in Europe/London rather than the device timezone, including GMT/BST transitions.
- Preserve native local and explicit UTC-offset output when using London timetables.
- Preserve the caller's initialized timezone database and selected local timezone.
- Support Dart 2.19 through Dart 3 and timezone 0.9.4 through 0.10.x.
- Cover London absolute instants and daylight-saving boundaries independently of the host timezone.

## 2.1.0

- feat: Add embedded London prayer times data for `unified_london_times` calculation method
- feat: Auto-initialize London times from embedded data - no manual setup required
- feat: Maintain backward compatibility with manual initialization methods
- test: Add comprehensive tests for auto-initialization functionality

## 2.0.0+1

- chore: update readme.

## 2.0.0

- release: stable version. with null safety and dart 3 support.

## 2.0.0-nullsafety.2

- fix: exclude MadhabExtensions from exporting. **madhab.getShadowLength()** should not accessible outside.

## 1.1.16

- fix: exclude MadhabExtensions from exporting. **madhab.getShadowLength()** should not accessible outside.

## 2.0.0-nullsafety.1

- docs: update.

## 2.0.0-nullsafety.0

- breaking: Migrate to null safety.
- feat: throws ArgumentError instead of null for invalid coordinates.
- note: this is a beta version. future versions of ^v2 may change api behavior.

## 1.1.15

- feat: added support for maghribAngle. PR#13

## 1.1.14

- docs: added Documentation for SunnahTimes and Qibla.
- docs: API Docs.

## 1.1.13

- feat: added Turkey Method.

## 1.1.12

- feat: added Coordinates Validation Support [Optional].

## 1.1.11

- test: 100% test coverage!
- docs: Readme Fixes.

## 1.1.10

- fix: Umma Al Qura and Qatar Method Params Bug Fixes.
- test: Test Prayer Times in Wide Range Locations From JSON Data.

## 1.1.9

- Example updates

## 1.1.8

- added PrayerTimes.today helper factory, so you don't have to manage `DateComponents` for Today's Times.
- added adhan bin, so you can run `pub run adhan` in cli to test quickly.
- docs and readme updates.

## 1.1.7

- added Flutter Example in /example folder.
- added utc and utcOffset quick helper factory in PrayerTimes.

## 1.1.6

- added Sunnah Times and Qibla.
- Code Improvements.

## 1.1.5

- added Docs/Modified(as Dart Standard) in Codes for Public APIs.

## 1.1.4

- made lightweight to use. removed external dependencies, so it has lower method overhead.

## 1.1.3

- update readme

## 1.1.2

- update package description
- format all files via dartfmt -w bin lib test

## 1.1.1

- Timezone Problem Fixes, Now PrayerTimes values will be default in Local time, to get a different timezone than Local you can set utcOffset named optional params.
- Bug Fixes

## 1.0.1

- Readme update

## 1.0.0

- Initial version, created by Riajul
