# Licence of the Malaysian zone map

These files are derived from OpenStreetMap data and are offered under the
[Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/)
(ODbL). © OpenStreetMap contributors, https://www.openstreetmap.org/copyright.

- `data/malaysia/malaysia_zones.txt`, the zone map
- `lib/src/data/malaysia_zones_data.dart`, the same bytes as a Dart string
- `tool/malaysia/raw/openstreetmap-MYS-ADM4.json.gz`, the pinned OpenStreetMap
  snapshot of Malaysia's state boundaries that the map is built from
- `tool/malaysia/raw/openstreetmap-MYS-border-features.tsv.gz` and
  `tool/malaysia/raw/openstreetmap-MYS-offmap-features.tsv.gz`, OpenStreetMap
  buildings and places, with their outlines, filtered from the Geofabrik extract
  `malaysia-singapore-brunei-261103.osm.pbf`, which the build checks the map
  against
- `tool/malaysia/islands.csv`, whose island centres were measured on the
  geoBoundaries ADM0 layer, itself a 2017 OpenStreetMap export under ODbL
- `tool/malaysia/town_fixtures.csv`, which holds coordinates of OpenStreetMap
  features
- `tool/malaysia/state_line_exceptions.csv`, whose paths start and end on the
  OpenStreetMap state line
- `tool/malaysia/no_zone_areas.csv`, which names OpenStreetMap features by
  their ids

The zone map also contains district boundaries from geoBoundaries gbOpen MYS
ADM2 (CC BY 3.0, sources geoBoundaries and citypopulation.de) and centre points
from GeoNames (CC BY 4.0). Keep this file, and the credits in `README.md`,
with any copy of the files above. The library code stays under the MIT licence
in `LICENSE`. The prayer timetables in `data/malaysia/malaysia_times.txt` are
published by JAKIM and the Selangor State Mufti Department and are not covered
by this file.
