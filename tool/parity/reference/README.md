# Reference grids

Output of the adhan-swift probe at `Tests/Probe` for the same 12 city, 365 day,
6 method grid as `tool/parity/probe.dart`, taken from
[PillarsApp/adhan-swift](https://github.com/PillarsApp/adhan-swift) commit
`f22e5cd0834f861f19c12538967f70ffcc21f885` with these commands, run from
`Tests/Probe` after `swift build -c release`:

- `swift-iterative.csv.gz`: `.build/release/Probe --correction iterative`
- `swift-singlePass.csv.gz`: `.build/release/Probe --correction singlePass`
- `swift-iterative-unresolved.csv.gz`: `.build/release/Probe --correction iterative --polar unresolved`
- `swift-singlePass-unresolved.csv.gz`: `.build/release/Probe --correction singlePass --polar unresolved`

The first two use the default `polarCircleResolution`, `aqrabBalad`. Regenerate
them when adhan-swift changes a result, then run `dart run tool/parity/compare.dart`.
