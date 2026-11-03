# Reference grids

Output of the adhan-swift probe at `Tests/Probe` for the same 12 city, 365 day,
6 method grid as `tool/parity/probe.dart`, taken from
[PillarsApp/adhan-swift](https://github.com/PillarsApp/adhan-swift) commit
`46a5f21cad82fab54b4a0e86362a4d1e302625ed` with these commands, run from
`Tests/Probe` after `swift build -c release`:

- `swift-iterative.csv.gz`: `.build/release/Probe --correction iterative`
- `swift-singlePass.csv.gz`: `.build/release/Probe --correction singlePass`
- `swift-iterative-unresolved.csv.gz`: `.build/release/Probe --correction iterative --polar unresolved`
- `swift-singlePass-unresolved.csv.gz`: `.build/release/Probe --correction singlePass --polar unresolved`

The first two use the default `polarCircleResolution`, `aqrabBalad`. Regenerate
them when adhan-swift changes a result, then run `dart run tool/parity/compare.dart`.
