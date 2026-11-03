# Malaysian Prayer Times Data Maintenance Guide

This guide describes how the Malaysian timetable and zone data is fetched, validated, encoded and released. It is for the engineer who updates the data each year, and for anyone porting the data to another language version of this package.

## Overview

Malaysia publishes official prayer times per zone. JAKIM serves them through e-Solat. From 2027 the Selangor State Mufti Department publishes Selangor as nine district timetables in PDF form, which e-Solat does not carry. The generator reads both, checks every row, applies a reviewed list of corrections, and writes two compact text files plus a manifest of hashes.

| Output | Content |
| --- | --- |
| `data/malaysia/malaysia_times.txt` | One line per zone and year with eight times per day |
| `data/malaysia/malaysia_zones.txt` | The zone catalog, the special areas and the district polygons |
| `data/malaysia/MANIFEST` | The SHA-256 of both outputs and of every source, with the request that retrieves it and its retrieval date. See [Manifest format](#manifest-format) |
| `lib/src/data/malaysia_times_data.dart` | `malaysiaTimesData`, the times file as a Dart string |
| `lib/src/data/malaysia_zones_data.dart` | `malaysiaZonesData`, the zones file as a Dart string |

The two Dart constants hold the same bytes as the text files. Other language versions copy the text files and check them against `MANIFEST`.

## Files

| Path | Purpose |
| --- | --- |
| `tool/malaysia/malaysia_times_cli.dart` | The `fetch`, `import-selangor`, `build` and `lookup` commands |
| `tool/malaysia/src/malaysia_timetables.dart` | Fetching, parsing, validation and correction of the timetables |
| `tool/malaysia/src/malaysia_zones.dart` | The zone catalog, district rules, polygon simplification and arc encoding |
| `tool/malaysia/src/malaysia_states.dart` | Moving state borders onto the ADM1 line, and the state check |
| `lib/src/data/malaysia_times_codec.dart` | Encoder and decoder for the times file |
| `lib/src/data/malaysia_zone_map.dart` | Decoder and point-to-zone resolver for the zones file |
| `tool/malaysia/raw/esolat/` | Each e-Solat response, gzipped, exactly as fetched |
| `tool/malaysia/raw/selangor/` | The `pdftotext -layout` text of each Selangor PDF, gzipped |
| `tool/malaysia/raw/geoBoundaries-MYS-ADM2_simplified.geojson.gz` | The district polygons, gzipped, exactly as downloaded |
| `tool/malaysia/raw/geoBoundaries-MYS-ADM1_simplified.geojson.gz` | The state polygons, gzipped, exactly as downloaded. They give the Putrajaya polygon and the borders between states |
| `tool/malaysia/selangor_sources.csv` | Each Selangor PDF's zone code, URL, retrieval date and SHA-256 |
| `tool/malaysia/corrections.csv` | Reviewed corrections and waivers |
| `tool/malaysia/zones.csv` | The zone catalog |
| `tool/malaysia/districts.csv` | The zone of each district, with split rules |
| `tool/malaysia/special_areas.csv` | Island and highland zones as a centre, a radius and a parent district |
| `tool/malaysia/islands.csv` | Islands that geoBoundaries ADM2 leaves out, as a centre, a radius and a district |
| `tool/malaysia/state_exceptions.csv` | Boxes where the ADM1 state line is wrong, so the district line stays |
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

- `fetch <year>...` posts `datestart` and `dateend` to `https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration&zone=<code>` for every `e-solat` zone that `zones.csv` has in force during the year, and stores each response that holds rows. It keeps a zone and year that already holds rows unless you pass `--refresh`. It stores nothing for a `NO_RECORD!` response. It exits 1, naming the zone and year, when a response is unusable (not JSON, not a JSON object, or without rows for another reason), when a request fails three times, when `--refresh` gets no rows for a zone and year that already holds rows, or when a stored file is not gzip. In each of those cases it keeps the stored response.
- `import-selangor <pdf>...` runs `pdftotext -layout` (Poppler) on each PDF, checks that it holds every day of the year, stores the text, and records the PDF's SHA-256.
- `build` validates, corrects and encodes everything. It prints every rejected row and exits 1 without writing anything when a row is rejected, an output is over budget, a stored raw file is not gzip (it names the file and the zone and year), the timetables do not match the catalog (see [Catalog](#catalog)), or a zone check fails (see [Zones format](#zones-format)). On success it prints a summary such as `117 zone-years, 0 rejected, 8 corrected, 24 waived` and the size of each output.
- `lookup <latitude> <longitude> <yyyy-mm-dd>` prints the zone in force at that point on that date, or `none`. It does not check the times file, so it prints a Sabah zone for a date in 2027 although Sabah has no 2027 timetable yet.

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
2. If the point lies inside a special area whose parent district is that region and whose zone is in force on the date, the special area's zone wins.
3. Otherwise take the first `districts.csv` row for that district whose zone is in force on the date and whose rule matches the point. A rule compares `lat` and `lon` with a number, for example `lon>=101.25`, and rules join with ` & `.

Districts that hold places from two zones carry ordered rule rows: Hulu Perak, Gua Musang, Rompin, Kinabatangan, Lahad Datu, Subis, Matu and Pusa. Each rule's `source` column names the e-Solat wording it follows and the places on each side.

#### Putrajaya

The geoBoundaries ADM2 layer has no Putrajaya shape, and its Sepang shape covers Putrajaya. `districts.csv` therefore maps the Putrajaya polygon from the geoBoundaries ADM1 layer to WLY01. A `districts.csv` row whose shape comes from the ADM1 layer must lie inside exactly one ADM2 shape. `build` cuts it out of that shape, so Sepang keeps the land around Putrajaya and Putrajaya resolves to WLY01.

#### State borders

The geoBoundaries ADM2 district shapes and the ADM1 state shapes come from different sources. geoBoundaries records citypopulation.de for ADM2 and a 2017 OpenStreetMap export for ADM1. Along the land borders between states they disagree by up to about 5 kilometres, and neither is right everywhere. Sindumin and six other villages of Sipitang, Sabah, lie inside the ADM2 Lawas shape, which made them resolve to the Sarawak zone SWK01; ADM1 and current OpenStreetMap put them in Sabah. Kampung Jabur and other villages of Kemaman, Terengganu, lie inside ADM1 Pahang; the ADM2 shapes and current OpenStreetMap put them in Terengganu.

`state_borders.csv` lists the borders that follow the ADM1 line. Each row names two states, a box and the evidence. Inside the box, `build` moves each border between a region of one state and a region of the other onto ADM1:

1. The border is replaced by the line the two states share in ADM1.
2. Each end of the border moves onto the ADM1 line. Where three regions meet inland, the end moves to the nearest vertex the states share in ADM1, and a district border inside one state that then crosses the new line is cut where it meets it. Where the border reaches the coast or a national border, the end moves to the end of the ADM1 line. If that point lies inside a district shape, the coastline or national border is cut at the point nearest to it.

Every other border keeps the ADM2 line, so inside a state the district shapes still decide the zone.

`build` then checks the result against ADM1. It resolves every point of a 0.002-degree grid (about 220 metres) that lies inside an ADM1 state, on 31 December 2026 and 1 January 2027. It groups the points that lie more than 150 metres inside a state but resolve to a zone of another state into areas. The 150 metres allow for the 100-metre simplification of both layers. Each area must lie inside a box in `state_exceptions.csv` for the same two states. `build` fails on every other area, and names its zones, the two states, its size, its deepest point and its bounding box. `build` also fails when moving the borders makes two arcs cross where they did not cross before.

`state_exceptions.csv` lists the places where the check's reference, ADM1, is wrong: the borders that keep the ADM2 line, Pulau Tioman and Pulau Seri Buat, which ADM1 puts in Johor, and one wedge at the Sabah-Sarawak-Kalimantan tri-point that the national border causes. Each row names its evidence.

The rows in both files were chosen against the OpenStreetMap state boundaries of 3 November 2026. A border follows ADM1 when OpenStreetMap agrees with ADM1 at most of the check's points along it and at the populated places on it. To change a border, confirm with a second source, such as OpenStreetMap or a state gazette, which line is right. Then add or narrow a row, rebuild, and add a fixture for each populated place on the changed stretch.

#### Special areas

`special_areas.csv` lists the island and highland zones as a centre, a radius and a parent district. A special area applies only to points that resolve to its parent district, so it never takes land from a neighbouring district. `build` makes each parent district its own region for this. It also samples each special area on a 100-metre grid and fails when a point that resolves to the special area's zone lies more than 500 metres inside another district of the same state. Across a state border, the state check decides.

SWK09, Zon Khas (Kampung Patarikan), has no special area. No map source, GeoNames or OpenStreetMap included, gives the position of Kampung Patarikan, so `lookup` never returns SWK09. Merapok and the Lawas villages around it resolve to SWK01, as the e-Solat wording for Lawas says. The villages across the Sabah border, such as Sindumin, resolve to SBH09. SWK09 stays in the catalog, and the times file keeps its timetable, so an app can offer it for manual selection.

#### Islands

The geoBoundaries ADM2 layer leaves out some islands that the ADM0 layer of the same release includes, and both layers leave out small islands such as Pulau Mabul. `islands.csv` adds each of these as an island area: an octagon with its corners at the given radius from the centre, added to the named district. A point inside the octagon resolves like a point in that district. The octagon may leave out part of a long or irregular island; see [Known limitations](#known-limitations).

- Each row's `source` column names the GeoNames island, the settlement on it, whether geoBoundaries ADM0 has a ring for it, and the nearest district.
- The district is the nearest ADM2 district unless a source says otherwise.
- `build` fails when an island area touches a district shape or another island area, so an island area never changes how a point on land resolves.

The list covers every GeoNames island and populated place (feature class P) that lies inside the unsimplified geoBoundaries ADM0 boundary and would otherwise resolve to no zone, and populated islands outside ADM0, such as Pulau Mabul. To check a new release, list the GeoNames features inside ADM0, run each through `lookup`, and add an island area for each feature that returns `none`.

#### Fixtures

`town_fixtures.csv` lists every place named in the e-Solat zone descriptions with its GeoNames coordinates and expected zone, plus populated islands, populated places along the borders between states, and points on each side of the special-area and Putrajaya boundaries. `build` and `test/malaysia_zone_fixtures_test.dart` both fail when a fixture resolves to another zone. Add a fixture before you change a rule.

#### Known limitations

- The split rules for Gua Musang, Rompin, Hulu Perak, Kinabatangan, Lahad Datu, Subis, Matu and Pusa are latitude or longitude lines drawn between the places the e-Solat wording names. No mukim polygon exists to check them, so each line is right at the named places but unproven between them, and land far from every named place can fall on the wrong side. Gua Musang's KTN01 side alone covers about 3,100 square kilometres.
- Neither state line matches OpenStreetMap everywhere. On the borders that keep the ADM2 line, 57 check areas (9.3 km2) where OpenStreetMap agrees with ADM1 keep the ADM2 line. On the borders that follow ADM1, 30 check areas (9.2 km2) where OpenStreetMap agrees with ADM2 now follow ADM1. No GeoNames populated place lies in them. Three GeoNames places resolve to a state other than OpenStreetMap's: the Genting Highlands town point and The Gap lie within 150 metres of the ADM1 line on its Selangor side, and Pulau Terus, at the Kesang estuary, is in Johor for GeoNames and in Melaka for OpenStreetMap.
- Moving a border's end onto the ADM1 line also moves the end of each district border inside the state that meets it, by up to the distance between the two lines. Taman Sri Ehsan, 38 metres from the Petaling line, moves from Gombak to Petaling for 2027.
- Points outside Malaysia near its borders can resolve to a Malaysian zone. The ADM2 district shapes run past the geoBoundaries ADM0 national border by up to about 2.7 kilometres, and a point outside every district within 500 metres of one resolves to that district. See [Notes for the public API](#notes-for-the-public-api) for the measured reach past each border.
- Island areas are octagons, not island outlines. They cover the whole geoBoundaries ADM0 ring of 15 of the 22 islands that have one, and 95 to 99 percent of Pulau Kaniogan, Pulau Kukup and Pulau Sulok. Pulau Langgun, Pulau Sedam, Pulau Tanjung Dendang, and the ring that holds Pulau Puru Puru and Tanjong Nuig are only partly covered, because a larger octagon would touch a district or another island area. A point on the uncovered part resolves only when it lies within 500 metres of a district or island area. On a 50-metre grid, 26 of 2,755 points on Pulau Langgun, 139 of 549 on Pulau Tanjung Dendang and 153 of 723 on the Pulau Puru Puru ring resolve to no zone. No GeoNames populated place lies on those points. Island districts come from the nearest district rather than an official list.
- `lookup` returns the Sabah zones for 2027, but Sabah has no 2027 timetable yet. A caller must check that the times file holds the zone and year before it uses official times.

### Zones format

`malaysia_zones.txt` is tab-separated, one record per line. The first field names the record type.

| Type | Fields |
| --- | --- |
| `Z` | Zone: code, state, areas, valid from, valid to, successors (space-separated), reference latitude, reference longitude |
| `S` | Special area: zone, name, latitude, longitude, radius in metres, parent region (counting `R` records from 0) |
| `A` | Arc: one boundary line, encoded with the Google polyline algorithm at precision 1e5, latitude first |
| `R` | Region: arc indices (space-separated, counting `A` records from 0), then zone rows (space-separated) |

```
Z	SGR01	Selangor	Gombak, Petaling, Sepang, Hulu Langat, Hulu Selangor, Shah Alam		2026-12-31	SGRGBK SGRHLG SGRHSL SGRPTG SGRSPG	3.3213	101.5767
S	JHR01	Pulau Aur	2.44969	104.52109	6000	3
R	28 29 30 41 128 129 130 131 132	PHG07:lon>=103.2 PHG02
```

A zone row is a zone code, optionally followed by `:` and a rule with no spaces, such as `PHG07:lon>=103.2`.

`build` produces the regions and arcs from the district polygons:

1. Every vertex is rounded to 1e-5 degrees.
2. Districts with the same ordered zone rows merge into one region, except that the parent district of a special area keeps its own region. Island areas join their district first, and an ADM1 shape is cut out of the ADM2 shape that holds it.
3. A border between two districts of one region drops out. A point is inside a region when a ray from it crosses the region's arcs an odd number of times, so holes and islands need no special handling.
4. The remaining borders are cut into arcs at every junction. Each arc is stored once and shared by the regions on both sides.
5. Each arc between regions of two different states follows the ADM1 line (see [State borders](#state-borders)).
6. Each arc is simplified with Douglas-Peucker at 100 metres, keeping its end points.

`build` fails when a district has no row, a row names an unknown zone, a rule is malformed, a fixture resolves to the wrong zone, a special area reaches more than 500 metres into another district of its state, an island area touches land or another island area, a point of a 0.02-degree grid falls in two regions, the state check finds an area that no exception explains, or following the ADM1 state borders makes two arcs cross.

## Notes for the public API

These notes are for anyone who builds a public API on the decoder and resolver in `lib/src/data/`.

- The resolver answers for any point and does not know the country. Points outside Malaysia near its land borders resolve to a Malaysian zone. A caller must check that the user is in Malaysia, for example from the platform's reverse geocoder, before it uses official times.
- The reach past each border, measured on a 100-metre grid of foreign land within 8 kilometres of the geoBoundaries ADM0 border of Malaysia, on 1 June 2026 and 1 June 2027:

  | Country | Farthest point that resolves | Zone | Distance past the border | Foreign land that resolves, within 3 km |
  | --- | --- | --- | --- | --- |
  | Brunei | 4.89474, 115.05230 | SWK01 | 3.0 km | 219 km2 |
  | Indonesia | 1.20936, 110.03502 | SWK08 | 2.9 km | 1,084 km2 |
  | Singapore | 1.43623, 104.02910 | JHR02 | 2.9 km | 1.3 km2 |
  | Thailand | 5.74876, 101.24499 | PRK03 | 1.0 km | 254 km2 |

  The Philippines has no land within 8 kilometres. In Singapore no district shape covers land; the points lie within 500 metres of the Johor shape in the strait.
- The resolver returns Sabah zones for 2027, but Sabah has no 2027 timetable yet. A caller must check that the times file holds the zone and year.
- The resolver never returns SWK09, because no source locates Kampung Patarikan. Offer it for manual selection.

## Manifest format

`data/malaysia/MANIFEST` is tab-separated, with a header row and one row per output file and per source.

| Column | Content |
| --- | --- |
| `kind` | `output` for a generated file. For a source: `esolat`, `selangor-pdf`, `selangor-text` or `geoboundaries` |
| `name` | The output file name, the zone and year, or the geoBoundaries layer and release |
| `retrieved` | The date the source was retrieved. For e-Solat it is the date of the response's `serverTime`. Empty for an output |
| `method` | The HTTP method that retrieves the source: `POST` for e-Solat and `GET` for a Selangor PDF or a geoBoundaries file. Empty for an output and for `selangor-text` |
| `url` | The request URL. For `selangor-text` it is the path of the committed text in this repository |
| `form` | The form fields a `POST` sends as `application/x-www-form-urlencoded`. Empty for every other row |
| `sha256` | The SHA-256 of the file, as described below |

Each hash covers decompressed bytes. For `esolat` and `geoboundaries` it is the response body as downloaded, which is the decompressed content of the gzipped file under `tool/malaysia/raw/`. For `selangor-pdf` it is the PDF as downloaded. For `selangor-text` it is the decompressed `pdftotext` output. For `output` it is the file in `data/malaysia/`.

To repeat an e-Solat request, send the form fields to the URL, for example `curl -X POST -d 'datestart=2026-01-01&dateend=2026-12-31' 'https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration&zone=WLY01'`. A new response carries a new `serverTime`, so its hash differs even when its `prayerTime` rows are the same.

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

The district polygons are from geoBoundaries gbOpen MYS ADM2 (sources geoBoundaries and citypopulation.de, CC BY 3.0). The Putrajaya polygon and the borders listed in `state_borders.csv` are from geoBoundaries ADM1, and the island positions were checked against ADM0. geoBoundaries records ADM1 and ADM0 as © OpenStreetMap contributors (Wambacher export, 2017) under the Open Database License 1.0. The town coordinates are from GeoNames under CC BY 4.0. Both credits are in `README.md`. The timetables are published by JAKIM and the Selangor State Mufti Department.
