// Independent astronomical fixtures; not Wifaqul app timetables.
// Install astronomy-engine@2.1.19 in a scratch directory with --ignore-scripts,
// then set NODE_PATH to that directory's node_modules and run:
// node tools/generate_wifaqul_fixtures.cjs <output-json-path>
const fs = require('node:fs');
const wifaqulAstronomy = require('astronomy-engine');
const path = require('node:path');
const enginePackagePath = path.join(path.dirname(require.resolve('astronomy-engine')), 'package.json');
if (JSON.parse(fs.readFileSync(enginePackagePath, 'utf8')).version !== '2.1.19') throw new Error('Expected astronomy-engine 2.1.19');
const wifaqulDayMs = 86400000;
const wifaqulOracleCache = new Map();

function geocentricEquator(time) {
  const vector = wifaqulAstronomy.GeoVector("Sun", time, true);
  const ofDate = wifaqulAstronomy.RotateVector(wifaqulAstronomy.Rotation_EQJ_EQD(time), vector);
  return wifaqulAstronomy.EquatorFromVector(ofDate);
}

function geocentricAltitude(time, observer) {
  const equator = geocentricEquator(time);
  return wifaqulAstronomy.Horizon(time, observer, equator.ra, equator.dec, null).altitude;
}

function nightlyMinimum(approximate, observer) {
  return wifaqulAstronomy.Search(
    time => geocentricAltitude(time.AddDays(1 / 86400), observer)
      - geocentricAltitude(time.AddDays(-1 / 86400), observer),
    wifaqulAstronomy.MakeTime(new Date(+approximate - 3600000)),
    wifaqulAstronomy.MakeTime(new Date(+approximate + 3600000)),
    {dt_tolerance_seconds: 0.01}
  );
}

function wifaqulRawSolar(dateText, latitude, longitude) {
  const key = `${dateText}|${latitude}|${longitude}`;
  if (wifaqulOracleCache.has(key))
    return wifaqulOracleCache.get(key);
  const observer = new wifaqulAstronomy.Observer(latitude, longitude, 0);
  const midnight = Date.parse(dateText + "T00:00:00Z");
  const noon = wifaqulAstronomy.SearchHourAngle("Sun", observer, 0, new Date(midnight - longitude / 360 * wifaqulDayMs), 1).time.date;
  const morningStart = nightlyMinimum(wifaqulAstronomy.SearchHourAngle("Sun", observer, 12, noon, -1).time.date, observer);
  const eveningEnd = nightlyMinimum(wifaqulAstronomy.SearchHourAngle("Sun", observer, 12, noon, 1).time.date, observer);
  const event = (altitude, rising) => {
    const minimum = rising ? morningStart : eveningEnd;
    if (!minimum || geocentricAltitude(minimum, observer) > altitude
        || geocentricAltitude(noon, observer) < altitude) return null;
    return wifaqulAstronomy.Search(
      time => (geocentricAltitude(time, observer) - altitude) * (rising ? 1 : -1),
      wifaqulAstronomy.MakeTime(rising ? minimum : noon),
      wifaqulAstronomy.MakeTime(rising ? noon : minimum),
      {dt_tolerance_seconds: 0.01}
    )?.date ?? null;
  };
  const declination = geocentricEquator(noon).dec;
  const asr = (shadow) => event(Math.atan(1 / (shadow + Math.tan(Math.abs(latitude - declination) * Math.PI / 180))) * 180 / Math.PI, false);
  const result = { midnight, noon, sunrise: event(-50 / 60, true), sunset: event(-50 / 60, false), fajr: event(-18, true), isha15: event(-15, false), isha18: event(-18, false), asrShafi: asr(1), asrHanafi: asr(2) };
  wifaqulOracleCache.set(key, result);
  return result;
}

function wifaqulShiftDate(dateText, days) {
  return new Date(Date.parse(dateText + "T00:00:00Z") + days * wifaqulDayMs).toISOString().slice(0, 10);
}

function wifaqulReferenceCap(year, latitude, longitude) {
  let longest = null;
  for (let day = 15;day <= 25; day++) {
    const solar = wifaqulRawSolar(`${year}-06-${day}`, latitude, longitude);
    if (!solar.sunrise || !solar.sunset)
      return null;
    if (!longest || +solar.sunset - +solar.sunrise > longest.daylight)
      longest = { date: `${year}-06-${day}`, daylight: +solar.sunset - +solar.sunrise, offset: +solar.sunset - solar.midnight + 65 * 60000 };
  }
  return longest;
}

function wifaqulOracleCase(date, latitude, longitude, madhab = "shafi", fajrRule = "aqrabul_ayyam", ishaRule = "longest_day") {
  const solar = wifaqulRawSolar(date, latitude, longitude);
  if (!solar.sunrise || !solar.sunset)
    return null;
  let fajr = solar.fajr;
  let fajrReferenceDate = null;
  if (!fajr) {
    if (latitude < 0)
      return null;
    if (fajrRule === "nisf_al_layl") {
      const previous = wifaqulRawSolar(wifaqulShiftDate(date, -1), latitude, longitude);
      if (!previous.sunset)
        return null;
      fajr = new Date((+previous.sunset + +solar.sunrise) / 2);
    } else {
      for (let days = 1;days <= 370; days++) {
        const referenceDate = wifaqulShiftDate(date, -days);
        const previous = wifaqulRawSolar(referenceDate, latitude, longitude);
        if (previous.fajr) {
          fajr = new Date(solar.midnight + +previous.fajr - previous.midnight);
          fajrReferenceDate = referenceDate;
          break;
        }
      }
    }
  }
  let isha = latitude >= 48 ? solar.isha15 : solar.isha18;
  let ishaReferenceDate = null;
  if (latitude >= 48) {
    const cap = wifaqulReferenceCap(Number(date.slice(0, 4)), latitude, longitude);
    if (!cap)
      return null;
    ishaReferenceDate = cap.date;
    if (isha && ishaRule === "seventh_of_night") {
      const tomorrow = wifaqulRawSolar(wifaqulShiftDate(date, 1), latitude, longitude);
      if (!tomorrow.sunrise)
        return null;
      isha = new Date(Math.min(+isha, +solar.sunset + (+tomorrow.sunrise - +solar.sunset) / 7));
    } else
      isha = new Date(Math.min(isha ? +isha : 1 / 0, solar.midnight + cap.offset));
  }
  if (!fajr || !isha)
    return null;
  const prayers = { fajr, sunrise: solar.sunrise, dhuhr: new Date(+solar.noon + 4 * 60000), asr: madhab === "hanafi" ? solar.asrHanafi : solar.asrShafi, maghrib: new Date(+solar.sunset + 5 * 60000), isha };
  return { date, latitude, longitude, madhab, fajrRule, ishaRule, fajrReferenceDate, ishaReferenceDate, expected: Object.fromEntries(Object.entries(prayers).map(([prayer, time]) => [prayer, time.toISOString()])) };
}

const inputs = [
  [
    "London ordinary winter",
    "2026-01-15",
    51.5074,
    -0.1278
  ],
  [
    "London Hanafi winter",
    "2026-01-15",
    51.5074,
    -0.1278,
    "hanafi"
  ],
  [
    "Aberdeen ordinary winter",
    "2026-01-15",
    57.1497,
    -2.0943
  ],
  [
    "Cairo below northern boundary",
    "2026-01-15",
    30.0444,
    31.2357,
    "hanafi"
  ],
  [
    "Cape Town ordinary southern summer",
    "2026-01-15",
    -33.9249,
    18.4241
  ],
  [
    "Below 48 north",
    "2026-04-01",
    47.999,
    0
  ],
  [
    "Exactly 48 north",
    "2026-04-01",
    48,
    0
  ],
  [
    "Above 48 north",
    "2026-04-01",
    48.001,
    0
  ],
  [
    "London before BST",
    "2026-03-28",
    51.5074,
    -0.1278
  ],
  [
    "London after BST",
    "2026-03-29",
    51.5074,
    -0.1278
  ],
  [
    "London before GMT",
    "2026-10-24",
    51.5074,
    -0.1278
  ],
  [
    "London after GMT",
    "2026-10-25",
    51.5074,
    -0.1278
  ],
  [
    "London late existing Isha",
    "2026-05-01",
    51.5074,
    -0.1278
  ],
  [
    "London last valid Fajr",
    "2026-05-22",
    51.5074,
    -0.1278
  ],
  [
    "London first absent Fajr",
    "2026-05-23",
    51.5074,
    -0.1278
  ],
  [
    "London early frozen season",
    "2026-06-01",
    51.5074,
    -0.1278
  ],
  [
    "London solstice default",
    "2026-06-21",
    51.5074,
    -0.1278
  ],
  [
    "London solstice Hanafi",
    "2026-06-21",
    51.5074,
    -0.1278,
    "hanafi"
  ],
  [
    "London late frozen season",
    "2026-07-15",
    51.5074,
    -0.1278
  ],
  [
    "London restored twilight",
    "2026-08-01",
    51.5074,
    -0.1278
  ],
  [
    "London solstice Nisf",
    "2026-06-21",
    51.5074,
    -0.1278,
    "shafi",
    "nisf_al_layl"
  ],
  [
    "London early Nisf",
    "2026-05-23",
    51.5074,
    -0.1278,
    "shafi",
    "nisf_al_layl"
  ],
  [
    "London existing seventh Isha",
    "2026-05-01",
    51.5074,
    -0.1278,
    "shafi",
    "aqrabul_ayyam",
    "seventh_of_night"
  ],
  [
    "London existing midsummer seventh Isha",
    "2026-06-21",
    51.5074,
    -0.1278,
    "shafi",
    "aqrabul_ayyam",
    "seventh_of_night"
  ],
  [
    "Aberdeen solstice default",
    "2026-06-21",
    57.1497,
    -2.0943
  ],
  [
    "Aberdeen solstice Nisf Hanafi",
    "2026-06-21",
    57.1497,
    -2.0943,
    "hanafi",
    "nisf_al_layl"
  ],
  [
    "Aberdeen early missing season",
    "2026-05-01",
    57.1497,
    -2.0943
  ],
  [
    "Aberdeen restored twilight",
    "2026-08-20",
    57.1497,
    -2.0943
  ],
  [
    "Leap day",
    "2024-02-29",
    51.5074,
    -0.1278
  ],
  [
    "Leap year solstice",
    "2024-06-21",
    51.5074,
    -0.1278
  ],
  [
    "Following year solstice",
    "2027-06-21",
    51.5074,
    -0.1278
  ],
  [
    "Year end",
    "2026-12-31",
    57.1497,
    -2.0943
  ],
  [
    "Western longitude Isha next UTC date",
    "2026-06-21",
    61.2181,
    -149.9003
  ],
  [
    "Eastern longitude Fajr prior UTC date",
    "2026-06-21",
    62.0355,
    129.6755
  ],
  [
    "Sydney southern ordinary winter",
    "2026-06-21",
    -33.8688,
    151.2093,
    "hanafi"
  ],
  [
    "Southern near twilight boundary ordinary",
    "2026-03-21",
    -54.8,
    -68.3
  ],
  ["Aberdeen absent seventh Isha", "2026-06-21", 57.1497, -2.0943, "shafi", "aqrabul_ayyam", "seventh_of_night"],
  ["London during New York repeated hour 2024", "2024-11-03", 51.5074, -0.1278],
  ["London during New York repeated hour 2026", "2026-11-01", 51.5074, -0.1278],
  ["Near western date line winter", "2026-01-01", 48, -179.9],
  ["Near eastern date line autumn", "2026-09-21", 48, 179.9],
  ["Western date line meridian winter", "2026-01-01", 48, -180],
  ["Eastern date line meridian autumn", "2026-09-21", 48, 180],
  ["Near western date line solstice", "2026-06-21", 60, -179.9],
  ["Near eastern date line solstice", "2026-06-21", 60, 179.9],
  ["Western date line meridian solstice", "2026-06-21", 60, -180],
  ["Eastern date line meridian solstice", "2026-06-21", 60, 180]
];
const metadata = {
  "schemaVersion": 1,
  "profile": "Wifaqul selected variants: last-valid-day Aqrab; longest-day sunset +65 minutes; UTC reference clocks",
  "provenance": {
    "engine": "Astronomy Engine",
    "version": "2.1.19",
    "source": "https://github.com/cosinekitty/astronomy/tree/v2.1.19",
    "documentation": "https://github.com/cosinekitty/astronomy/blob/v2.1.19/source/js/README.md",
    "generatedAt": "2026-09-15",
    "claim": "Independent astronomical reference with the explicit selected policy applied; NOT Wifaqul app or PDF timetable outputs. No Adhan implementation was used to generate expected instants.",
    "altitudeDefinition": "Geocentric apparent Sun centre via GeoVector, EQJ-to-EQD rotation and Horizon without refraction; no topocentric solar parallax, matching Adhan's geometric convention. Search locates the altitude derivative zero and then the rising/falling crossing. Horizon -50/60 degrees; Fajr -18; Isha -15 at >=48N otherwise -18. Transit SearchHourAngle=0; Asr uses independent geocentric declination at transit.",
    "referenceDefinition": "Last available raw 18-degree Fajr UTC offset; longest daylight among June15-25, raw sunset UTC offset+65 minutes. No intermediate rounding.",
    "toleranceSeconds": 120,
    "toleranceReason": "Compare distinct astronomical models plus final minute rounding, not bit-identical ephemerides. Boundary-selection behavior is additionally tested against each engine raw events."
  }
};
const cases = inputs.map(([name,...args]) => ({name,...wifaqulOracleCase(...args)}));
if (cases.some(row => !row.expected)) throw new Error("Reference fixture has unavailable events");
const output = JSON.stringify({...metadata, cases}, null, 2) + "\n";
if (!process.argv[2]) throw new Error("Provide the output JSON path");
fs.writeFileSync(process.argv[2], output);
console.log(`Generated ${cases.length} independent reference cases`);
