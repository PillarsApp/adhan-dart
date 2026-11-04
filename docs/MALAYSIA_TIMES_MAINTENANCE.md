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
| `data/malaysia/LICENSE-ODbL.md` | The licence of the zone map and of the OpenStreetMap snapshot it is built from. See [Licences](#licences) |

The two Dart constants hold the same bytes as the text files. Other language versions copy the text files, `MANIFEST` and `LICENSE-ODbL.md`, check the hashes, and carry the credits in [Licences](#licences).

## Files

| Path | Purpose |
| --- | --- |
| `tool/malaysia/malaysia_times_cli.dart` | The `fetch`, `import-selangor`, `fetch-osm`, `build`, `check` and `lookup` commands |
| `tool/malaysia/src/malaysia_timetables.dart` | Fetching, parsing, validation and correction of the timetables |
| `tool/malaysia/src/malaysia_zones.dart` | The zone catalog, district rules, polygon simplification and arc encoding |
| `tool/malaysia/src/osm_snapshot.dart` | The pinned OpenStreetMap snapshot: the Overpass query, the ring assembly and the state lookups |
| `tool/malaysia/src/osm_fetch.dart` | `fetch-osm`, which downloads the snapshot for its pinned date |
| `tool/malaysia/src/stitch_borders.dart` | Replacing every border between two states with the OpenStreetMap line, and cutting the OpenStreetMap rings named in `districts.csv` out of the district that covers them |
| `tool/malaysia/src/malaysia_states.dart` | The state check: the shipped map against the full-resolution snapshot |
| `tool/malaysia/src/geometry.dart` | Point, segment and ring arithmetic shared by the modules above |
| `tool/malaysia/src/gzip_input.dart` | Reading a stored gzip file and rejecting an empty, truncated or corrupt one |
| `lib/src/data/malaysia_times_codec.dart` | Encoder and decoder for the times file |
| `lib/src/data/malaysia_zone_map.dart` | Decoder and point-to-zone resolver for the zones file |
| `tool/malaysia/raw/esolat/` | Each e-Solat response, gzipped, exactly as fetched |
| `tool/malaysia/raw/selangor/` | The `pdftotext -layout` text of each Selangor PDF, gzipped |
| `tool/malaysia/raw/geoBoundaries-MYS-ADM2_simplified.geojson.gz` | The district polygons, gzipped, exactly as downloaded |
| `tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz` | The Overpass response with Malaysia's 16 `admin_level=4` relations, gzipped, exactly as downloaded. It gives every border between states, the Putrajaya ring, the Tanjung Tuan exclave and Pulau Aceh |
| `tool/malaysia/selangor_sources.csv` | Each Selangor PDF's zone code, URL, retrieval date and SHA-256 |
| `tool/malaysia/corrections.csv` | Reviewed corrections and waivers |
| `tool/malaysia/zones.csv` | The zone catalog |
| `tool/malaysia/districts.csv` | The zone of each district, with split rules; a row's shape is a geoBoundaries ADM2 `shapeID` or an OpenStreetMap ring |
| `tool/malaysia/special_areas.csv` | Island and highland zones as a centre, a radius and a parent district |
| `tool/malaysia/islands.csv` | Islands that geoBoundaries ADM2 leaves out, as a centre, a radius and a district |
| `tool/malaysia/town_fixtures.csv` | Every place named in the zone descriptions, with its expected zone, plus the places checked on each border |

The Selangor PDFs are not committed because they total 182 MB. Their URLs and SHA-256 hashes are in `selangor_sources.csv` and `MANIFEST`.

## Commands

Run every command from the repository root.

```bash
dart run tool/malaysia/malaysia_times_cli.dart fetch 2028
dart run tool/malaysia/malaysia_times_cli.dart import-selangor ~/Downloads/selangor-2028/*.pdf
dart run tool/malaysia/malaysia_times_cli.dart fetch-osm
dart run tool/malaysia/malaysia_times_cli.dart build
dart run tool/malaysia/malaysia_times_cli.dart check data/malaysia/malaysia_zones.txt
dart run tool/malaysia/malaysia_times_cli.dart lookup 3.1390 101.6869 2027-01-01
```

- `fetch <year>...` posts `datestart` and `dateend` to `https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration&zone=<code>` for every `e-solat` zone that `zones.csv` has in force during the year, and stores each response that holds rows. It keeps a zone and year that already holds rows unless you pass `--refresh`. It stores nothing for a `NO_RECORD!` response. It exits 1, naming the zone and year, when a response is unusable (not JSON, not a JSON object, or without rows for another reason), when a request fails three times, when `--refresh` gets no rows for a zone and year that already holds rows, or when a stored file is not gzip. In each of those cases it keeps the stored response.
- `import-selangor <pdf>...` runs `pdftotext -layout` (Poppler) on each PDF, checks that it holds every day of the year, stores the text, and records the PDF's SHA-256.
- `fetch-osm` posts the Overpass query in `tool/malaysia/src/osm_snapshot.dart` to the Overpass API and stores the response as `tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz`. The query carries the pinned date (`osmSnapshotDate`), so a rerun returns the boundaries as they stood at that moment; only the response header, which names the server's current database time, differs, so compare the `elements` array rather than the whole file. The public servers are often at capacity, so the command tries three servers in three rounds with growing pauses and exits 1 if none answers. To move to a newer snapshot, change `osmSnapshotDate`, run `fetch-osm`, then `build`, and read every fixture and check result.
- `build` validates, corrects and encodes everything. It prints every rejected row and exits 1 without writing anything when a row is rejected, an output is over budget, a stored raw file is empty, truncated, corrupt or not gzip (it names the file, and for a timetable the zone and year), a geoBoundaries or OpenStreetMap file is not the JSON the build expects (it names the file), the timetables do not match the catalog (see [Catalog](#catalog)), or a zone check fails (see [Zones format](#zones-format)). On success it prints a summary such as `117 zone-years, 0 rejected, 8 corrected, 24 waived` and the size of each output.
- `check <zones file>` runs the state check of [State borders](#state-borders) on any zones file, for example an older release or a copy another language version carries, prints every area, and exits 1 when an area on land fails.
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

Inside a state the geoBoundaries ADM2 district shapes decide the zone. Between states the OpenStreetMap snapshot decides. `build` stitches the two sources together:

1. Every run of a district's ring that it shares with a district of another state is an inter-state run. Its ends are junctions.
2. Each junction is moved onto the OpenStreetMap line. Where a district border inside a state meets the junction, that border is extended straight to the line, or cut where it already crosses the line, so the border inside the state keeps its own course and only its last metres move. Where three states meet, the junction moves to the point where the three OpenStreetMap relations meet. Where a border reaches the coast or the national border, the junction moves to the point where the OpenStreetMap line crosses the district's coast, or to the end of the OpenStreetMap line between the two states; the coast between the old junction and the new one changes district. If a straight connector from the old junction to that end would pass through either state, the connector starts further along the coast, at the first point from which the straight line stays outside both states.
3. Each inter-state run is replaced by the OpenStreetMap line between its two moved junctions.

So a state border moves no district border inside a state except at its last segment, which is what went wrong at Taman Sri Ehsan when an earlier build moved the Gombak and Petaling border onto the state line. The shipped coastline and national border stay the ADM2 line, so what counts as land, and how far a zone reaches past the national border, is unchanged from earlier releases.

`build` then measures the shipped map against the full-resolution snapshot. It resolves every point of a 0.001-degree grid (about 110 metres) that lies inside a state in the snapshot, on every date where a zone in `zones.csv` starts or ends (now 31 December 2026 and 1 January 2027), and groups the points that lie more than 110 metres inside a state but resolve to a zone of another state into areas. The 110 metres are the 100-metre simplification of the shipped arcs plus the rounding to 1e-5 degrees, so a point deeper than that can only be on the wrong side through an error in the data, never through the simplification. The check reads the snapshot, not the shipped arcs, so simplifying or editing the arcs cannot hide an error from it. `build` fails on every area on land, naming its zones, the two states, its size, its deepest point and its bounding box. An area whose points all lie outside every district polygon, so that only the 500-metre snap reaches them, is reported in the summary but does not fail the build; at this release those are four areas of sea, 2.64 km2 in all, where the snap crosses a state's maritime line (see [Known limitations](#known-limitations)). `check` runs the same measurement on any zones file. There is no list of exceptions: no source was found that says the snapshot is wrong anywhere, so the map follows it everywhere.

The simplification keeps every arc vertex within 150 metres of a fixture, so a named place close to a border resolves as the full-resolution line says. `build` also fails when the stitching makes two arcs cross where the district polygons did not cross before.

#### Special areas

`special_areas.csv` lists the island and highland zones as a centre, a radius and a parent district. A special area applies only to points that resolve to its parent district, so it never takes land from a neighbouring district. `build` makes each parent district its own region for this. It also samples each special area on a 100-metre grid and fails when a point that resolves to the special area's zone lies more than 500 metres inside another district of the same state. Across a state border, the state check decides.

SWK09, Zon Khas (Kampung Patarikan), has no special area. No map source, GeoNames or OpenStreetMap included, gives the position of Kampung Patarikan, so `lookup` never returns SWK09. Merapok and the Lawas villages around it resolve to SWK01, as the e-Solat wording for Lawas says. The villages across the Sabah border, such as Sindumin, resolve to SBH09. SWK09 stays in the catalog, and the times file keeps its timetable, so an app can offer it for manual selection.

#### Islands

The geoBoundaries ADM2 layer leaves out some islands that the ADM0 layer of the same release includes, and both layers leave out small islands such as Pulau Mabul. `islands.csv` adds each of these as an island area: an octagon with its corners at the given radius from the centre, added to the named district. A point inside the octagon resolves like a point in that district. The octagon may leave out part of a long or irregular island; see [Known limitations](#known-limitations).

- Each row's `source` column names the GeoNames island, the settlement on it, whether geoBoundaries ADM0 has a ring for it, and the nearest district.
- The district is the nearest ADM2 district unless a source says otherwise.
- `build` fails when an island area touches a district shape or another island area, so an island area never changes how a point on land resolves.

The list covers every GeoNames island and populated place (feature class P) that lies inside the unsimplified geoBoundaries ADM0 boundary and would otherwise resolve to no zone, and populated islands outside ADM0, such as Pulau Mabul. An island that the snapshot gives to a state other than its nearest district's, such as Pulau Aceh, is a `districts.csv` row with an OpenStreetMap ring instead. To check a new release, list the GeoNames features inside ADM0, run each through `lookup`, and add an island area for each feature that returns `none`.

#### Fixtures

`town_fixtures.csv` lists every place named in the e-Solat zone descriptions with its GeoNames coordinates and expected zone, plus populated islands, populated places and buildings along the borders between states, and points on each side of the special-area and Putrajaya boundaries. Each expected zone follows the e-Solat description and the state the snapshot puts the place in; the two agree at every fixture. `build` and `test/malaysia_zone_fixtures_test.dart` both fail when a fixture resolves to another zone. Add a fixture before you change a rule.

#### Known limitations

- The split rules for Gua Musang, Rompin, Hulu Perak, Kinabatangan, Lahad Datu, Subis, Matu and Pusa are latitude or longitude lines drawn between the places the e-Solat wording names. No mukim polygon exists to check them, so each line is right at the named places but unproven between them, and land far from every named place can fall on the wrong side. Gua Musang's KTN01 side alone covers about 3,100 square kilometres.
- Within 110 metres of a state border the simplified arc can put a point on the other side. Measured on 230,232 points every 150 metres along every border in the snapshot, at 40, 100, 200, 400, 800 and 1,600 metres on each side, 4,909 points resolve to a zone of another state at this release, against 32,262 and 23,852 at the two releases before. 4,669 of them lie within 50 metres of the snapshot's line and all within 110 metres. No point on land deeper than 110 metres does.
- The 500-metre snap reaches points outside every district polygon, which is sea or foreign land as the ADM2 layer draws it. At sea it can cross a state's maritime line: around the Tanjung Tuan exclave (2.44 km2 of sea that the snapshot gives to Negeri Sembilan resolves to MLK01), off Sungai Sepang (0.12 km2, SGR01 and SGRSPG in Negeri Sembilan's water), off Pulau Aceh (0.07 km2, PHG07 in Johor's water) and at the Linggi estuary (0.01 km2). The build summary and `check` report these four areas.
- The coastline and the national border stay the ADM2 line. Where that line runs inland of the snapshot's, a strip of land that the snapshot calls Malaysian is outside every district polygon and resolves only through the snap. Points outside Malaysia near its borders can resolve to a Malaysian zone, because the ADM2 district shapes run past the geoBoundaries ADM0 national border by up to about 2.7 kilometres, and a point outside every district within 500 metres of one resolves to that district. See [Notes for the public API](#notes-for-the-public-api) for the measured reach past each border.
- Pulau Seri Buat and Pulau Sembilang return PHG07. The snapshot puts them in Pahang, as does the e-Solat wording for Rompin, but PHG01 names only Pulau Tioman, so PHG01 is arguable for them.
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
2. Districts with the same ordered zone rows merge into one region, except that the parent district of a special area keeps its own region. The OpenStreetMap rings named in `districts.csv` are cut out of the shapes that cover them, every border between two states is stitched to the OpenStreetMap line, and island areas join their district.
3. A border between two districts of one region drops out. A point is inside a region when a ray from it crosses the region's arcs an odd number of times, so holes and islands need no special handling.
4. The remaining borders are cut into arcs at every junction. Each arc is stored once and shared by the regions on both sides.
5. Each arc between regions of two different states is the OpenStreetMap line (see [State borders](#state-borders)).
6. Each arc is simplified with Douglas-Peucker at 100 metres, keeping its end points and every vertex within 150 metres of a fixture.

`build` fails when a district has no row, a row names an unknown zone or an OpenStreetMap ring that does not exist, a rule is malformed, an OpenStreetMap ring of one state lies inside another state's shape without a row, a junction has no OpenStreetMap line within 5 kilometres, a fixture resolves to the wrong zone, a special area reaches more than 500 metres into another district of its state, an island area touches land or another island area, a point of a 0.02-degree grid falls in two regions, the state check finds an area on land, or stitching the state borders makes two arcs cross.

## Notes for the public API

These notes are for anyone who builds a public API on the decoder and resolver in `lib/src/data/`.

- The resolver answers for any point and does not know the country. Points outside Malaysia near its borders, on land or across the Johor Strait, can resolve to a Malaysian zone. A caller must check that the user is in Malaysia, for example from the platform's reverse geocoder, before it uses official times.
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
| `kind` | `output` for a generated file. For a source: `esolat`, `selangor-pdf`, `selangor-text`, `geoboundaries` or `openstreetmap` |
| `name` | The output file name, the zone and year, the geoBoundaries layer and release, or the OpenStreetMap layer and pinned date |
| `retrieved` | The date the source was retrieved. For e-Solat it is the date of the response's `serverTime`; for OpenStreetMap it is the pinned date. Empty for an output |
| `method` | The HTTP method that retrieves the source: `POST` for e-Solat and OpenStreetMap, `GET` for a Selangor PDF or a geoBoundaries file. Empty for an output and for `selangor-text` |
| `url` | The request URL. For `selangor-text` it is the path of the committed text in this repository |
| `form` | The form fields a `POST` sends as `application/x-www-form-urlencoded`. For OpenStreetMap it is the Overpass query with its pinned date. Empty for every other row |
| `sha256` | The SHA-256 of the file, as described below |

Each hash covers decompressed bytes. For `esolat`, `geoboundaries` and `openstreetmap` it is the response body as downloaded, which is the decompressed content of the gzipped file under `tool/malaysia/raw/`. For `selangor-pdf` it is the PDF as downloaded. For `selangor-text` it is the decompressed `pdftotext` output. For `output` it is the file in `data/malaysia/`.

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

The zone map is a database derived from OpenStreetMap, so it is offered under the Open Database License 1.0, as [data/malaysia/LICENSE-ODbL.md](../data/malaysia/LICENSE-ODbL.md) states. That file names the ODbL files: `data/malaysia/malaysia_zones.txt`, `lib/src/data/malaysia_zones_data.dart`, `tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz` and `tool/malaysia/islands.csv`. The state borders, the Putrajaya ring, the Tanjung Tuan exclave and Pulau Aceh come from the snapshot of 2026-11-04T00:00:00Z, © OpenStreetMap contributors. The district polygons inside each state are from geoBoundaries gbOpen MYS ADM2 (sources geoBoundaries and citypopulation.de, CC BY 3.0). 21 of the island centres in `islands.csv` are the centres of rings in geoBoundaries ADM0, which geoBoundaries records as a 2017 OpenStreetMap export under ODbL, and their octagons were sized around those rings. The centres of the 11 special areas, of the other 16 islands, of the zone reference points and of the fixtures are from GeoNames (CC BY 4.0). The timetables are published by JAKIM and the Selangor State Mufti Department. The library code is MIT, in `LICENSE`.

A port to another language version copies the three data files with `LICENSE-ODbL.md` and puts this credit in its readme:

> State boundaries © OpenStreetMap contributors, Open Database License 1.0 (https://opendatacommons.org/licenses/odbl/1-0/). District boundaries from geoBoundaries gbOpen MYS ADM2, CC BY 3.0. Place coordinates from GeoNames, CC BY 4.0. The zone map file is offered under the Open Database License 1.0.
