# Malaysian Prayer Times Data Maintenance Guide

This guide describes how the Malaysian timetable and zone data is fetched, validated, encoded and released. It is for the engineer who updates the data each year, and for anyone porting the data to another language version of this package.

## Overview

Malaysia publishes official prayer times per zone. JAKIM serves them through e-Solat. From 2027 the Selangor State Mufti Department publishes Selangor as nine district timetables in PDF form, which e-Solat does not carry. The generator reads both, checks every row, applies a reviewed list of corrections, and writes two compact text files plus a manifest of hashes.

| Output | Content |
| --- | --- |
| `data/malaysia/malaysia_times.txt` | One line per zone and year with eight times per day |
| `data/malaysia/malaysia_zones.txt` | The zone catalog, the special areas and the district polygons |
| `data/malaysia/MANIFEST` | The SHA-256 of both outputs and of every source, with its URL and retrieval date |
| `lib/src/data/malaysia_times_data.dart` | `malaysiaTimesData`, the times file as a Dart string |
| `lib/src/data/malaysia_zones_data.dart` | `malaysiaZonesData`, the zones file as a Dart string |

The two Dart constants hold the same bytes as the text files. Other language versions copy the text files and check them against `MANIFEST`.

## Files

| Path | Purpose |
| --- | --- |
| `tool/malaysia/malaysia_times_cli.dart` | The `fetch`, `import-selangor`, `build` and `lookup` commands |
| `tool/malaysia/src/malaysia_timetables.dart` | Fetching, parsing, validation and correction of the timetables |
| `tool/malaysia/src/malaysia_zones.dart` | The zone catalog, district rules, polygon simplification and arc encoding |
| `lib/src/data/malaysia_times_codec.dart` | Encoder and decoder for the times file |
| `lib/src/data/malaysia_zone_map.dart` | Decoder and point-to-zone resolver for the zones file |
| `tool/malaysia/raw/esolat/` | Each e-Solat response, gzipped, exactly as fetched |
| `tool/malaysia/raw/selangor/` | The `pdftotext -layout` text of each Selangor PDF, gzipped |
| `tool/malaysia/raw/geoBoundaries-MYS-ADM2_simplified.geojson.gz` | The district polygons, gzipped, exactly as downloaded |
| `tool/malaysia/selangor_sources.csv` | Each Selangor PDF's zone code, URL, retrieval date and SHA-256 |
| `tool/malaysia/corrections.csv` | Reviewed corrections and waivers |
| `tool/malaysia/zones.csv` | The zone catalog |
| `tool/malaysia/districts.csv` | The zone of each district, with split rules |
| `tool/malaysia/special_areas.csv` | Island and highland zones as a centre and a radius |
| `tool/malaysia/town_fixtures.csv` | Every place named in the zone descriptions, with its expected zone |

The Selangor PDFs are not committed because they total 182 MB. Their URLs and SHA-256 hashes are in `selangor_sources.csv` and `MANIFEST`.

## Commands

Run every command from the repository root.

```bash
dart run tool/malaysia/malaysia_times_cli.dart fetch 2028
dart run tool/malaysia/malaysia_times_cli.dart import-selangor ~/Downloads/selangor-2028/*.pdf
dart run tool/malaysia/malaysia_times_cli.dart build
dart run tool/malaysia/malaysia_times_cli.dart lookup 3.1390 101.6869 2027-01-01
```

- `fetch <year>...` posts `datestart` and `dateend` to `https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration&zone=<code>` for every `e-solat` zone that `zones.csv` has in force during the year, and stores each response that holds rows. It keeps a zone and year that already holds rows unless you pass `--refresh`. It stores nothing for a `NO_RECORD!` response. It exits 1, naming the zone and year, when a response is unusable (not JSON, not a JSON object, or without rows for another reason), when a request fails three times, or when `--refresh` gets no rows for a zone and year that already holds rows. In each of those cases it keeps the stored response.
- `import-selangor <pdf>...` runs `pdftotext -layout` (Poppler) on each PDF, checks that it holds every day of the year, stores the text, and records the PDF's SHA-256.
- `build` validates, corrects and encodes everything. It prints every rejected row and exits 1 without writing anything when a row is rejected, an output is over budget, or the timetables do not match the catalog (see [Catalog](#catalog)). On success it prints a summary such as `117 zone-years, 0 rejected, 8 corrected, 24 waived` and the size of each output.
- `lookup <latitude> <longitude> <yyyy-mm-dd>` prints the zone in force at that point on that date, or `none`.

## Validation

`build` checks each row after its corrections are applied. A row is rejected when any of these rules fails and no waiver covers it.

| Rule | Check |
| --- | --- |
| `core-order` | Subuh, Syuruk, Zohor, Asar, Maghrib and Isyak strictly increase |
| `imsak-gap` | Imsak is 0 to 30 minutes before Subuh |
| `daily-step` | Each of the eight times changes by at most 3 minutes from the day before |
| `complete-year` | The zone and year holds every day from 1 January to 31 December |

The output is also limited to 400,000 bytes, and 60,000 bytes gzipped, per file.

## Corrections and waivers

`corrections.csv` has one row per zone, date and field: `zone,date,field,published,corrected,rule,reason,corroboration,date_sent`. Fields use the e-Solat names: `imsak`, `fajr`, `syuruk`, `dhuha`, `dhuhr`, `asr`, `maghrib`, `isha`.

- A **correction** has a `corrected` value that differs from `published`. Add one only for a clear printing error, such as a time off by one or twelve hours. The `corroboration` column names the neighbouring days and an independent calculation, with its parameters and place. The WaktuSolat API mirrors e-Solat, so it cannot corroborate a correction.
- A **waiver** has `corrected` equal to `published`. It keeps a published value that breaks one rule, for one zone, date and field. Use it when the value is ordered and plausible but steps by more than 3 minutes, and ask JAKIM about it.

`build` fails when a row's `published` value no longer matches the source, because the source changed and the row needs review. It also fails when a waiver covers no violation. Report every correction and waiver to JAKIM, and write the date sent into `date_sent`.

## Times format

`malaysia_times.txt` has one line per zone and year, sorted by year and then zone:

```
WLY01 2026 05560606071807431319164219172031eeddedde...
```

The line is the zone code, the year, then the days. The first day is eight four-digit `HHMM` values. Each later day is eight cells, one per time, in the order Imsak, Subuh, Syuruk, Dhuha, Zohor, Asar, Maghrib, Isyak. A cell is one letter for a change from the day before (`a` to `g` for -3 to +3 minutes), or `~HHMM` for a larger change. Times are local times in UTC+8.

Selangor rows carry Dhuha as Syuruk plus 25 minutes, as each Selangor PDF states.

## Zones

### Catalog

`zones.csv` lists each zone with its state, the areas e-Solat names, its validity dates, its successors, a reference point, the source of its timetable and the years whose timetable is unpublished. An empty date means the validity is open on that side. The reference point is the GeoNames position of the zone's first named town, or the centre of its special area.

The `source` column is `e-solat` for a zone that `fetch` downloads, or `selangor-pdf` for a Selangor district whose timetable comes from `selangor_sources.csv`. The `unpublished` column lists, separated by spaces, the years for which the publisher has no timetable yet, such as `2027` for every Sabah zone.

`build` covers every year that has a stored e-Solat response or a `selangor_sources.csv` row. For each of those years it fails, naming the zone and year, when:

- a zone in force during the year has no rows and the year is not in its `unpublished` column
- a zone has rows for a year in its `unpublished` column
- a zone has rows for a year in which `zones.csv` does not have it in force
- a stored e-Solat response holds no rows

JAKIM has not published codes for the nine Selangor districts that take effect on 1 January 2027. The catalog uses these provisional codes:

| Code | District | Replaces |
| --- | --- | --- |
| SGRGBK | Gombak | SGR01 |
| SGRHLG | Hulu Langat | SGR01 |
| SGRHSL | Hulu Selangor | SGR01 |
| SGRPTG | Petaling | SGR01 |
| SGRSPG | Sepang | SGR01 |
| SGRKSL | Kuala Selangor | SGR02 |
| SGRSBN | Sabak Bernam | SGR02 |
| SGRKLG | Klang | SGR03 |
| SGRKLT | Kuala Langat | SGR03 |

SGR01, SGR02 and SGR03 are valid to 31 December 2026 and list these codes as successors. If JAKIM publishes its own codes, add them as new catalog rows valid from the date JAKIM names, make each provisional code valid to the day before, and list the JAKIM code as its successor. Never reuse a code with a new meaning inside one validity period.

### Resolution

A point resolves in three steps.

1. Find the district region that contains the point. When no region contains it, take the nearest region boundary within 500 metres. Some coastal towns sit a few hundred metres seaward of the simplified coastline.
2. Take the first `districts.csv` row for that district whose zone is in force on the date and whose rule matches the point. A rule compares `lat` and `lon` with a number, for example `lon>=101.25`, and rules join with ` & `.
3. If the point lies inside a special area whose zone is in force, and the point is in no district or the district's zone is in the same state, the special area wins.

Districts that hold places from two zones carry ordered rule rows: Hulu Perak, Gua Musang, Rompin, Kinabatangan, Lahad Datu, Subis, Matu and Pusa. Putrajaya lies inside the Sepang polygon, so Sepang's first row is a box for WLY01. Each rule's `source` column names the e-Solat wording it follows and the places on each side.

`town_fixtures.csv` lists every place named in the e-Solat zone descriptions with its GeoNames coordinates and expected zone. `build` and `test/malaysia_zone_fixtures_test.dart` both fail when a fixture resolves to another zone. Add a fixture before you change a rule.

### Zones format

`malaysia_zones.txt` is tab-separated, one record per line. The first field names the record type.

| Type | Fields |
| --- | --- |
| `Z` | Zone: code, state, areas, valid from, valid to, successors (space-separated), reference latitude, reference longitude |
| `S` | Special area: zone, name, latitude, longitude, radius in metres |
| `A` | Arc: one boundary line, encoded with the Google polyline algorithm at precision 1e5, latitude first |
| `R` | Region: arc indices (space-separated, counting `A` records from 0), then zone rows (space-separated) |

```
Z	SGR01	Selangor	Gombak, Petaling, Sepang, Hulu Langat, Hulu Selangor, Shah Alam		2026-12-31	SGRGBK SGRHLG SGRHSL SGRPTG SGRSPG	3.3213	101.5767
S	JHR01	Pulau Aur	2.44969	104.52109	6000
R	24 25 26 31 108 109 110 111 112	PHG07:lon>=103.2 PHG02
```

A zone row is a zone code, optionally followed by `:` and a rule with no spaces, such as `PHG07:lon>=103.2`.

`build` produces the regions and arcs from the district polygons:

1. Every vertex is rounded to 1e-5 degrees.
2. Districts with the same ordered zone rows merge into one region.
3. A border between two districts of one region drops out. A point is inside a region when a ray from it crosses the region's arcs an odd number of times, so holes and islands need no special handling.
4. The remaining borders are cut into arcs at every junction. Each arc is stored once and shared by the regions on both sides.
5. Each arc is simplified with Douglas-Peucker at 100 metres, keeping its end points.

`build` fails when a district has no row, a row names an unknown zone, a rule is malformed, or a fixture resolves to the wrong zone. It also prints any point of a 0.02-degree grid that falls in two regions.

## Yearly update

Run this in the fourth quarter, so a release ships before 1 January.

1. Run `fetch <next year>`. For each zone that returns `NO_RECORD!`, add the year to the zone's `unpublished` column in `zones.csv`. Those zones fall back to calculated times for that year.
2. If the Selangor Mufti publishes district PDFs for the next year, download them, add their rows to `selangor_sources.csv`, and run `import-selangor`.
3. Run `build`. Read every rejected row. Add a correction only for a clear printing error with corroboration, and a waiver for a plausible step. Draft a report to JAKIM for both.
4. Run `dart test`.
5. Commit the raw files, the CSVs and the generated files together, and release.
6. Copy `malaysia_times.txt`, `malaysia_zones.txt` and `MANIFEST` into the other language versions and run their hash check.

Until JAKIM publishes the Sabah 2027 timetable, run `fetch 2027` weekly. When the Sabah rows arrive, remove `2027` from the `unpublished` column of each Sabah zone, rebuild and release.

## Licences

The district polygons are from geoBoundaries gbOpen MYS ADM2 under CC BY 3.0. The town coordinates are from GeoNames under CC BY 4.0. Both credits are in `README.md`. The timetables are published by JAKIM and the Selangor State Mufti Department.
