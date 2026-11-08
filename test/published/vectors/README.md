# Published timetable vectors

These files pin the `OTT 1` format that `docs/PUBLISHED_TIMETABLE_FORMAT.md` describes. Every decoder and encoder of the format, in any language, is checked against the same bytes. Do not edit them by hand. Regenerate them with:

```
dart run tool/published/vectors.dart
```

`test/published/vectors_test.dart` fails when the files on disk differ from what the generator writes, when the reference encoder does not reproduce a valid file from its input, or when a shuffled input encodes to different bytes.

## Layout

- `valid/<name>.ott` is a well-formed file. `valid/<name>.input.json` is the encoder input that produces it under the canonical encoding rules, so an encoder test is `encode(input) == ott`.
- `refused.json` lists encoder inputs that a canonical encoder must refuse, each with the rule the file it would write breaks. An encoder test is that `encode(input)` fails for each.
- `expected.json` lists lookup cases over the valid files. Each case names the vector, the coordinates, an optional manual `localityId`, the date, and the `result`: `row` with the `locality`, the `published` UTC instant per column and the assembled `asr` for both madhabs; `noRow` with the `locality`; or `noLocality`. Instants are `YYYY-MM-DDTHH:MM:SSZ`.
- `malformed/<name>.ott` is the valid base file with exactly one mutation, so it breaks exactly one rule. `malformed/index.json` names the `stage` that rejects each file (`decode` for `PublishedTimetable.decode`, `validate` for `validateAllRows()`), the `rule` id from the format doc that the file breaks, and the `mutation`. A decoder's error for the file starts with that rule id. `published_vectors_test.dart` holds every file to its stage and rule, and fails when a rule in the decoder has no file.

## Cases

`kacst-like` has the shape of a KACST part, three Saudi cities with ten days in each of 2026 and 2027, with automatic and manual lookups, a date inside coverage with no row, a date after coverage and an unknown manual id. Its minutes are calculated Umm al-Qura times, not an authority's publication. `shapes` covers resolution: a tie between two points, nearest point, the nearer point with the later id, a point exactly on its radius and one metre beyond, a point inside an area, area tolerance, a hole, overlapping areas and a retired locality with a successor. `dst` is an Egypt-like zone whose offset changes twice in the year and carries `imsak` and `asrHanafi`. `late-isha` has Isha after midnight and a published Hanafi Asr. `two-zones` lists its zones out of sorted order in the input, so an encoder that does not rewrite each locality's zone index to the sorted order gives Istanbul Dubai's offset and fails the lookup cases. `edge-values` has a negative offset and negative longitudes, a revision of 0, names with escaped quotes, a backslash, a tab, a control character and non-ASCII letters, unsorted `names`, `offsets`, `successors` and `localities` in the input, ids with `.`, `_` and `-`, and a retired locality with two successors. `canon` pins the rest of the canonical encoding: every delta letter from `a` to `g`, changes of exactly ±3 as letters and of ±4 or more as `~HHMM`, six consecutive days split into two lines at 1 January, `names` keys sorted by UTF-16 code unit with a key outside the Basic Multilingual Plane, a name of U+007F written literally and one of `\b\f` escaped, a locality with both `validFrom` and `validTo`, and an area whose two rings stay in input order although sorting would swap them.

The assembled `asr` in `expected.json` is `PrayerTimes.official` with the default `hourAngleCorrection` and no adjustments. The Hanafi shift uses the locality's reference point.
