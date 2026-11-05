# Parity tools

Run from the repository root.

- `dart run tool/parity/probe.dart [--polar aqrabBalad|aqrabYaum|unresolved] [--correction iterative|singlePass]` prints the 12 city, 365 day, 6 method grid for 2026 as CSV, in the format of the adhan-swift probe at `Tests/Probe`.
- `dart run tool/parity/compare.dart` runs the grid for each `hourAngleCorrection` value, with `aqrabBalad` and with `unresolved`, against the adhan-swift grids in `reference/` and prints the differing cells. Its Singapore method runs with `Rounding.up`, which the adhan-swift Singapore method uses by default and this library's does not, so the comparison is exact. Exit code 1 means a difference.
- `dart compile exe tool/parity/bench.dart -o bench && ./bench [--correction iterative|singlePass]` prints the median microseconds per `PrayerTimes` construction for London over 100,000 constructions. Compile first so the number reflects AOT code.
- `dart compile exe tool/parity/bench_malaysia.dart -o bench_malaysia && ./bench_malaysia` prints the first `malaysia_official` construction in milliseconds, which includes parsing the zone map and decoding one zone-year, then the median microseconds over 100,000 constructions of a warm lookup with a manual zone, a warm lookup that resolves the zone from Kuala Lumpur's coordinates, a `MalaysiaZones.resolve` call over six Malaysian cities, and the London Muslim World League construction that `bench.dart` measures. Compile first so the numbers reflect AOT code.
- `bench_base.dart` runs the same timing loop with the default options and uses only the 2.3.0 API. Copy it into a 2.3.0 checkout and compile it there for a baseline to compare with.
