# Published timetable format `OTT 1`

This page describes the `OTT 1` file format that `PublishedTimetable.decode` reads, the rules a decoder enforces, the resolution and time semantics every reader applies, and the canonical encoding an encoder writes. The test vectors under `test/published/vectors/` are the executable form of this page. An encoder or a decoder in another language is correct when it agrees with those vectors byte for byte and instant for instant.

## File shape

A valid `OTT 1` file is UTF-8: the header line is UTF-8 JSON and every row line is ASCII. A decoder does not decode the file as text. It splits the bytes at LF (`0x0A`) and reads each row line byte by byte, so a byte outside the row grammar, any byte above `0x7F` included, breaks the rule for its position (`cell-reset-nbsp.ott` puts the byte `0xA0` after a tilde and breaks `cell.digits`), and a header line that is not UTF-8 breaks `header.json`. Every line, the last one included, ends with a single LF. A CR (`0x0D`) anywhere in the file is malformed, and so is a UTF-8 byte order mark (`EF BB BF`) anywhere in the file, inside a string included.

- Line 1 is the magic and the major version, exactly `OTT 1`.
- Line 2 is the header, one JSON object on one line.
- Every later line is a row line. A row line carries the published minutes of one locality for a run of consecutive days inside one calendar year.

```
OTT 1
{"authority":"sa-umm-al-qura","revision":12,"part":"all","coverage":["2026-01-01","2027-12-31"],"columns":["fajr","sunrise","dhuhr","asr","maghrib","isha"],"asrShadow":1,"zones":[{"id":"Asia/Riyadh","offsets":[["2026-01-01",180]]}],"localities":[{"id":"1001","group":"1001","zone":0,"names":{"ar":"الرياض","en":"Riyadh","ur":"ریاض"},"ref":[24670000,46690000],"point":{"radiusM":25000}}]}
1001 2026-01-01 050006301220164018201950edeedededeedededde
1001 2027-01-01 050206311221164218211952eeeeeedddddd
```

A decoder rejects a magic other than `OTT` and a major version other than `1`. A decoder ignores header keys this page does not name. A new key never changes the meaning of the keys named here. A change that would alter their meaning is a new major version.

Every rule a decoder enforces has an id, listed under [Rule ids](#rule-ids). A decoder's error for a malformed file names the id of the rule the file breaks, and `test/published/vectors/malformed/index.json` names the stage and the rule id of every malformed vector, so decoders in different languages are held to the same rule for the same bytes.

## Header

The header is a JSON object. Every key in the table is required. The decoder rejects a header that lacks a key, or whose value breaks the rule in the table.

An object in the header, at any depth, never carries the same key twice. JSON parsers keep one of the two values and differ on which, so a decoder does not rely on its parser here: after the header parses, it scans the header line once, remembering the keys of each open object, and rejects the second occurrence of a key (`header.duplicateKey`). A key compares after its escapes are decoded, so `"en"` and `"\u0065n"` are the same key. The same scan counts the open objects and arrays: a header that nests deeper than 32 levels, the header object itself being level 1, is malformed (`header.json`). A string escape that is a lone surrogate (`\ud800` with no low surrogate after it) and a number that is not finite (such as `1e999`) are malformed (`header.json`), under an ignored key too, because JSON parsers differ on both.

Every integer in the header is a JSON number written as digits with an optional leading minus sign. `1.0`, `12.0`, `1e0` and `1e7` are not integers, whatever value they denote. A number that is not an integer representable in a signed 32-bit integer breaks its field's integer rule; a 32-bit integer outside the field's bounds breaks its range rule. Only a `ref` value and an offset's `minutes` may be negative. Every other integer is 0 or more.

Every pattern on this page matches the whole string. A value with a trailing line break does not match.

| Key | Value | Rule |
|---|---|---|
| `authority` | string | Matches `^[a-z0-9][a-z0-9-]{0,63}$`. The identifier of the publishing authority, such as `sa-umm-al-qura`. |
| `revision` | integer | 0 to 2147483647. The authority's revision counter for this edition. |
| `part` | string | Matches `^[a-z0-9][a-z0-9-]{0,63}$`. The name of this part inside the edition, such as `all`. |
| `coverage` | `[from, to]` | Two dates, `from` at or before `to`. Every row date lies in this range. A date in the range with no row is "no row", not an error. |
| `columns` | array of strings | Unique names from the column set below. Contains all six core columns. The order is the order of the cells in every row line. |
| `asrShadow` | integer | 1 or 2. The shadow factor of the published `asr` column. |
| `zones` | array of zone objects | At least one zone. |
| `localities` | array of locality objects | At least one locality. |

### Dates

A date is `YYYY-MM-DD` in the proleptic Gregorian calendar and names a real calendar day. Day arithmetic is in whole UTC days.

### Columns

The column set is `imsak`, `fajr`, `sunrise`, `dhuha`, `dhuhr`, `asr`, `asrHanafi`, `maghrib`, `isha`, `eid`. The six core columns are `fajr`, `sunrise`, `dhuhr`, `asr`, `maghrib` and `isha`. A name outside the set is malformed.

### Zone object

| Key | Value | Rule |
|---|---|---|
| `id` | string | Not empty. Unique within `zones`. The IANA zone name, such as `Asia/Riyadh`. Readers never look it up. It is for people and for the change report. |
| `offsets` | array of `[date, minutes]` | At least one entry. Dates strictly ascending. The first date is at or before `coverage[0]`. `minutes` is an integer with absolute value at most 1440, east of UTC. |

The offset in force on a date is the `minutes` of the entry with the greatest date at or before that date. The encoder writes one entry per change of offset, so a zone without daylight saving has one entry.

### Locality object

| Key | Value | Rule |
|---|---|---|
| `id` | string | Matches `^[A-Za-z0-9_.-]{1,32}$`. Unique within the header. |
| `group` | string | Not empty. A region key for grouped pickers, such as a KACST region id or a Malaysian state. |
| `zone` | integer | An index into `zones`. |
| `names` | object | Keys are language codes, values are strings. May be empty. A reader shows the name in the requested language, else `en`, else `id`. |
| `ref` | `[lat, lon]` | Two integers in microdegrees. `lat` in -90000000 to 90000000, `lon` in -180000000 to 180000000. The reference point. For a point locality it is the point. |
| `point` | `{"radiusM": integer}` | `radiusM` from 1 to 2147483647. Present on a point locality. |
| `area` | `{"polygons": [...], "toleranceM": integer}` | `polygons` has at least one ring. `toleranceM` from 0 to 2147483647. Present on an area locality. |
| `validFrom` | date | Optional. The first day the locality is in force. |
| `validTo` | date | Optional. The last day the locality is in force. At or after `validFrom` when both are present. |
| `successors` | array of strings | Optional. Ids of localities in this header that replace this locality after `validTo`. |

Exactly one of `point` and `area` is present. A locality is in force on a date when the date is at or after `validFrom` (or `validFrom` is absent) and at or before `validTo` (or `validTo` is absent).

A ring is a Google encoded polyline at precision 6, so each decoded value is a microdegree integer, latitude first. Each value (the delta that one run of chunks encodes, not the running coordinate) is written in at most seven chunks (the encoder writes the fewest chunks, and a 32-bit value never needs more) and decodes to a signed 32-bit integer; a ring that breaks either, or that is the empty string, is `locality.area.polyline`. A ring with an odd number of values is `locality.area.ring`. A ring has at least three vertices and every vertex is inside the `ref` ranges. The closing edge from the last vertex back to the first is implicit, so the encoder does not repeat the first vertex. The area is the even-odd fill of all rings together, so a hole is any ring inside another ring, and ring order carries no meaning.

Every integer in the file fits in a signed 32-bit integer. Readers on a 32-bit target multiply microdegrees in 64-bit arithmetic, because a cross product of two microdegree differences does not fit in 32 bits. A reader whose integers carry 53 bits, such as Dart compiled to JavaScript, is exact only while every ring edge spans less than about 9 degrees in both latitude and longitude.

## Row lines

A row line is three fields separated by one space (`0x20`):

```
<localityId> <firstDate> <cells>
```

| Field | Rule |
|---|---|
| `localityId` | The `id` of a locality in the header. |
| `firstDate` | A date inside `coverage`. Day `i` of the line is `firstDate` plus `i` days. |
| `cells` | The encoded minutes of every day, in `columns` order. See the codec below. |

A line never crosses 1 January. The last day of a line is in the same calendar year as `firstDate`. Two lines of one locality never share a day. A locality may have no line for some dates in `coverage`. Those dates have no row.

### Cell codec

The codec is the Malaysia delta codec with the column count taken from the header. Let `n` be the length of `columns`.

- `HHMM` is exactly four bytes from `0x30` to `0x39`. A sign, a space, a tab, any other whitespace or any other byte in those four positions is malformed, in the first day and after a tilde alike.
- The first day is `n` groups of `HHMM`, one per column.
- Every later day is `n` cells, one per column. A cell is one letter from `a` to `g`, or a tilde followed by `HHMM`.
- A letter is the change in minutes from the same column on the previous day. `a` is -3, `b` is -2, `c` is -1, `d` is 0, `e` is +1, `f` is +2, `g` is +3.
- `~HHMM` sets the column to an absolute value.
- `HHMM` means `60 × HH + MM` minutes after local midnight of the day. `HH` runs from 00 to 47 and `MM` from 00 to 59, so a value is 0 to 2879. A value of 1440 or more is a time after the following midnight, which high-latitude Isha needs.

The decoder rejects a cell that is not a letter from `a` to `g` or a tilde and four digits, a day with fewer than `n` cells, `MM` above 59, `HH` above 47, and any minute outside 0 to 2879 after a delta is applied.

`cells` for a line holding the two days `[300, 390, 740, 1000, 1100, 1190]` and `[301, 390, 741, 1001, 1100, 1191]` is `050006301220164018201950edeede`.

## Validation stages

A decoder validates in two stages, so a process that only needs one row never pays for the whole file.

**Decode.** `PublishedTimetable.decode` first checks the file rules on the bytes (not empty, ends with LF, no CR, no byte order mark), then reads line 1 and the header, checks every header rule above, and scans every row line once. For a row line it checks the three-field shape, that `localityId` is in the header, that `firstDate` is a real date inside `coverage`, that `cells` starts with `4 × n` ASCII digits, and that the line has no CR. It does not decode cells. A failure throws `FormatException`.

**Validate all rows.** `validateAllRows()` decodes every line once and checks that every minute is 0 to 2879, that the core columns strictly increase on every day in the order `fajr`, `sunrise`, `dhuhr`, `asr`, `maghrib`, `isha`, that no line crosses 1 January or ends after `coverage`, and that no two lines of one locality overlap. A failure throws `FormatException`. A lookup on a file that was never validated decodes the covering line on first use and throws `FormatException` from the lookup if that line is malformed.

### Rule ids

Every check a decoder makes is one of the rules below. The Dart decoder opens each `FormatException` message with the id and a colon. `test/published/vectors/malformed/` has at least one file for every rule, each the valid base file with exactly one mutation, and `index.json` records the file's stage, rule id and mutation. A decoder in another language passes the vectors when it rejects each file at the recorded stage for the recorded rule, and a rule with no file is a test failure.

| Id | Stage | Rule |
|---|---|---|
| `file.empty` | decode | The file has at least one byte. |
| `file.lastLineNoLF` | decode | The last byte is LF. |
| `file.cr` | decode | No byte is CR. |
| `file.bom` | decode | No byte sequence is `EF BB BF`. |
| `file.magic` | decode | Line 1 is `OTT 1`. |
| `file.headerAbsent` | decode | A header line follows line 1. |
| `header.json` | decode | Line 2 is UTF-8 and parses as one JSON object that nests at most 32 levels, with no lone surrogate escape and no non-finite number. |
| `header.duplicateKey` | decode | No object in the header repeats a key. |
| `header.keyAbsent` | decode | Every required key is present. |
| `header.authority` | decode | `authority` is a string matching `^[a-z0-9][a-z0-9-]{0,63}$`. |
| `header.revision` | decode | `revision` is an integer from 0 to 2147483647. |
| `header.part` | decode | `part` is a string matching `^[a-z0-9][a-z0-9-]{0,63}$`. |
| `header.coverage` | decode | `coverage` is two dates. |
| `header.coverage.order` | decode | `coverage[0]` is at or before `coverage[1]`. |
| `header.asrShadow` | decode | `asrShadow` is 1 or 2. |
| `column.unknown` | decode | `columns` is an array of names from the column set. |
| `column.duplicate` | decode | No column name repeats. |
| `column.missingCore` | decode | Every core column is present. |
| `zones.empty` | decode | `zones` is an array with at least one zone. |
| `zone.id` | decode | A zone is an object whose `id` is a non-empty string. |
| `zone.id.duplicate` | decode | No zone id repeats. |
| `zone.offsets.empty` | decode | `offsets` is an array with at least one entry. |
| `zone.offset.shape` | decode | An offset is `[date, minutes]`. |
| `zone.offset.date` | decode | An offset date is a date. |
| `zone.offset.order` | decode | Offset dates strictly ascend. |
| `zone.offset.range` | decode | Offset minutes is an integer from -1440 to 1440. |
| `zone.offset.start` | decode | The first offset date is at or before `coverage[0]`. |
| `localities.empty` | decode | `localities` is an array with at least one locality. |
| `locality.id` | decode | A locality is an object whose `id` matches the id pattern. |
| `locality.id.duplicate` | decode | No locality id repeats. |
| `locality.group` | decode | `group` is a non-empty string. |
| `locality.zone` | decode | `zone` is an index into `zones`. |
| `locality.names` | decode | `names` is an object whose values are strings. |
| `locality.ref.shape` | decode | `ref` is `[lat, lon]`. |
| `locality.ref.integer` | decode | A `ref` value is a 32-bit integer. |
| `locality.ref.range` | decode | `lat` is within ±90000000 and `lon` within ±180000000. |
| `locality.validity.date` | decode | `validFrom` and `validTo` are dates. |
| `locality.validity.order` | decode | `validTo` is at or after `validFrom`. |
| `locality.successor` | decode | `successors` is an array of ids in the header. |
| `locality.geometry` | decode | Exactly one of `point` and `area` is present. |
| `locality.point.radius` | decode | `point` is an object whose `radiusM` is an integer from 1 to 2147483647. |
| `locality.area.polygons` | decode | `area` is an object whose `polygons` is an array with at least one ring. |
| `locality.area.tolerance` | decode | `toleranceM` is an integer from 0 to 2147483647. |
| `locality.area.polyline` | decode | A ring is a non-empty string of bytes 63 to 126 whose values are complete, at most seven chunks each, and 32-bit. |
| `locality.area.ring` | decode | A ring decodes to an even number of values and at least three vertices. |
| `locality.area.vertex` | decode | Every vertex is inside the `ref` ranges. |
| `row.fields` | decode | A row line is three fields separated by single spaces. |
| `row.locality` | decode | The row's locality id is in the header. |
| `row.date` | decode | The row's first date is a date. |
| `row.coverage` | decode | The row's first date is inside `coverage`. |
| `row.firstDay.length` | decode | `cells` has at least `4 × n` bytes. |
| `row.firstDay.digits` | decode | The first `4 × n` bytes of `cells` are digits. |
| `cell.truncatedTime` | validate | Four bytes follow a tilde. |
| `cell.digits` | validate | The four bytes after a tilde are digits. |
| `cell.minute` | validate | `MM` of any `HHMM`, in the first day or after a tilde, is at most 59. |
| `cell.hour` | validate | `HH` of any `HHMM`, in the first day or after a tilde, is at most 47. |
| `cell.truncatedDay` | validate | Every day after the first has `n` cells. |
| `cell.letter` | validate | A cell that is not a tilde is a letter from `a` to `g`. |
| `cell.delta` | validate | A delta keeps the column within 0 to 2879. |
| `row.coreOrder` | validate | The core columns strictly increase on every day. |
| `row.crossesYear` | validate | A line ends in the year it starts. |
| `row.endsAfterCoverage` | validate | A line ends at or before `coverage[1]`. |
| `row.overlap` | validate | Two lines of one locality share no day. |

The `file.*` rules run first, in the order of the table, before any line is parsed, and each presumes the rules above it hold, so a file breaks at most one of them. The other decode-stage rules may be checked in any order, and the validate-stage rules run only on a file that passed the decode stage. Every vector breaks exactly one rule, so the recorded stage and rule are the only ones a correct decoder can report for it. A file that breaks several header or row rules may be reported under any of them.

## Semantics every reader applies

### Instants

Published minutes are wall time. A reader turns them into an instant with the artifact's own offsets and never with the device's time zone database:

```
instant = utcMidnight(date) + minutes − offset(zone, date)
```

where `zone` is the locality's zone, `offset` is in minutes east of UTC as the zone's `offsets` give it for `date`, and `date` is the row's day, not the day the instant falls on.

### Locality resolution

`localityAt(coordinates, date)` returns at most one locality. A latitude outside -90 to 90, a longitude outside -180 to 180, a non-finite coordinate, or a `date` that is not a calendar day (such as 2026-02-30) is a caller error, not a lookup result: Dart throws `ArgumentError`, and no reader normalizes the date or returns "no locality" for it. A manual lookup by id still requires a calendar day and never reads the coordinates.

1. Consider only localities in force on `date`.
2. Among point localities, keep those whose distance from the coordinates is at most the radius. Take the nearest. If two are equally near, take the one whose `id` sorts first by UTF-16 code unit.
3. If no point locality matched, take the first area locality in header order that contains the coordinates or lies within `toleranceM` of them.
4. Otherwise there is no locality.

A manual lookup with a locality id skips resolution. An id the header does not know gives "no locality". A known id gives that locality whether or not it is in force on the date.

Distances are in whole millimetres, so two implementations agree even when their trigonometric functions differ in the last bit:

- The distance between two coordinates is the haversine distance on a sphere of radius 6371008.8 metres, rounded to the nearest millimetre. With latitudes and longitudes in radians, `a = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)` and `d = 2R · atan2(√a, √(1 − a))`. A `ref` value converts to degrees as `ref / 1000000`.
- A coordinate is inside an area when an even-odd crossing count over every edge of every ring is odd. The coordinate is first quantized to microdegrees by rounding half away from zero. An edge from `(lat1, lon1)` to `(lat2, lon2)` counts when `(lat1 > lat) ≠ (lat2 > lat)` and the point lies on the side of the edge that `(lon − lon1) × (lat2 − lat1)` against `(lat − lat1) × (lon2 − lon1)` names, with `<` when `lat2 > lat1` and `>` otherwise. The products are 64-bit.
- The distance from a coordinate to an area is the smallest distance from the coordinate to any edge of any ring, rounded to the nearest millimetre. Both ends of the edge and the coordinate are projected onto a plane around the coordinate: `y = (lat − lat0) × 110574` and `x = (lon − lon0) × 111320 × cos(lat0)`, in metres, with every value in degrees except the cosine's argument, which is `lat0` in radians. The distance is the planar distance to the segment, with the projection onto the segment clamped to its ends.

### Hanafi Asr

`asrShadow` names the shadow factor of the published `asr`. A reader that assembles prayer times for a madhab with the same factor uses the published Asr. When the factors differ, Asr is the published Asr plus `floor((asr(userShadow) − asr(asrShadow)) × 60 + 0.5)` minutes. Both solar Asr times are computed with the library's own solar-time algorithm (adhan's `SolarTime`, not an external ephemeris), at the locality's reference point on the row's date, as fractional hours; the difference in minutes is rounded to the nearest minute with a half rounded up, so a shift of −2.5 becomes −2 and one of 2.5 becomes 3. When the header has an `asrHanafi` column and the madhab is Hanafi, the reader uses that column instead. The `expected.json` vectors give the assembled Asr for both madhabs.

At a high latitude the sun can fail to reach the Hanafi shadow length on a day it does reach the Shafi one, so the solar difference is undefined. A reader asked for that Asr without an `asrHanafi` column reports that it cannot assemble the day instead of returning a time (Dart throws `StateError` from `PrayerTimes.official`). An authority whose localities can reach such a day must publish `asrHanafi`.

## Canonical encoding

An encoder that follows these rules writes the same bytes for the same input in every language, which is what makes the artifact hash stable. The Dart reference encoder is `tool/published/ott_encoder.dart`, and `test/published/vectors/valid/*.input.json` holds the input of every valid vector.

### Input

The input is the header fields plus `rows`, a map from locality id to a map from date to an array of minutes in `columns` order. `polygons` in the input is the array of encoded polyline strings exactly as the file carries them; the encoder neither encodes nor reorders rings. A locality's `zone` in the input is an index into the input's `zones`. The order of every array and of every object's keys in the input carries no meaning except for `columns`, `polygons`, `coverage`, `ref`, an offset pair and a day's minutes, so the same data in any order encodes to the same bytes:

```json
{"authority":"sa-umm-al-qura","revision":12,"part":"all","coverage":["2026-01-01","2027-12-31"],"columns":["fajr","sunrise","dhuhr","asr","maghrib","isha"],"asrShadow":1,"zones":[...],"localities":[...],
 "rows":{"1001":{"2026-01-01":[300,390,740,1000,1100,1190],"2026-01-02":[301,390,741,1001,1100,1191]}}}
```

### Rules

1. Write `OTT 1` and LF.
2. Write the header as JSON with no whitespace between tokens. Keys in this order: `authority`, `revision`, `part`, `coverage`, `columns`, `asrShadow`, `zones`, `localities`. Inside a zone: `id`, `offsets`. Inside a locality: `id`, `group`, `zone`, `names`, `ref`, then `point` or `area`, then `validFrom`, `validTo`, `successors`, each only when present. Inside `point`: `radiusM`. Inside `area`: `polygons`, `toleranceM`.
3. Sort `zones` by `id` and each zone's `offsets` by date. Sort `localities` by `id`, the keys of `names`, and `successors`. Every sort compares strings by UTF-16 code unit, which is what JavaScript's default sort, Dart's `compareTo` and Swift's `utf16` comparison do; it differs from a code point sort only for characters outside the Basic Multilingual Plane. Keep `columns` and `polygons` in input order. The encoder rewrites each locality's `zone` to the index of the same zone in the sorted `zones`, so the written index always refers to the sorted array.
4. Refuse an input whose strings hold U+FEFF or a lone surrogate, because the file they would produce breaks `file.bom` or `header.json`. Escape the other strings as JSON.stringify and Dart's `jsonEncode` do: `"` as `\"`, `\` as `\\`, and the control characters U+0000 to U+001F as `\b`, `\f`, `\n`, `\r`, `\t` or `\u00XX` with lowercase hex digits (`\u001b`). U+007F and every other character are literal UTF-8. Write integers in decimal with no exponent, no fraction and no plus sign, with a minus sign only when the value is negative.
5. Write the row lines for the localities in header order. For each locality, split its dates into maximal runs of consecutive days that stay inside one calendar year, in date order, and write one line per run. Use a letter whenever the change is -3 to +3 and `~HHMM` otherwise.
6. End every line with LF.

## Size

A cell is one byte on most days, so a locality-year of six columns is about 2.2 KB. KACST, with 173 localities and two years, is about 780 KB before compression (an estimate from the Malaysia ratio, not a measurement).
