## 2.5.0

- Add `CalculationMethod.malaysia_official`, which reads the official Malaysian prayer timetable for the zone and date from embedded data, with instants built at UTC+8. Where no row covers them, it calculates with Fajr 18, Isha 18 and the offsets Fajr +1, Sunrise −1, Dhuhr +3, Asr +1, Maghrib +2, Isha +1.
- Add `CalculationParameters.malaysiaZone` to pick a zone by code instead of resolving it from the coordinates.
- Add `PrayerTimes.source`, `malaysiaZone` and `malaysiaDay`. `source` is `official` for a published row (Malaysia and London), `calculated` for every other method, and `calculatedNoZone` or `calculatedNoRow` when the Malaysian method had to calculate.
- Add `MalaysiaZones` (`resolve`, `on`, `zone`), `MalaysiaZone` with validity dates and successors, and `MalaysiaTimetable.day` with Imsak and Dhuha.
- Add `tool/parity/bench_malaysia.dart`.

## 2.4.0

- Add `polarCircleResolution` with `aqrabBalad` (default), `aqrabYaum` and `unresolved`, so days inside the polar circles resolve to usable times instead of throwing.
- Add `hourAngleCorrection` with `iterative` (default) and `singlePass`. `iterative` repeats the hour angle correction until it converges, validates Asr and the order of the times, and moves Isha by a few minutes on some summer days above about 48 degrees latitude. `singlePass` keeps the single-pass correction of 2.3.0.
- Add `rounding` with `nearest` (default), `up` and `none`, and honour it in sunnah times.
- Add `HighLatitudeRule.recommended`, which treats both hemispheres alike.
- Throw `ArgumentError` for a latitude outside -90 to 90.
- Under `iterative`, pick the solar transit nearest the longitude's mean noon, so consecutive days never jump by a day, as adhan-swift does. Locations such as Suva and Anadyr no longer get the next day's times for weeks at a time. `singlePass` keeps the 2.3.0 transit.
- Round in UTC, so a daylight saving day in the host time zone no longer moves a result by an hour.
- Keep sub-second precision in the night fractions behind the safe Fajr and Isha bounds, matching adhan-swift to the minute.
- A Maghrib angle the sun does not reach, as with the Tehran method in a polar summer, leaves Maghrib at sunset instead of throwing.
- Add `tool/parity/`, a grid probe, a comparison against the adhan-swift probe output, and a benchmark.

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
