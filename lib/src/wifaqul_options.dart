/// Missing-dawn policies for the selected Wifaqul profile.
enum WifaqulFajrRule { aqrabul_ayyam, nisf_al_layl }

/// Northern Isha policies for the selected Wifaqul profile.
enum WifaqulIshaRule { longest_day, seventh_of_night }

/// Pillars' explicit selection of published Wifaqul variants, not a claim of
/// parity with the current Wifaqul app (https://www.wifaqululama.co.uk/highlat/).
///
/// Valid 18-degree dawn is preserved. Missing northern dawn uses the last valid
/// day's UTC clock time, or optionally the midpoint of the preceding night.
/// At 48 degrees north and above, Isha uses 15 degrees and a longest-day sunset
/// plus 65 minute cap. Seventh-of-night instead caps present twilight only;
/// missing twilight still uses the longest-day cap. Below 48 north Isha is 18
/// degrees. Southern missing twilight and unsupported polar events throw an
/// ArgumentError. Generic high-latitude rules are ignored for this method.
class WifaqulOptions {
  final WifaqulFajrRule fajrRule;
  final WifaqulIshaRule ishaRule;

  const WifaqulOptions({
    this.fajrRule = WifaqulFajrRule.aqrabul_ayyam,
    this.ishaRule = WifaqulIshaRule.longest_day,
  });
}
