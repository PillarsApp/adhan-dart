# Published timetable vectors

These files pin the `OTT 1` format that `docs/PUBLISHED_TIMETABLE_FORMAT.md` describes. Every decoder and encoder of the format, in any language, is checked against the same bytes. Do not edit them by hand. Regenerate them with:

```
dart run tool/published/vectors.dart
```

`test/published/vectors_test.dart` fails when the files on disk differ from what the generator writes.

## Layout

- `valid/<name>.ott` is a well-formed file. `valid/<name>.input.json` is the encoder input that produces it under the canonical encoding rules, so an encoder test is `encode(input) == ott`.
- `expected.json` lists lookup cases over the valid files. Each case names the vector, the coordinates, an optional manual `localityId`, the date, and the `result`: `row` with the `locality`, the `published` UTC instant per column and the assembled `asr` for both madhabs; `noRow` with the `locality`; or `noLocality`. Instants are `YYYY-MM-DDTHH:MM:SSZ`.
- `malformed/<name>.ott` is a file a decoder rejects. `malformed/index.json` names the stage that rejects each one: `decode` for `PublishedTimetable.decode`, `validate` for `validateAllRows()`.

## Cases

`kacst-like` carries ten real days of three Saudi capitals in 2026 and 2027, with automatic and manual lookups, a date inside coverage with no row, a date after coverage and an unknown manual id. `shapes` covers resolution: a tie between two points, nearest point, a point exactly on its radius and one metre beyond, a point inside an area, area tolerance, a hole, overlapping areas and a retired locality with a successor. `dst` is an Egypt-like zone whose offset changes twice in the year and carries `imsak` and `asrHanafi`. `late-isha` has Isha after midnight and a published Hanafi Asr.

The assembled `asr` in `expected.json` is `PrayerTimes.official` with the default `hourAngleCorrection` and no adjustments. The Hanafi shift uses the locality's reference point.
