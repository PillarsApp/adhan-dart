# Parity tools

Run from the repository root.

- `dart run tool/parity/probe.dart [--polar aqrabBalad|aqrabYaum|unresolved] [--correction iterative|singlePass]` prints the 10 city, 365 day, 6 method grid for 2026 as CSV, in the format of the adhan-swift probe at `Tests/Probe`.
- `dart run tool/parity/compare.dart` runs the grid for each `hourAngleCorrection` value against the adhan-swift grids in `reference/` and prints the differing cells. Exit code 1 means a difference outside the Singapore rounding exclusion.
- `dart compile exe tool/parity/bench.dart -o bench && ./bench [--correction iterative|singlePass]` prints the median microseconds per `PrayerTimes` construction for London over 100,000 constructions. Compile first so the number reflects AOT code.
