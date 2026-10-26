# School Air

Tells the people who run a room whether its air is OK by reading CO₂ inside and particles outside.

Congressional App Challenge 2026, IN-08.

iPhone app in Swift and SwiftUI with Swift Charts and Firebase Realtime Database. Two small sensor
boxes (one indoor CO₂ box, one portable particle box) post readings to Firebase; the app turns them
into one plain-language advisory.

## Why

The usual fix for a stuffy classroom is "open a window". On a smoky or high-pollen day that pulls
particles in. The two numbers have to be read together, and the app refuses to give a green light
when it does not have fresh data from both.

## Screens

- **Sensors (Now)**: the advisory at the top, then each box's reading with its source, units,
  one-minute average, time measured and status (live / warming up / stale / missing). A separate
  card shows the regional outdoor AQI with its own label and time. Tap a reading for its history.
- **Weather**: current conditions, hourly and seven-day forecast for the configured city
  (Open-Meteo). Switchable °F/°C without touching sensor units.
- **History**: the last 24 hours and 7 days of CO₂ and PM2.5 on separate charts. Gaps are shaded
  gray and never filled in. Event markers (HVAC changed, window opened, HEPA on, class ended, box
  moved) are added by hand from the **+** button.
- **ⓘ About**: how to read the three numbers, the bands and the thresholds.
- **Family access**: the owner phone approves other phones to view the sensors (see below).

## The advisory logic

`SchoolAir/Models/Advisory.swift`. Inputs: latest CO₂, latest outdoor PM2.5, both box statuses, and
whether the portable box's location is known. Separate trigger and clear thresholds so it does not
chatter:

| | Trigger | Clear |
|---|---|---|
| CO₂ elevated | ≥ 1000 ppm | < 900 ppm |
| Outdoor particles elevated | ≥ 35.5 µg/m³ | < 30.0 µg/m³ |

| Situation | What the app says |
|---|---|
| CO₂ elevated, outdoor fine | The room needs more outside air. Raise the HVAC outdoor-air setting or open windows where allowed. |
| CO₂ elevated, particles elevated | Names the conflict. Filtration first, windows shut, fewer people or move the group. |
| Particles elevated, CO₂ normal | Outdoor advisory. Windows shut, rely on filtration. Never "safe". |
| Stale, missing, or unknown location | "Insufficient current information." Never a green light. |

Stale means no reading for 3 minutes (`BoxStatus.staleAfter`). Colors are ventilation prompts and
EPA concentration bands, not health ratings, and the app says so on screen.

## Data

### Firebase Realtime Database contract

```
/nodes/{id}              name, kind (indoor | portable), location, schemaVersion
/latest/{id}             newest reading, overwritten on each upload
/readings/{id}/{autoId}  one entry per upload, never overwritten
/viewers/{uid}           display name of an approved family phone (owner-managed)
```

Every reading: `t` (Firebase server timestamp, `{".sv": "timestamp"}`), `schemaVersion`, `seq`,
`bootId`, `qualityFlags` (`warming_up`, `sensor_missing`, `incomplete`).
Indoor adds `co2`, `tempC`, `rh`. Portable adds environmental `pm25`, `pm10`, `tempC`, `rh` and
`session` (`window`, `porch`, `moving`). A missing value is absent, never zero.
Node ids: `home-in`, `portable`. Legacy `pm25env` is accepted; CF=1 `pm25std` is never silently
substituted.

`SchoolAir/Data/ReadingDecoder.swift` decodes this shape (unit tested, SDK-free).
`SchoolAir/Data/FirebaseReadingSource.swift` attaches the live listeners.

### Freshness and history

- A three-minute sensor timeout stays truthful: receiving a cached record does not make it fresh.
  The Sensors screen distinguishes database connectivity, read errors and sensor freshness.
- History loads a bounded number of push-key records per box, processes incremental changes off
  the UI thread, and keeps seven days in memory. Day charts use 5-minute averages, week charts
  30-minute averages, both preserving outages over 150 seconds. Statistics use the original samples.

### Regional outdoor AQI

By default the outside AQI card shows an explicitly labeled **Open-Meteo / CAMS** regional model
estimate for the configured city (Evansville, IN), with model-valid time, attribution and PM2.5 as
a separate µg/m³ value. It is a model, not an EPA monitor observation, and the UI says so. Missing,
stale, future or malformed reports produce explicit errors rather than a number.

If an AirNow API key is configured in `Secrets.plist`, the card uses the EPA AirNow observation for
the configured ZIP code instead.

### Swapping the data source

`SchoolAirApp.swift` builds the store with one `ReadingSource`:

- `FirebaseReadingSource()` — live data (default).
- `PlaceholderReadingSource()` — a deterministic made-up week, labelled "Placeholder" on every
  screen. Launch with the `-demo` argument in a Debug build to use it without any hardware.
- `RecordedReadingSource(url:)` — replays a `RecordedSession` JSON file, labelled "Recorded".

### Family access

Phones sign in to Firebase anonymously. One phone is the **owner**: it can approve other phones by
pasting the code they display (`SA1:<uid>`), and revoke them. Approved phones read both boxes and
their history; nobody but the sensor uploader can write readings, and history entries can never be
overwritten or deleted. All of this is enforced by `Firebase/database.rules.json`, and
`Firebase/security-tests.cjs` proves it against the emulator.

## Getting started

Requirements: Xcode 16 or later, iOS 17 or later, a Firebase project, and Node 18+ if you want to
run the rules tests.

1. **Clone** and open `SchoolAir.xcodeproj`. Swift Package Manager fetches the Firebase SDK.

2. **Firebase project.** In the Firebase console create a project, enable **Authentication →
   Anonymous**, create a **Realtime Database**, and add an **iOS app** with bundle id
   `org.schoolair.SchoolAir` (or change the bundle id in Xcode to match one you prefer). Download
   `GoogleService-Info.plist` into `SchoolAir/`. It is gitignored; never commit it.

3. **Secrets.** Copy `SchoolAir/Secrets.example.plist` to `SchoolAir/Secrets.plist` (gitignored).
   Leave the UIDs blank for the first run.

4. **Signing.** In the SchoolAir target's *Signing & Capabilities*, pick your team. Build and run.
   Without hardware, add `-demo` under *Product → Scheme → Edit Scheme → Arguments* to see the app
   with placeholder data.

5. **Make your phone the owner.** Run the app once on the phone that should manage access, open
   *Sensors → Family access*, and copy its code. The 28 characters after `SA1:` are that phone's
   Firebase UID. Put it in `Secrets.plist` as `FIREBASE_OWNER_UID`.

6. **Sensor identity.** Create a Firebase user for the sensor boxes (any sign-in method; the boxes
   authenticate with it when they upload) and put its UID in `Secrets.plist` as
   `FIREBASE_SENSOR_UID`.

7. **Deploy rules.** In `Firebase/database.rules.json`, replace `OWNER_UID_PLACEHOLDER` and
   `SENSOR_UID_PLACEHOLDER` with the same two UIDs, then:

   ```sh
   cd Firebase
   npm install
   npx firebase login
   npx firebase deploy --only database --project <your-project-id>
   ```

   Rebuild the app so it picks up the new `Secrets.plist`.

8. **Optional: AirNow.** Paste a free key from <https://docs.airnowapi.org> into `Secrets.plist`
   as `AIRNOW_API_KEY`, and set `AIRNOW_ZIP`. Without a key the app uses the Open-Meteo/CAMS model.

The regional city for weather and modeled AQI is set in `SchoolAir/Data/Weather.swift`
(`WeatherReport.area`, `WeatherClient.url`) and `SchoolAir/Data/AirNow.swift` (`OpenMeteoClient`).

## Tests

- **App**: `SchoolAirTests` covers the advisory engine (all four situations, insufficient states,
  hysteresis), the bands, box status, gap detection and bucketing, the Firebase decoder, the AirNow
  and Open-Meteo parsers, weather decoding, the history display pipeline, the phone-location
  capture rules and the family-access code format. Run with ⌘U.
- **Security rules**: `cd Firebase && npm install && npm test` starts the Realtime Database
  emulator (needs Java) and runs `security-tests.cjs` against `database.rules.json`. The tests read
  the owner and sensor UIDs from the rules file, so they pass with the placeholders as shipped and
  with your real UIDs after you fill them in.

## Hardware

The sensor boxes are not part of this repository. The indoor box carries a Sensirion **SCD-41**
(CO₂, temperature, humidity); the portable box carries a Plantower **PMSA003I** (PM2.5 / PM10) and a
Sensirion **SHT45**. Each posts to Firebase following the data contract above. The portable box has
no GPS: its location is set once from the phone while standing next to it and is stored on the
phone only.

## Privacy

- Phones use anonymous Firebase sign-in; no accounts, emails or names are collected.
- The saved box location never leaves the phone. Weather and modeled AQI always use the configured
  city, not the phone's location.
- API keys, the Firebase config file and account UIDs live in gitignored files
  (`GoogleService-Info.plist`, `Secrets.plist`). The committed rules use placeholders.

## Project layout

```
SchoolAir/            iOS app (SwiftUI)
  Data/               reading sources, Firebase, AirNow/Open-Meteo, weather, location, secrets
  Models/             advisory engine, bands, status, history series, insights, decoders
  Views/              Sensors, History, Weather, About, Family access, splash, theme
SchoolAirTests/       unit tests (XCTest and Swift Testing)
Firebase/             Realtime Database rules, emulator config and rules tests
Design/               scripts that render the app icon (Pillow)
```

## Not in version one

Map and nearest-monitor view, humidity correction inside the alert logic (an experimental
correction exists in `HumidityCorrection.swift` but is neither displayed nor applied), push
notifications, battery power and duty cycling, permanent outdoor install.

## License

MIT — see [LICENSE](LICENSE).
