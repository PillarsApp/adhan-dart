# Parity tools

Run from the repository root.

- `dart run tool/parity/probe.dart [--polar aqrabBalad|aqrabYaum|unresolved] [--correction iterative|singlePass]` prints the 10 city, 365 day, 6 method grid for 2026 as CSV, in the format of the adhan-swift probe at `Tests/Probe`.
- `dart run tool/parity/compare.dart` runs the grid for each `hourAngleCorrection` value, with `aqrabBalad` and with `unresolved`, against the adhan-swift grids in `reference/` and prints the differing cells. Its Singapore method runs with `Rounding.up`, which the adhan-swift Singapore method uses by default and this library's does not, so the comparison is exact. Exit code 1 means a difference.
- `dart compile exe tool/parity/bench.dart -o bench && ./bench [--correction iterative|singlePass]` prints the median microseconds per `PrayerTimes` construction for London over 100,000 constructions. Compile first so the number reflects AOT code.
