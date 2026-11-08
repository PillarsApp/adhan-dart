# Published timetable format `OTT 1`

This page describes the `OTT 1` file format that `PublishedTimetable.decode` reads, the rules a decoder enforces, the resolution and time semantics every reader applies, and the canonical encoding an encoder writes. The test vectors under `test/published/vectors/` are the executable form of this page. An encoder or a decoder in another language is correct when it agrees with those vectors byte for byte and instant for instant.

## File shape

An `OTT 1` file is one UTF-8 text file. Every line, the last one included, ends with a single LF (`0x0A`). A CR (`0x0D`) anywhere in the file is malformed.

- Line 1 is the magic and the major version, exactly `OTT 1`.
- Line 2 is the header, one JSON object on one line.
- Every later line is a row line. A row line carries the published minutes of one locality for a run of consecutive days inside one calendar year.

```
OTT 1
{"authority":"sa-umm-al-qura","revision":12,"part":"all","coverage":["2026-01-01","2027-12-31"],"columns":["fajr","sunrise","dhuhr","asr","maghrib","isha"],"asrShadow":1,"zones":[{"id":"Asia/Riyadh","offsets":[["2026-01-01",180]]}],"localities":[{"id":"1001","group":"1001","zone":0,"names":{"ar":"الرياض","en":"Riyadh","ur":"ریاض"},"ref":[24670000,46690000],"point":{"radiusM":25000}}]}
1001 2026-01-01 051506371157145717171847ededeedddddd
1001 2027-01-01 051606371157145817181848dedddd
```

A decoder rejects a magic other than `OTT` and a major version other than `1`. A decoder ignores header keys this page does not name. A new key never changes the meaning of the keys named here. A change that would alter their meaning is a new major version.

## Header

The header is a JSON object. Every key in the table is required. The decoder rejects a header that lacks a key, or whose value breaks the rule in the table.

| Key | Value | Rule |
|---|---|---|
| `authority` | string | Not empty. No whitespace. The identifier of the publishing authority, such as `sa-umm-al-qura`. |
| `revision` | integer | 0 to 2147483647. The authority's revision counter for this edition. |
| `part` | string | Not empty. No whitespace. The name of this part inside the edition, such as `all`. |
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
| `id` | string | Not empty. The IANA zone name, such as `Asia/Riyadh`. Readers never look it up. It is for people and for the change report. |
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

A ring is a Google encoded polyline at precision 6, so each decoded value is a microdegree integer, latitude first. A ring has at least three vertices and every vertex is inside the `ref` ranges. The closing edge from the last vertex back to the first is implicit, so the encoder does not repeat the first vertex. The area is the even-odd fill of all rings together, so a hole is any ring inside another ring, and ring order carries no meaning.

Every integer in the file fits in a signed 32-bit integer. Readers on a 32-bit target multiply microdegrees in 64-bit arithmetic, because a cross product of two microdegree differences does not fit in 32 bits.

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

- The first day is `n` groups of four ASCII digits, `HHMM`, one per column.
- Every later day is `n` cells, one per column. A cell is one letter from `a` to `g`, or a tilde followed by `HHMM`.
- A letter is the change in minutes from the same column on the previous day. `a` is -3, `b` is -2, `c` is -1, `d` is 0, `e` is +1, `f` is +2, `g` is +3.
- `~HHMM` sets the column to an absolute value.
- `HHMM` means `60 × HH + MM` minutes after local midnight of the day. `HH` runs from 00 to 47 and `MM` from 00 to 59, so a value is 0 to 2879. A value of 1440 or more is a time after the following midnight, which high-latitude Isha needs.

The decoder rejects a cell that is not a letter from `a` to `g` or a tilde and four digits, a day with fewer than `n` cells, `MM` above 59, and any minute outside 0 to 2879 after a delta is applied.

`cells` for a line holding the two days `[315, 397, 717, 897, 1037, 1127]` and `[316, 397, 718, 897, 1038, 1128]` is `051506371157145717171847ededee`.

## Validation stages

A decoder validates in two stages, so a process that only needs one row never pays for the whole file.

**Decode.** `PublishedTimetable.decode` reads line 1 and the header, checks every header rule above, and scans every row line once. For a row line it checks the three-field shape, that `localityId` is in the header, that `firstDate` is a real date inside `coverage`, that `cells` starts with `4 × n` ASCII digits, and that the line has no CR. It does not decode cells. A failure throws `FormatException`.

**Validate all rows.** `validateAllRows()` decodes every line once and checks that every minute is 0 to 2879, that the core columns strictly increase on every day in the order `fajr`, `sunrise`, `dhuhr`, `asr`, `maghrib`, `isha`, that no line crosses 1 January, and that no two lines of one locality overlap. A failure throws `FormatException`. A lookup on a file that was never validated decodes the covering line on first use and throws `FormatException` from the lookup if that line is malformed.

The `test/published/vectors/malformed/` directory has one file per rule, and `index.json` names the stage that rejects each file.

## Semantics every reader applies

### Instants

Published minutes are wall time. A reader turns them into an instant with the artifact's own offsets and never with the device's time zone database:

```
instant = utcMidnight(date) + minutes − offset(zone, date)
```

where `zone` is the locality's zone, `offset` is in minutes east of UTC as the zone's `offsets` give it for `date`, and `date` is the row's day, not the day the instant falls on.

### Locality resolution

`localityAt(coordinates, date)` returns at most one locality. A non-finite coordinate is an argument error.

1. Consider only localities in force on `date`.
2. Among point localities, keep those whose distance from the coordinates is at most the radius. Take the nearest. If two are equally near, take the one whose `id` sorts first by code point.
3. If no point locality matched, take the first area locality in header order that contains the coordinates or lies within `toleranceM` of them.
4. Otherwise there is no locality.

A manual lookup with a locality id skips resolution. An id the header does not know gives "no locality". A known id gives that locality whether or not it is in force on the date.

Distances are in whole millimetres, so two implementations agree even when their trigonometric functions differ in the last bit:

- The distance between two coordinates is the haversine distance on a sphere of radius 6371008.8 metres, rounded to the nearest millimetre. With latitudes and longitudes in radians, `a = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)` and `d = 2R · atan2(√a, √(1 − a))`. A `ref` value converts to degrees as `ref / 1000000`.
- A coordinate is inside an area when an even-odd crossing count over every edge of every ring is odd. The coordinate is first quantized to microdegrees by rounding half away from zero. An edge from `(lat1, lon1)` to `(lat2, lon2)` counts when `(lat1 > lat) ≠ (lat2 > lat)` and the point lies on the side of the edge that `(lon − lon1) × (lat2 − lat1)` against `(lat − lat1) × (lon2 − lon1)` names, with `<` when `lat2 > lat1` and `>` otherwise. The products are 64-bit.
- The distance from a coordinate to an area is the smallest distance from the coordinate to any edge of any ring, rounded to the nearest millimetre. Both ends of the edge and the coordinate are projected onto a plane around the coordinate: `y = (lat − lat0) × 110574` and `x = (lon − lon0) × 111320 × cos(lat0)`, in metres, with every value in degrees except the cosine's argument, which is `lat0` in radians. The distance is the planar distance to the segment, with the projection onto the segment clamped to its ends.

### Hanafi Asr

`asrShadow` names the shadow factor of the published `asr`. A reader that assembles prayer times for a madhab with the same factor uses the published Asr. When the factors differ, Asr is the published Asr plus `round((asr(userShadow) − asr(asrShadow)) × 60)` minutes, both solar Asr times computed at the locality's reference point on the row's date. When the header has an `asrHanafi` column and the madhab is Hanafi, the reader uses that column instead. The `expected.json` vectors give the assembled Asr for both madhabs.

## Canonical encoding

An encoder that follows these rules writes the same bytes for the same input in every language, which is what makes the artifact hash stable. The Dart reference encoder is `tool/published/ott_encoder.dart`, and `test/published/vectors/valid/*.input.json` holds the input of every valid vector.

### Input

The input is the header fields plus `rows`, a map from locality id to a map from date to an array of minutes in `columns` order:

```json
{"authority":"sa-umm-al-qura","revision":12,"part":"all","coverage":["2026-01-01","2027-12-31"],"columns":["fajr","sunrise","dhuhr","asr","maghrib","isha"],"asrShadow":1,"zones":[...],"localities":[...],
 "rows":{"1001":{"2026-01-01":[315,397,717,897,1037,1127],"2026-01-02":[316,397,718,897,1038,1128]}}}
```

### Rules

1. Write `OTT 1` and LF.
2. Write the header as JSON with no whitespace between tokens. Keys in this order: `authority`, `revision`, `part`, `coverage`, `columns`, `asrShadow`, `zones`, `localities`. Inside a zone: `id`, `offsets`. Inside a locality: `id`, `group`, `zone`, `names`, `ref`, then `point` or `area`, then `validFrom`, `validTo`, `successors`, each only when present. Inside `point`: `radiusM`. Inside `area`: `polygons`, `toleranceM`.
3. Sort `zones` by `id` and each zone's `offsets` by date. Sort `localities` by `id`, the keys of `names` by code point, and `successors` by code point. Keep `columns` and `polygons` in input order. A locality's `zone` in the input is an index into the input's `zones`. The encoder rewrites it to the index of the same zone in the sorted `zones`, so the written index always refers to the sorted array.
4. Escape strings as JSON.stringify and Dart's `jsonEncode` do: `"` as `\"`, `\` as `\\`, and the control characters U+0000 to U+001F as `\b`, `\f`, `\n`, `\r`, `\t` or `\u00XX`. Every other character is literal UTF-8. Write integers with no exponent, sign or fraction.
5. Write the row lines for the localities in header order. For each locality, split its dates into maximal runs of consecutive days that stay inside one calendar year, in date order, and write one line per run. Use a letter whenever the change is -3 to +3 and `~HHMM` otherwise.
6. End every line with LF.

## Size

A cell is one byte on most days, so a locality-year of six columns is about 2.2 KB. KACST, with 173 localities and two years, is about 780 KB before compression (an estimate from the Malaysia ratio, not a measurement).
