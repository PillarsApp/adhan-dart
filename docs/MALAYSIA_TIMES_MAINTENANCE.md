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
| `data/malaysia/LICENSE-ODbL.md` | The licence of the zone map and of the OpenStreetMap data it is built from. See [Licences](#licences) |

The two Dart constants hold the same bytes as the text files. Other language versions copy the text files, `MANIFEST` and `LICENSE-ODbL.md`, check the hashes, and carry the credits in [Licences](#licences).

## Files

| Path | Purpose |
| --- | --- |
| `tool/malaysia/malaysia_times_cli.dart` | The `fetch`, `import-selangor`, `fetch-osm`, `import-osm-extract`, `build`, `check` and `lookup` commands |
| `tool/malaysia/src/malaysia_timetables.dart` | Fetching, parsing, validation and correction of the timetables |
| `tool/malaysia/src/malaysia_zones.dart` | The zone catalog, district rules and arc encoding |
| `tool/malaysia/src/border_simplify.dart` | Polygon simplification, the zone pairs whose times differ, and the outline test of OpenStreetMap features near state lines with the vertices it keeps |
| `tool/malaysia/src/osm_snapshot.dart` | The pinned OpenStreetMap snapshot: the Overpass query, the ring assembly and the state lookups |
| `tool/malaysia/src/osm_fetch.dart` | `fetch-osm`, which downloads the snapshot for its pinned date |
| `tool/malaysia/src/osm_extract.dart` | `import-osm-extract`, which filters the pinned Geofabrik extract to the OpenStreetMap features the build checks |
| `tool/malaysia/src/stitch_borders.dart` | Replacing every border between two states with the OpenStreetMap line, and cutting the OpenStreetMap rings named in `districts.csv` out of the district that covers them |
| `tool/malaysia/src/malaysia_states.dart` | The state check: the shipped map against the full-resolution snapshot, and land or places with no zone |
| `tool/malaysia/src/geometry.dart` | Point, segment and ring arithmetic shared by the modules above |
| `tool/malaysia/src/gzip_input.dart` | Reading a stored gzip file and rejecting an empty, truncated or corrupt one |
| `lib/src/data/malaysia_times_codec.dart` | Encoder and decoder for the times file |
| `lib/src/data/malaysia_zone_map.dart` | Decoder and point-to-zone resolver for the zones file |
| `tool/malaysia/raw/esolat/` | Each e-Solat response, gzipped, exactly as fetched |
| `tool/malaysia/raw/selangor/` | The `pdftotext -layout` text of each Selangor PDF, gzipped |
| `tool/malaysia/raw/geoBoundaries-MYS-ADM2_simplified.geojson.gz` | The district polygons, gzipped, exactly as downloaded |
| `tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz` | The Overpass response with Malaysia's 16 `admin_level=4` relations, gzipped, exactly as downloaded. It gives every border between states, the Putrajaya ring, the Tanjung Tuan exclave and Pulau Aceh |
| `tool/malaysia/raw/openstreetmap-MYS-border-features.tsv.gz` | Every OpenStreetMap feature of the classes in [Commands](#commands) with any part of its outline within 150 metres of a state line, as its centre and its outline, from the pinned Geofabrik extract |
| `tool/malaysia/raw/openstreetmap-MYS-offmap-features.tsv.gz` | The same kinds of feature whose centre lies inside a state in the snapshot but more than 400 metres outside every district polygon, as its centre and its outline. `build` and `check` decode every outline and fail on a malformed one, but resolve only the centres |
| `tool/malaysia/selangor_sources.csv` | Each Selangor PDF's zone code, URL, retrieval date and SHA-256 |
| `tool/malaysia/corrections.csv` | Reviewed corrections and waivers |
| `tool/malaysia/zones.csv` | The zone catalog |
| `tool/malaysia/districts.csv` | The zone of each district, with split rules; a row's shape is a geoBoundaries ADM2 `shapeID` or an OpenStreetMap ring |
| `tool/malaysia/special_areas.csv` | Island and highland zones as a centre, a radius and a parent district |
| `tool/malaysia/islands.csv` | Islands that geoBoundaries ADM2 leaves out, as a centre, a radius and a district |
| `tool/malaysia/town_fixtures.csv` | Every place named in the zone descriptions, with its expected zone, plus the places checked on each border |
| `tool/malaysia/state_line_exceptions.csv` | Stretches where a source says the OpenStreetMap state line is wrong, with the line that replaces it and the source |
| `tool/malaysia/no_zone_areas.csv` | The OpenStreetMap features off the map that resolve to no zone, by OpenStreetMap id, in named areas, each with a reason |

The Selangor PDFs are not committed because they total 182 MB. Their URLs and SHA-256 hashes are in `selangor_sources.csv` and `MANIFEST`.

## Commands

Run every command from the repository root.

```bash
dart run tool/malaysia/malaysia_times_cli.dart fetch 2028
dart run tool/malaysia/malaysia_times_cli.dart import-selangor ~/Downloads/selangor-2028/*.pdf
dart run tool/malaysia/malaysia_times_cli.dart fetch-osm
dart run tool/malaysia/malaysia_times_cli.dart import-osm-extract ~/Downloads/malaysia-singapore-brunei-261103.osm.pbf
dart run tool/malaysia/malaysia_times_cli.dart build
dart run tool/malaysia/malaysia_times_cli.dart check data/malaysia/malaysia_zones.txt
dart run tool/malaysia/malaysia_times_cli.dart lookup 3.1390 101.6869 2027-01-01
```

- `fetch <year>...` posts `datestart` and `dateend` to `https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration&zone=<code>` for every `e-solat` zone that `zones.csv` has in force during the year, and stores each response that holds rows. It keeps a zone and year that already holds rows unless you pass `--refresh`. It stores nothing for a `NO_RECORD!` response. It stores a response only when its rows are the days of the year, each once and in order. It exits 1, naming the zone and year, when a response is unusable (not JSON, not a JSON object, without rows for another reason, or with rows for another year or for part of the year), when a request fails three times, when `--refresh` gets no rows for a zone and year that already holds rows, or when a stored file is not gzip. In each of those cases it keeps the stored response.
- `import-selangor <pdf>...` runs `pdftotext -layout` (Poppler) on each PDF, checks that it holds every day of the year, stores the text, and records the PDF's SHA-256.
- `fetch-osm` posts the Overpass query in `tool/malaysia/src/osm_snapshot.dart` to the Overpass API and stores the response as `tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz`. The query carries the pinned date (`osmSnapshotDate`), so a rerun returns the boundaries as they stood at that moment; only the response header, which names the server's current database time, differs, so compare the `elements` array rather than the whole file. It writes nothing from a response whose `osm_base` is older than the pinned date, that carries an Overpass `remark`, that lacks a state relation or the geometry of a border way, or that has fewer rings for a state than the stored snapshot. The public servers are often at capacity, so the command tries three servers in three rounds with growing pauses and exits 1 if none returns a usable snapshot. To move to a newer snapshot, change `osmSnapshotDate`, run `fetch-osm`, then `import-osm-extract` and `build`, and read every fixture and check result. Delete the stored snapshot first if a ring is meant to disappear.
- `import-osm-extract <pbf>` reads a local copy of the pinned Geofabrik extract `https://download.geofabrik.de/asia/malaysia-singapore-brunei-261103.osm.pbf` (OpenStreetMap data of 2026-11-03T21:24:23Z), checks its SHA-256 against `osmExtractSha256` in `tool/malaysia/src/osm_extract.dart`, and filters it with `osmium` (osmium-tool). It keeps every `building=*` and `place=*`, every `tourism=*` stay (hotel, motel, guest house, hostel, chalet, apartment, camp or caravan site, hut), every `amenity=school`, `place_of_worship`, `kindergarten`, `college`, `university`, `hospital` or `clinic`, every `leisure=resort`, every `landuse=residential` area with a name, and every feature with an `addr:housenumber`. It writes each feature's centre, the centre of its bounding box rounded to 1e-5 degrees, and its outline, every ring or line of its geometry rounded to 1e-5 degrees and encoded with the Google polyline algorithm, into two files: the features with any point of the outline within 150 metres of a state line, and the features whose centre lies inside a state but more than 400 metres outside every district polygon. A `place=*` feature counts by its centre only, because a place polygon, such as a state's, is drawn along the boundary itself. The command prints the SHA-256 of each file when it differs from `osmBorderFeaturesSha256` or `osmOffMapFeaturesSha256` in `tool/malaysia/src/osm_extract.dart`; `build` and `check` read only files with the pinned hashes, so a hand-edited extract fails both. Geofabrik keeps dated daily files for a limited time. To move to a newer file, first set `osmExtractUrl`, `osmExtractTimestamp` and `osmExtractSha256` in `tool/malaysia/src/osm_extract.dart`, because the command refuses any other file, exits 1 and writes nothing. Then run the command, set `osmBorderFeaturesSha256` and `osmOffMapFeaturesSha256` to the hashes it prints, and run `build`, which writes the new file name, time and hash into `MANIFEST`. Replace the old file name and time in `data/malaysia/LICENSE-ODbL.md`, in the README credit, and in this guide's `import-osm-extract` example, the URL and timestamp of the `import-osm-extract` bullet, and [Licences](#licences). Then review the changes. We used a Geofabrik extract rather than Overpass because the public Overpass servers refused queries for every building near the state lines on 2026-11-04.
- `build` validates, corrects and encodes everything. It prints every rejected row and exits 1 without writing anything when a row is rejected, an output is over budget, a stored raw file is empty, truncated, corrupt or not gzip (it names the file, and for a timetable the zone and year), a geoBoundaries or OpenStreetMap file is not the JSON the build expects, an extract does not have its pinned SHA-256, or a CSV is missing, empty or has a row with the wrong number of fields (it names the file in each case), the timetables do not match the catalog (see [Catalog](#catalog)), or a zone check fails (see [Zones format](#zones-format)). On success it prints a summary such as `117 zone-years, 0 rejected, 8 corrected, 24 waived` and the size of each output.
- `check <zones file>` runs the outline test of [Simplification near state lines](#simplification-near-state-lines), the state check of [State borders](#state-borders) and the no-zone check of [Land with no zone](#land-with-no-zone) on any zones file, for example an older release or a copy another language version carries. It prints every border feature with an outline point within 110 metres of a state line on another state's zone, and every area, and exits 1 when one fails. Outline points 110 to 150 metres from the line are neither printed nor counted. It also exits 1, naming the file, when the zones file, the snapshot, the geoBoundaries ADM2 file, an extract, `zones.csv`, `state_line_exceptions.csv` or `no_zone_areas.csv` is missing or cannot be read, or an extract does not have its pinned SHA-256. Every command exits 1 and names the file when a CSV it reads is missing, empty or has a row with the wrong number of fields.
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

#### Putrajaya, Tanjung Tuan and Pulau Aceh

A `districts.csv` row whose `shape_id` is `MY-16@2.9264/101.6964` takes its shape from the OpenStreetMap snapshot: the ring of the relation with that ISO 3166-2 code that contains the point. Three rows use this form. Putrajaya has no geoBoundaries ADM2 shape, and the Sepang shape covers it. Tanjung Tuan, the Melaka exclave at Cape Rachado, is missing from every geoBoundaries layer, and the Port Dickson shape covers its land. Pulau Aceh, 16 km east of Endau, is a Pahang island that the sea part of the Mersing shape covers. `build` cuts each ring out of the shapes of other states that it lies in or crosses: a ring inside a shape becomes a hole, and where a ring crosses a shape's coast, the shape's run inside the ring is replaced by the ring's path inside the shape. `build` fails when an outer ring of a state in the snapshot lies inside a shape of another state and no row names it.

#### State borders

Inside a state the geoBoundaries ADM2 district shapes decide the zone. Between states the OpenStreetMap snapshot decides, except on the stretches in `state_line_exceptions.csv`. `build` stitches the two sources together:

1. Every run of a district's ring that it shares with a district of another state is an inter-state run. Its ends are junctions.
2. Each junction is moved onto the OpenStreetMap line. Where a district border inside a state meets the junction, that border is extended straight to the line, or cut where it already crosses the line, so the border inside the state keeps its own course. Usually only its last metres move, but a border that meets the line at a shallow angle pivots along its length: the Mersing and Segamat border moves by up to 16 metres along 15.5 kilometres, and the Lipis and Jerantut border by up to 75 metres along 1.8 kilometres, up to 27 kilometres from the junction; neither strip holds a populated place. Where three states meet, the junction moves to the point where the three OpenStreetMap relations meet. Where a border reaches the coast or the national border, the junction moves to the point where the OpenStreetMap line crosses the district's coast, or to the end of the OpenStreetMap line between the two states; the coast between the old junction and the new one changes district. If a straight connector from the old junction to that end would pass through either state, the connector starts further along the coast, at the first point from which the straight line stays outside both states.
3. Each inter-state run is replaced by the OpenStreetMap line between its two moved junctions.

So a state border moves a district border inside a state only near the junction where they meet. An earlier build moved the whole Gombak and Petaling border onto the state line, which put Taman Sri Ehsan on the wrong zone. The shipped coastline and national border are the ADM2 line, simplified at 100 metres except within 150 metres of a fixture, where every raw ADM2 segment stays. The exceptions are the coast of Pulau Aceh and the seaward edge of the Tanjung Tuan exclave, which come from the snapshot. So what counts as land, and how far a zone reaches past the national border, follows the ADM2 layer.

`state_line_exceptions.csv` lists each stretch where a source says the OpenStreetMap line is wrong. A row names the territory that loses land, the territory that gains it, a path and the source. The path starts and ends on the snapshot's line between the two territories, within 2 metres, and runs through the territory that loses land. `build`, `check` and `import-osm-extract` replace the snapshot's line between the two ends with the path before they use the snapshot, and fail, naming the row, when the path does not end on that line. The one row is Jalan 16/2, Section 16, Petaling Jaya. OpenStreetMap puts its Nos. 1 to 26 up to 102 metres inside Kuala Lumpur, and its line here has not changed since 2017. The houses carry the Petaling Jaya postcode 46350 and the Section 16 street name, property listings place the street in Petaling Jaya, Selangor, and the geoBoundaries ADM2 Petaling shape covers them. The path follows the ADM2 line from its crossing with the OpenStreetMap line to longitude 101.6448. It then runs between the Jalan 16/2 houses and the Lorong 16/2A houses inside the bend of Jalan 16/2, whose OpenStreetMap addresses carry the Kuala Lumpur postcode 59100, and meets the OpenStreetMap line again at longitude 101.6452. It moves the 22 Jalan 16/2 houses, the 8 Jalan Dato Abu Bakar 16/1 houses between them and the OpenStreetMap line, and one building without an address, each whole, and leaves every Lorong 16/2A house in Kuala Lumpur. The houses on each side stand about 3 metres apart, so the path passes 1.41 metres from Jalan 16/2 No. 1, 1.61 metres from No. 5 and 1.11 metres from Lorong 16/2A No. 2, measured on the shipped line. Each of these houses resolves to its own side at every sample.

`build` then measures the shipped map against the full-resolution snapshot. It resolves every point of a 0.001-degree grid (about 110 metres) that lies inside a state or federal territory in the snapshot, on every date where a zone in `zones.csv` starts or ends (now 31 December 2026 and 1 January 2027). It groups into areas the points that lie more than 110 metres inside and resolve to a zone of another state or territory. Kuala Lumpur, Putrajaya and Labuan count as three territories: a Wilayah Persekutuan zone belongs to the territories its `areas` column names, so WLY01 belongs to Kuala Lumpur and Putrajaya, and WLY02 to Labuan. Special areas count like district rows, so a special area moved onto another state's land fails. The 110 metres exceed the 100-metre simplification plus the rounding to 1e-5 degrees, so a point deeper than that can only be on the wrong side through an error in the data, never through the simplification. The grid reads the snapshot, not the shipped arcs, and finds a wrong area only when a grid point falls inside it. An arc that puts a strip of land narrower than the grid on the wrong side can pass. A test copy of the map with a tooth 56 metres wide and 442 metres deep added to the Negeri Sembilan and Pahang border, between two grid columns, put NGS01 up to about 400 metres inside Pahang, up to 4 minutes off, and `check` exited 0. Nearer the line, the outline test of [Simplification near state lines](#simplification-near-state-lines) catches an arc that puts an outline point of a feature in the extract on the wrong side, and `check` runs it too. It does not test land that no outline reaches. `build` fails on every area on land, naming its zones, the two states or territories, its size, its deepest point and its bounding box. An area whose points all lie outside every district polygon, so that only the 500-metre snap reaches them, is reported but does not fail; at this release those are four areas of sea, 2.64 km2 in all, where the snap crosses a state's maritime line (see [Known limits](#known-limits)). `check` runs the same measurement on any zones file. `build` also fails when the stitching makes two arcs cross where the district polygons did not cross before.

#### Simplification near state lines

Each arc is simplified with Douglas-Peucker. On a state border the tolerance is 80 metres wherever a zone on one side and a zone on the other differ by 2 minutes or more in any published time on any day both publish; everywhere else it is 100 metres. The build derives these zone pairs from the times file it has just built. A vertex counts the zones of the district rows whose rule matches it, and of the special areas whose circle comes within 100 metres of it. Of the zone pairs that meet across a state line, only WLY01 against SGR01, SGRGBK, SGRPTG and SGRSPG differ by at most 1 minute, so the 80 metres apply on every state border except those stretches of the Kuala Lumpur and Putrajaya lines.

The build also keeps the full-resolution line where people are. It reads each feature of `openstreetmap-MYS-border-features.tsv.gz` as its outline points: every vertex of its outline, and a point every 5 metres along each edge, rounded to 1e-5 degrees. A feature carries the first of these tags that it has: a `tourism=*` stay, `amenity=school` or `place_of_worship`, `place=*`, `building=*`, `amenity=kindergarten`, `college`, `university`, `hospital` or `clinic`, `leisure=resort`, a named `landuse=residential`, `addr:housenumber`. A feature whose tag is `place=*` has one point, its centre, even when it also carries `building=*` or `landuse=residential`. A place that is also a stay, a school or a place of worship is tested along its outline. The build tests no point inside an area. It resolves every outline point within 150 metres of a state line on the catalog dates. Where the simplified map puts an outline point on a zone of another state or territory, the build looks at each simplified span of a state border that holds a raw segment within the point's distance to the line plus 110 metres, keeps the raw vertex of that span nearest the point, simplifies again, and repeats until a pass keeps no new vertex. A point more than 110 metres from the line may stay on the wrong zone. The border between two districts of one state gets no such vertices, only those that fixtures keep. The build then fails, naming each feature, if any outline point within 110 metres of a state line still resolves to another state's zone. At this release the build kept 608 vertices for 14,909 features with 241,882 outline points within 110 metres of a state line. Its summary says `608 arc vertices kept for border features, 14909 OpenStreetMap border features (241882 outline points) within 110 m of a state line, 0 with a point on another state's zone`. Fixtures keep the line differently: every raw segment within 150 metres of a fixture keeps both its vertices.

Testing outlines rather than centres matters for long buildings. A terrace row in the Pelangi Heights estate, Mantin, is 12 to 17 metres inside Negeri Sembilan along its whole length; when only its centre was tested, a simplified line crossed it and put its east end on SGR01. Its outline now resolves to NGS03 at every point, and fixtures record the east ends of three such rows.

The size rule decided these numbers. Measured on the zones file with `GZipCodec(level: 9)`, as the build measures it, against the 60,000-byte limit:

| Setting | Gzipped bytes | Features with an outline point on another state's zone |
| --- | --- | --- |
| 100 m everywhere, no vertices kept for features | 55,952 | 1,145 |
| 80 m on differing borders, no vertices kept for features | 57,581 | 998 |
| 100 m everywhere, the nearest raw vertex kept for each moved point | 57,243 | 0 |
| 90 m on differing borders, the nearest raw vertex kept | 57,964 | 0 |
| 80 m on differing borders, the nearest raw vertex kept (shipped) | 58,829 | 0 |
| 75 m on differing borders, the nearest raw vertex kept | 59,328, less than 1,000 under the limit | 0 |
| 70 m on differing borders, the nearest raw vertex kept | 59,869, less than 1,000 under the limit | 0 |
| 100 m everywhere, every raw segment within 150 m of each moved point | 57,978 | 0 |
| 80 m on differing borders, every raw segment within 150 m of each moved point | 59,466, less than 1,000 under the limit | 0 |

The shipped setting is the tightest tolerance that leaves at least 1,000 bytes under the limit. Keeping every raw segment within 150 metres of each moved outline point, as fixtures do, would leave 534 bytes at 80 metres.

#### Land with no zone

`build` and `check` also look for places that resolve to no zone. Every grid point inside a geoBoundaries ADM2 district polygon and inside a state in the snapshot must resolve to a zone on every catalog date, so a deleted region, a hole in a region or a split rule with a gap fails; no row of any file exempts land. The centre of every feature in `openstreetmap-MYS-offmap-features.tsv.gz`, the features whose centre lies inside a state but more than 400 metres outside every district polygon, is resolved too. Their outlines are not, so a feature whose centre has a zone can have an outline that reaches land with none. Each such feature with no zone must be named by its OpenStreetMap id in a row of `no_zone_areas.csv` for the same state or territory, so removing an island area fails even where the places around it are named. The report groups the features with no zone into areas of features within about a kilometre of each other. `build` fails on an id in that file that is not such a feature, so the list stays current; `check` prints it. At this release no grid point on ADM2 land lacks a zone, and the 37 rows name all 2,142 features, in 230 areas; see [Known limits](#known-limits).

#### Special areas

`special_areas.csv` lists the island and highland zones as a centre, a radius and a parent district. A special area applies only to points that resolve to its parent district, so it never takes land from a neighbouring district. `build` makes each parent district its own region for this. It also samples each special area on a 100-metre grid and fails when a point that resolves to the special area's zone lies more than 500 metres inside another district of the same state. Across a state border, the state check decides.

SWK09, Zon Khas (Kampung Patarikan), has no special area. No map source, GeoNames or OpenStreetMap included, gives the position of Kampung Patarikan, so `lookup` never returns SWK09. Merapok and the Lawas villages around it resolve to SWK01, as the e-Solat wording for Lawas says. The villages across the Sabah border, such as Sindumin, resolve to SBH09. SWK09 stays in the catalog, and the times file keeps its timetable, so an app can offer it for manual selection.

#### Islands

The geoBoundaries ADM2 layer leaves out some islands that the ADM0 layer of the same release includes, and both layers leave out small islands such as Pulau Mabul. `islands.csv` adds each of these as an island area: an octagon with its corners at the given radius from the centre, added to the named district. A point inside the octagon resolves like a point in that district. The octagon may leave out part of a long or irregular island; see [Known limits](#known-limits).

- Each row's `source` column names the GeoNames island, the settlement on it, whether geoBoundaries ADM0 has a ring for it, and the nearest district.
- The district is the nearest ADM2 district unless a source says otherwise.
- `build` fails when an island area touches a district shape or another island area, so an island area never changes how a point on land resolves.

The list covers every GeoNames island and populated place (feature class P) that lies inside the unsimplified geoBoundaries ADM0 boundary and would otherwise resolve to no zone, and populated islands outside ADM0, such as Pulau Mabul. It does not cover every island that OpenStreetMap maps with buildings; [Land with no zone](#land-with-no-zone) lists those. An island that the snapshot gives to a state other than its nearest district's, such as Pulau Aceh, is a `districts.csv` row with an OpenStreetMap ring instead. To check a new release, list the GeoNames features inside ADM0, run each through `lookup`, and add an island area for each feature that returns `none`.

#### Fixtures

`town_fixtures.csv` lists every place named in the e-Solat zone descriptions with its GeoNames coordinates and expected zone, plus populated islands, populated places and buildings along the borders between states, and points on each side of the special-area and Putrajaya boundaries. Each expected zone follows the e-Solat description and the state the snapshot, with its exceptions, puts the place in; the two agree at every fixture. A fixture with an empty zone records a place that resolves to no zone, such as Layang-Layang. `build` and `test/malaysia_zone_fixtures_test.dart` both fail when a fixture resolves to another zone. Add a fixture before you change a rule.

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
2. Districts with the same ordered zone rows merge into one region, except that the parent district of a special area keeps its own region. The OpenStreetMap rings named in `districts.csv` are cut out of the shapes that cover them, every border between two states is stitched to the OpenStreetMap line, and island areas join their district.
3. A border between two districts of one region drops out. A point is inside a region when a ray from it crosses the region's arcs an odd number of times, so holes and islands need no special handling.
4. The remaining borders are cut into arcs at every junction. Each arc is stored once and shared by the regions on both sides.
5. Each arc between regions of two different states is the OpenStreetMap line (see [State borders](#state-borders)).
6. Each arc is simplified with Douglas-Peucker at 100 metres, or 80 metres on a state border between zones whose times differ by 2 minutes or more. It keeps its end points, every vertex of each raw segment within 150 metres of a fixture, and the raw vertices that keep the outline points of OpenStreetMap border features on their own state's zone (see [Simplification near state lines](#simplification-near-state-lines)).

`build` fails when a district has no row, a row names an unknown zone or an OpenStreetMap ring that does not exist, a rule is malformed, an OpenStreetMap ring of one state lies inside another state's shape without a row, a junction has no OpenStreetMap line within 5 kilometres, a fixture resolves to the wrong zone, a special area reaches more than 500 metres into another district of its state, an island area touches land or another island area, a point of a 0.02-degree grid falls in two regions, the state check finds an area on land, an outline point of an OpenStreetMap border feature within 110 metres of a state line resolves to another state's zone, land has no zone, a feature off the map has no zone and `no_zone_areas.csv` does not name it, an id in that file is not such a feature, an extract does not have its pinned SHA-256, a state line exception does not end on the line, or stitching the state borders makes two arcs cross.

## Known limits

Each limit below holds at this release, measured with the build's own lookups. A place that resolves to no zone gets no official times, and a caller falls back to calculated times.

- **Points between OpenStreetMap features near a state line.** Every outline point of every feature in the border extract within 110 metres of a state line resolves to its own state's zone, except that a `place=*` feature counts by its centre. Outline points lie at most 5 metres apart, so a stretch narrower than that, on an edge or inside, can resolve to the other side's zone, whether or not a building straddles the line. Apartment Seri Ceria 2 (way 1387194435, `landuse=residential`) does not touch the line, yet points on its edge and inside it, 5.1 to 6.9 metres inside Kuala Lumpur, resolve to SGR01 and SGRPTG. The RDA Banquet Hall (way 1073825250, `building=yes`) has a sliver 2.0 to 2.55 metres deep inside Kuala Lumpur, depending on the sampling, that resolves to SGR01 and SGRPTG. Both are at most 1 minute off. For 98 features of the extract the only wrong points lie within 0.59 metres of the line, where the rounding to 1e-5 degrees decides the side.
- **Inside areas.** The build tests no point inside an area feature, and tests a `place=*` area only at its centre. A `place=*` feature is kept in the extract only when its centre lies within 150 metres of a state line, so 133 place areas with an outline point within 110 metres of a state line are not in the extract, and 93 of them are named residential areas. They include the Pelangi Heights estate polygon itself (way 603550612), Presint 11 and 20 in Putrajaya, Kampung Alor Batu and Taman Wangsa Melawati. The table lists 25 areas in 24 rows: 21 home areas that have an outline point deeper than 1.2 metres on another state's zone, and four more whose wrong points lie in the interior (Taman Maluri, Asahan Sialang Relau, Seksyen 5 and Cheras). It gives the deepest wrong point on a 2-metre grid, or, for Taman Teknologi Malaysia, Bukit Fraser, Bandar Sri Damansara, Serdang Raya and the Putrajaya part of Perdana Lakeview East, marked with an asterisk, on the 5-metre outline and 10-metre interior sampling, and for Seksyen 5 and Cheras, which have no asterisk, on the 2-metre grid, the zone it resolves to, the zone it should resolve to, and the largest difference in a prayer time between the two across 2026 and 2027.

  | Area | Deepest wrong point | Resolves to | Should be | Largest difference |
  | --- | --- | --- | --- | --- |
  | Presint 11, Putrajaya (way 888199085) | 71.0 m | SGR01, SGRSPG | WLY01 | 1 minute |
  | Taman Wangsa Melawati, Kuala Lumpur (relation 14968650) | 65.0 m | SGR01, SGRGBK | WLY01 | 1 minute |
  | Unnamed residential area, Perak (way 214791937) | 62.8 m | KDH04 | PRK03 | Dhuha 16 minutes, Asar 5, the other times up to 4 |
  | Seksyen 5, Petaling Jaya, Selangor (relation 17056748, `place=quarter`) | 60.1 m | WLY01 | SGR01, SGRPTG | 1 minute |
  | Taman Meranti Lestari, Melaka (way 943354661) | 59.7 m | NGS02 | MLK01 | Syuruk and Dhuha 3 minutes, the other times up to 2 |
  | Taman Teknologi Malaysia, Kuala Lumpur (way 200888146, `place=neighbourhood` and `landuse=commercial`) | 59.4 m* | SGR01, SGRPTG | WLY01 | 1 minute |
  | Presint 20, Putrajaya (way 888188169) | 55.8 m | SGR01, SGRSPG | WLY01 | 1 minute |
  | Kampung Alor Batu, Pahang (way 1460190139, `place=village` and `landuse=residential`) | 55.6 m | TRG04 | PHG02 | 3 minutes, Zohor 1 |
  | Cheras, Kuala Lumpur and Selangor (relation 11277900, `place=suburb`) | 52.5 m in Kuala Lumpur, 24.0 m in Selangor | SGR01 and SGRHLG in Kuala Lumpur, WLY01 in Selangor | WLY01 in Kuala Lumpur, SGR01 and SGRHLG in Selangor | 2 minutes (1 in 2026) |
  | Bukit Fraser, Pahang (relation 21151112, `place=town`) | 51.8 m* in Pahang, 13.4 m in Selangor | SGR01 and SGRHSL in Pahang, PHG06 in Selangor | PHG06 in Pahang, SGR01 and SGRHSL in Selangor | Maghrib 8 minutes, Syuruk and Dhuha 7, the other times up to 3 |
  | Gombak Setia, Selangor (way 545244077) | 50.1 m in Selangor, 18.4 m in Kuala Lumpur | WLY01 in Selangor, SGR01 and SGRGBK in Kuala Lumpur | SGR01 and SGRGBK in Selangor, WLY01 in Kuala Lumpur | 1 minute |
  | Perdana Lakeview West, Selangor (relation 17292835) | 45.1 m | WLY01 | SGR01, SGRSPG | 1 minute |
  | Kampung Bukit Lanjan, Kuala Lumpur (way 705364483) | 34.2 m | SGR01, SGRPTG | WLY01 | 1 minute |
  | Perdana Lakeview East, Selangor and Putrajaya (way 295784276) | 34.1 m in Selangor, 20.3 m* in Putrajaya | WLY01 in Selangor, SGR01 and SGRSPG in Putrajaya | SGR01 and SGRSPG in Selangor, WLY01 in Putrajaya | 1 minute |
  | Unnamed residential area, Terengganu (way 693069743) | 25.2 m | PHG02 | TRG04 | 3 minutes, Zohor 1 |
  | Bandar Sri Damansara, Kuala Lumpur (relation 11989705, `place=suburb`) | 24.5 m* | SGR01, SGRPTG | WLY01 | 1 minute |
  | Taman Maluri, Kuala Lumpur (relation 17227843) | 20.1 m | SGR01, SGRHLG | WLY01 | 2 minutes (1 in 2026) |
  | Asahan Sialang Relau, Johor (way 646004909) | 17.6 m | MLK01 | JHR04 | Dhuha 6 minutes, the other times 3 |
  | Taman Seri Meranti, Negeri Sembilan (way 943354662) | 11.6 m | MLK01 | NGS02 | Syuruk and Dhuha 3 minutes, the other times up to 2 |
  | Cyber Heights Villa, Putrajaya (way 295652464) | 10.9 m in Putrajaya, 17.1 m in Selangor | SGR01 and SGRSPG in Putrajaya, WLY01 in Selangor | WLY01 in Putrajaya, SGR01 and SGRSPG in Selangor | 1 minute |
  | Bandar Kinrara 9 and Bandar Kinrara, Kuala Lumpur (relations 12858317 and 12773887) | 10.5 m | SGR01, SGRPTG | WLY01 | 1 minute |
  | Kampung Selayang Pandang, Selangor (relation 17342159) | 6.3 m | WLY01 | SGR01, SGRGBK | 1 minute |
  | Serdang Raya, Kuala Lumpur (way 1006950044, `place=suburb`) | 2.9 m* | SGR01, SGRPTG | WLY01 | 1 minute |
  | Unnamed residential area, Selangor (way 1478870084) | 2.6 m | WLY01 | SGR01, SGRGBK | 1 minute |

  Taman Teknologi Malaysia (tagged `place=neighbourhood` and `landuse=commercial`) is the Technology Park Malaysia site. It holds a student residence (way 199766626), two university campuses (Asia Pacific University, way 944352525, and the IMU University campus, ways 192611614, 192611616, 619939878 and 619995262), a school (Stellaire International, relation 17928110) and a mosque (MIMOS Mosque, way 201436644). Each of them resolves to WLY01, the right zone, 199 to 839 metres from the line. The wrong part lies in the south-west corner, near 3.0421, 101.6785. Two more residential polygons have wrong points no deeper than 2.4 metres: Taman Segar, Kuala Lumpur (relation 11310189, 2.3 m, SGR01 and SGRHLG) and an unnamed area in Pulau Pinang (way 639740555, 2.1 m, KDH05). Other place polygons also have wrong interiors, such as Presint 13 in Putrajaya (way 888199089, up to 52.6 m on a 10-metre grid).

  Asahan Sialang Relau is in the extract, but the test reaches only its outline. No mapped home, school, stay or place of worship lies in any of these wrong parts. The school, mosque and clinic of Kampung Alor Batu (ways 1459983396, 1460177060, 1460177061 and 1460404879) and SJK (C) Chung Hwa Asahan resolve to their own side at every point. Whether unmapped homes stand in the wrong parts is not known.
- **Unmapped land at Fraser's Hill.** Unmapped land on the Pahang side resolves to SGR01 and SGRHSL (Hulu Selangor from 2027): 63.5 metres inside Pahang near 3.7107, 101.7122 and 51.3 metres near 3.7047, 101.7381. Maghrib comes up to 8 minutes before PHG06's. The points include the inside of the town relation Bukit Fraser (relation 21151112), 51.8 metres deep on a 10-metre grid. No mapped building, school, stay or place of worship lies in or within 20 metres of these parts.
- **River and sea islets.** A `place=islet` way is tested at its centre, which resolves correctly, while its outline can lie on the other side's zone. Ten islets have outline points deeper than 1.2 metres on the other side's zone. The deepest such point of each, on the outline sampling, is 7.3 metres for way 900617660 and 3.3 metres for way 900617661, both unnamed on the Kedah and Perak line in Sungai Kerian, inside Perak on KDH05, which differs from PRK06 by up to 14 minutes in Dhuha and 5 in Asar; 48.1 metres for unnamed way 899781730 in Perak, on KDH05; 31.1 metres for unnamed way 899750398 in Kedah and 22.4 and 21.4 metres for unnamed ways 899740423 and 900598187 in Kedah, all three on PRK06; 7.4 and 2.4 metres for unnamed ways 900653973 and 899740422 in Kedah, both on PRK06; 2.2 metres for unnamed way 901016740 in Perak, on KDH05; and 31.8 metres for Pulau Trus in Melaka (way 724774980), on JHR04, which differs from MLK01 by 3 minutes and by 6 in Dhuha in 2027. Pulau Trus is not in the extract, because its centre lies 155.7 metres from the line, so the build never tests it. No mapped building lies within 20 metres of a wrong part of any of them.
- **Features outside the extract's classes.** A point that OpenStreetMap does not map, or maps outside the extract's classes, is protected only by the 80-metre tolerance (100 metres on the Kuala Lumpur and Putrajaya lines where the zones differ by at most 1 minute). Measured on 230,232 points every 150 metres along every border in the snapshot, at 40, 100, 200, 400, 800 and 1,600 metres on each side, 3,091 points inside a district polygon resolve to a zone of another state or territory; the deepest lies 71.4 metres inside its territory. Another 184 points are sea that only the snap reaches. A different set of 228,756 points on the same plan finds 3,049 and a deepest point of 72.9 metres, so the deepest point depends on the sample. Of the 40,024 OpenStreetMap buildings, places, amenities, shops, offices and other points of interest in the pinned Geofabrik extract that lie within 150 metres of a state line, 38 resolve to another state's zone when each is tested at one point. They are lines and markers drawn on the boundary, viewpoints, shelters and information boards on hilltops, one building whose centre lies 0.5 metres from the line, and a fuel station, a cafe and a payment kiosk 6 to 20 metres inside Kuala Lumpur at Kepong, which resolve to SGRPTG, at most 1 minute off. That count is one point per feature. Tested at every outline point, 604 of 30,110 features within 150 metres, in a filter of the same file with wider classes, have a wrong point deeper than 1.2 metres, the rounding of the map. 469 of them are lines such as roads, rivers and rails. The homes, schools, stays and places of worship among them are 21 area polygons, all in the table under Inside areas. Roads and water are not checked by the build: near the Kesang estuary between Johor and Melaka, six unnamed features that are not buildings or places resolve to the other state's zone, 6 minutes off, and points on Jalan Melaka - Masjid Tanah - Lubok Cina and Jalan Sepang Lukut resolve 3 and 4 minutes off.
- **The Kuala Lumpur and Putrajaya lines.** Of those 3,091 points, 99 lie on the Kuala Lumpur and Putrajaya lines and swap WLY01 for SGR01, SGRGBK, SGRPTG or SGRSPG, which differ by at most 1 minute on any day. Six more, on the Cheras and Ampang stretch, resolve to SGR01 and SGRHLG inside Kuala Lumpur, three of them 0.1 to 0.6 metres from the line; SGRHLG differs from WLY01 by 2 minutes on 221 days of 2027.
- **The state check's grid.** The state check samples a 0.001-degree grid, about 110 metres, so a wrong area narrower than the grid can fall between its points; the outline test covers only the outlines of mapped features, every 5 metres. Areas that only the snap reaches are reported, not failed, and the check does not test them against a coastline.
- **Disputed places.** The map follows the snapshot and the e-Solat wording, but other sources disagree about these places:
  - Fraser's Hill, Selangor side: SJK(C) Bukit Fraser, Sri Berkat Rest House, Methodist Bungalow, Kingswood Bungalow and two bungalows 22 and 51 metres inside Selangor (OpenStreetMap ways 713091688 and 711938028) resolve to the Hulu Selangor zone (SGR01, SGRHSL from 2027), because the snapshot puts them in Selangor. e-Solat names Bukit Fraser under PHG06, and the hill uses Pahang addresses. Their Maghrib is up to 8 minutes before PHG06's. Which timetable the Selangor side of the hill follows is a question for JAKIM and the Selangor mufti.
  - Pulau Terus (MLK01), Pos Penangau (KTN02), Broga (NGS03), the Villea Port Dickson hotel (MLK01, with a Port Dickson postal address) and the Genting Ria buildings (Hulu Selangor zone): GeoNames, postal addresses or ADM2 disagree with the snapshot.
  - Tanjung Biru Condominium, 73 metres inside Negeri Sembilan by the snapshot, resolves to NGS03; addresses inside the Tanjung Tuan exclave also say Port Dickson.
  - Pulau Seri Buat and Pulau Sembilang return PHG07. The snapshot puts them in Pahang, as does the e-Solat wording for Rompin, but PHG01 names only Pulau Tioman, so PHG01 is arguable for them.
  - The Perak and Kedah tripoint north of Pengkalan Hulu (6.5 km2, PRK03) and the Perlis tripoint (3.5 km2, PLS01) follow the snapshot; ADM2 says Kedah. Neither holds a populated place.
  - Kepong Sentral Condominium (way 1073854740) straddles the Gombak and Petaling border, and the OpenStreetMap relation of Gombak (relation 12438352) holds it. In 2026 all 3,289 of its outline and interior samples resolve to SGR01. In 2027, 1,187 resolve to SGRGBK and 2,102 to SGRPTG. The two differ by at most 1 minute. The border between two districts of one state gets no vertices for mapped features, so building points near it can fall on the neighbouring district's zone. At Kepong, in 2027, 116 of the 182 outline points of the apartment block of Kepong Sentral Condominium (way 807113506) lie in the OpenStreetMap Gombak relation and resolve to SGRPTG. On the stored ADM2 Gombak polygon as the build reads it, rounded to 1e-5 degrees, none of them lies inside it, and none of another building's (way 1289557054) does either.
  - Section 16, Petaling Jaya: the Lorong 16/2A houses inside the bend of Jalan 16/2 resolve to WLY01, as their 59100 postcode, the snapshot and the OpenStreetMap place area "Seksyen 16 (Kuala Lumpur)" say, although the ADM2 Petaling shape covers them. Jalan 16/2 Nos. 32 to 82, further north, carry the Petaling Jaya postcode 46350 but resolve to WLY01, because the snapshot and ADM2 both put them in Kuala Lumpur. Jalan 16/4 No. 1 (way 359487670) carries 46350 and ADM2 Petaling covers it, but the snapshot puts it 148 metres inside Kuala Lumpur, 139.7 metres from the path, so it stays on WLY01. The path moves 4.3 percent of the samples of the KK9 residential college grounds (relation 17087779, postcode 50603 Kuala Lumpur) into Selangor, and no building there.
  - The Sri Malai Vinayagar Temple resolves to the Selangor zone along its whole outline, because the snapshot puts it 15 metres inside Selangor; the ADM2 line puts it 22 metres inside Kuala Lumpur.
  - SMK Tunku Besar, SMK Petaling and Surau Juma'at Al Mustaqimah resolve by the snapshot, although their postcodes (73000, 46000 and 56100) belong to the state on the other side.
- **Places with no zone.** 2,142 OpenStreetMap features in 230 areas inside the snapshot's states lie more than 500 metres outside every district polygon and island area and resolve to no zone. `no_zone_areas.csv` names each by id, in 37 rows. The largest are the Semporna and Tawau islands in Sabah (1,346 features, among them the villages of Pulau Omadal with its school, Pulau Danawan and Pulau Nusa Tengah, and the Kapalai and Pom Pom dive resorts), the Kudat and Banggi islands (273), the Port Dickson coast (88), the Johor east coast islands (78), the Langkawi islets and Pulau Payar (54), the Sandakan Turtle Islands (41), the Manjung coast in Perak with the Sultan Azlan Shah power station (39), the Tanjung Pengelih ferry terminal and the islands off Pengerang (34), and the Penang coast with the reclaimed land at Seri Tanjung Pinang and nearby islets (25). Among them are a hospital node on South Mangsee Island (node 8927074517), which belongs to the Philippines but lies inside the OpenStreetMap Sabah relation at sea, an unnamed clinic on the Manjung coast (node 12045080246) and the Doris Mataking resort on Pulau Mataking, Semporna (node 14295898900). The Johor east coast row also holds three features on the mainland, not on an island: a mosque (way 1388820827) and two chalet sites (ways 1551475934 and 1551475938) at Teluk Gorek, Mersing. About 0.6 square kilometres of that headland lie more than 500 metres outside the Mersing shape. The Geofabrik extract stops short of the Spratly reefs, so the check cannot see Layang-Layang (Swallow Reef), whose dive resort and airstrip lie inside the snapshot's Sabah ring and resolve to no zone; a fixture records it. No grid point on ADM2 land lacks a zone, but about 112 square kilometres of land that the snapshot puts in Malaysia, along the national border, lies more than 500 metres outside every district polygon and resolves to no zone, as does the Teluk Gorek headland.
- **Partly covered islands.** Island areas are octagons, not island outlines. They cover the whole geoBoundaries ADM0 ring of 14 of the 21 islands that have one, and 95 to 99 percent of Pulau Kaniogan, Pulau Kukup and Pulau Sulok. Pulau Langgun, Pulau Sedam, Pulau Tanjung Dendang, and the ring that holds Pulau Puru Puru and Tanjong Nuig are only partly covered, because a larger octagon would touch a district or another island area. On a 50-metre grid, 26 of 2,755 points on Pulau Langgun, 139 of 549 on Pulau Tanjung Dendang and 153 of 723 on the Pulau Puru Puru ring resolve to no zone. Island districts come from the nearest district rather than an official list.
- **The snap at sea.** The 500-metre snap reaches points outside every district polygon, which is sea or foreign land as the ADM2 layer draws it. At sea it can cross a state's maritime line: around the Tanjung Tuan exclave (2.44 km2 of sea that the snapshot gives to Negeri Sembilan resolves to MLK01), off Sungai Sepang (0.12 km2, SGR01 and SGRSPG in Negeri Sembilan's water), off Pulau Aceh (0.07 km2, PHG07 in Johor's water) and at the Linggi estuary (0.01 km2). The build summary and `check` report these four areas.
- **Past the national border.** The coastline and the national border are the ADM2 line. Points outside Malaysia near its land borders can resolve to a Malaysian zone, because the ADM2 district shapes run past the geoBoundaries ADM0 national border, and a point outside every district within 500 metres of one resolves to that district. The farthest such points lie 3.0 kilometres into Brunei, 2.9 into Indonesia, 2.9 into Singapore (across the Johor Strait) and 1.0 into Thailand; [Notes for the public API](#notes-for-the-public-api) gives the areas.
- **Split rules.** The split rules for Gua Musang, Rompin, Hulu Perak, Kinabatangan, Lahad Datu, Subis, Matu and Pusa are latitude or longitude lines drawn between the places the e-Solat wording names. No mukim polygon exists to check them, so each line is right at the named places but unproven between them, and land far from every named place can fall on the wrong side. Gua Musang's KTN01 side alone covers about 3,100 square kilometres.
- **Sabah 2027.** `lookup` returns the Sabah zones for 2027, but Sabah has no 2027 timetable yet. A caller must check that the times file holds the zone and year before it uses official times.

## Notes for the public API

These notes are for anyone who builds a public API on the decoder and resolver in `lib/src/data/`.

- The resolver answers for any point and does not know the country. Points outside Malaysia near its borders, on land or across the Johor Strait, can resolve to a Malaysian zone. A caller must check that the user is in Malaysia, for example from the platform's reverse geocoder, before it uses official times.
- The reach past each border, measured on a 100-metre grid of foreign land within 8 kilometres of the geoBoundaries ADM0 border of Malaysia, on 1 June 2026 and 1 June 2027:

  | Country | Farthest point that resolves | Zone | Distance past the border | Foreign land that resolves, within 3 km |
  | --- | --- | --- | --- | --- |
  | Brunei | 4.89474, 115.05230 | SWK01 | 3.0 km | 219 km2 |
  | Indonesia | 1.20936, 110.03502 | SWK08 | 2.9 km | 1,084 km2 |
  | Singapore | 1.43623, 104.02910 | JHR02 | 2.9 km | 1.24 km2 |
  | Thailand | 5.74876, 101.24499 | PRK03 | 1.0 km | 254 km2 |

  The Philippines has no land within 8 kilometres. In Singapore no district shape covers land; the points lie within 500 metres of the Johor shape in the strait.
- `zoneAt` returns null for a point that no district region contains and that lies more than 500 metres from every region boundary: the open sea, most foreign land, and the places that [Known limits](#known-limits) lists with no zone. A caller then falls back to calculated times.
- The resolver returns Sabah zones for 2027, but Sabah has no 2027 timetable yet. A caller must check that the times file holds the zone and year.
- The resolver never returns SWK09, because no source locates Kampung Patarikan. Offer it for manual selection.

## Manifest format

`data/malaysia/MANIFEST` is tab-separated, with a header row and one row per output file and per source.

| Column | Content |
| --- | --- |
| `kind` | `output` for a generated file. For a source: `esolat`, `selangor-pdf`, `selangor-text`, `geoboundaries`, `geofabrik` or `openstreetmap` |
| `name` | The output file name, the zone and year, the geoBoundaries layer and release, the Geofabrik extract and the time of its data, or the OpenStreetMap layer and its date |
| `retrieved` | The date the source was retrieved. For e-Solat it is the date of the response's `serverTime`; for OpenStreetMap it is the pinned date, or for the features filtered from the Geofabrik extract the date of its data. Empty for an output |
| `method` | The HTTP method that retrieves the source: `POST` for e-Solat and the OpenStreetMap snapshot, `GET` for a Selangor PDF, a geoBoundaries file or the Geofabrik extract. `osmium` for the OpenStreetMap features that `import-osm-extract` filters from the Geofabrik extract. Empty for an output and for `selangor-text` |
| `url` | The request URL. For `selangor-text` it is the path of the committed text in this repository |
| `form` | The form fields a `POST` sends as `application/x-www-form-urlencoded`. For the OpenStreetMap snapshot it is the Overpass query with its pinned date; for the OpenStreetMap features it is the `osmium tags-filter` expression. Empty for every other row |
| `sha256` | The SHA-256 of the file, as described below |

Each hash covers decompressed bytes. For `esolat`, `geoboundaries` and `openstreetmap` it is the response body as downloaded, which is the decompressed content of the gzipped file under `tool/malaysia/raw/`. For `selangor-pdf` and `geofabrik` it is the file as downloaded. For the OpenStreetMap features it is the decompressed content of their gzipped file under `tool/malaysia/raw/`. For `selangor-text` it is the decompressed `pdftotext` output. For `output` it is the file in `data/malaysia/`.

To repeat an e-Solat request, send the form fields to the URL, for example `curl -X POST -d 'datestart=2026-01-01&dateend=2026-12-31' 'https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration&zone=WLY01'`. A new response carries a new `serverTime`, so its hash differs even when its `prayerTime` rows are the same.

## Yearly update

Run this in the fourth quarter, so a release ships before 1 January.

1. Run `fetch <next year>`. For each zone that returns `NO_RECORD!`, add the year to the zone's `unpublished` column in `zones.csv`. Those zones fall back to calculated times for that year.
2. If the Selangor Mufti publishes district PDFs for the next year, download them, add their rows to `selangor_sources.csv`, and run `import-selangor`.
3. Run `build`. Read every rejected row. Add a correction only for a clear printing error with corroboration, and a waiver for a plausible step. Draft a report to JAKIM for both.
4. Run `dart test`.
5. Commit the raw files, the CSVs and the generated files together, and release.
6. Copy `malaysia_times.txt`, `malaysia_zones.txt`, `MANIFEST` and `LICENSE-ODbL.md` into the other language versions, run their hash check, and carry the credits of [Licences](#licences) into their readme.

Until JAKIM publishes the Sabah 2027 timetable, run `fetch 2027` weekly. When the Sabah rows arrive, remove `2027` from the `unpublished` column of each Sabah zone, rebuild and release.

## Licences

The zone map is a database derived from OpenStreetMap, so it is offered under the Open Database License 1.0, as [data/malaysia/LICENSE-ODbL.md](../data/malaysia/LICENSE-ODbL.md) states. That file names every file that holds OpenStreetMap-derived data:

- `data/malaysia/malaysia_zones.txt` and `lib/src/data/malaysia_zones_data.dart`, the zone map
- `tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz`, the snapshot of the state boundaries, 2026-11-04T00:00:00Z
- `tool/malaysia/raw/openstreetmap-MYS-border-features.tsv.gz` and `tool/malaysia/raw/openstreetmap-MYS-offmap-features.tsv.gz`, the features and their outlines filtered from the Geofabrik extract of 2026-11-03T21:24:23Z
- `tool/malaysia/islands.csv`, whose 20 island centres from geoBoundaries ADM0 come from a 2017 OpenStreetMap export
- `tool/malaysia/town_fixtures.csv`, which holds coordinates of OpenStreetMap features
- `tool/malaysia/state_line_exceptions.csv`, whose path ends lie on the OpenStreetMap line
- `tool/malaysia/no_zone_areas.csv`, which names OpenStreetMap features by id

The state borders, the Putrajaya ring, the Tanjung Tuan exclave and Pulau Aceh come from the snapshot, © OpenStreetMap contributors. The district polygons inside each state are from geoBoundaries gbOpen MYS ADM2 (sources geoBoundaries and citypopulation.de, CC BY 3.0). The centres of the 11 special areas, of the other 17 islands, of the zone reference points and of most fixtures are from GeoNames (CC BY 4.0). The timetables are published by JAKIM and the Selangor State Mufti Department. The library code is MIT, in `LICENSE`. These are licence facts, not legal advice.

A port to another language version copies the three data files with `LICENSE-ODbL.md` and puts this credit in its readme:

> State boundaries © OpenStreetMap contributors, Open Database License 1.0 (https://opendatacommons.org/licenses/odbl/1-0/). District boundaries from geoBoundaries gbOpen MYS ADM2 (sources: geoBoundaries, citypopulation.de), CC BY 3.0; Runfola, D. et al. (2020) geoBoundaries: A global database of political administrative boundaries. PLoS ONE 15(4): e0231866, https://doi.org/10.1371/journal.pone.0231866. Place coordinates from GeoNames, CC BY 4.0. The zone map file is offered under the Open Database License 1.0.
