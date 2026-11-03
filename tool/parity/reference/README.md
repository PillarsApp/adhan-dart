# Reference grids

Output of the adhan-swift probe at `Tests/Probe` for the same 10 city, 365 day,
6 method grid as `tool/parity/probe.dart`, taken from
[PillarsApp/adhan-swift](https://github.com/PillarsApp/adhan-swift) commit
`8ce6218ed3ce21950539e57a6e6e99a3bc8fb586` with these commands, run from
`Tests/Probe` with `swift build -c release`:

- `swift-iterative.csv.gz`: `.build/release/Probe --correction iterative`
- `swift-singlePass.csv.gz`: `.build/release/Probe --correction singlePass`

Both use the default `polarCircleResolution`, `aqrabBalad`. Regenerate them when
adhan-swift changes a result, then run `dart run tool/parity/compare.dart`.
