# Rounding tools

Run from the repository root.

- `dart run tool/rounding/vectors.dart` writes `test/rounding/vectors.json`. For each prayer it picks a 2026 Umm al-Qura time at Riyadh or Mecca that falls a fraction of a second, 1 second and 59 seconds past a minute, each at least 0.25 seconds from a second boundary, and adds a London lookup Fajr and sunrise that sit exactly on a minute. Each case records the instant to the millisecond and the minute each rounding value gives, derived from the rounding rules rather than from the library's rounding.
