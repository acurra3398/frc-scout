# FRC Scout

iPad scouting for FRC 2026 **REBUILT**, sideloaded with SideStore. It works offline: scouts hand data to the lead with QR codes, and nothing needs Wi-Fi at the venue.

| Tab | What it's for |
|---|---|
| **Match** | Scouting one robot per match. The header shows the team's name, pit, robustness, fuel capacity, and a live points estimate. Each phase has its own color. Fuel uses +1/+5/+10 counters, and big chips cover climbs, neutral-zone autos, died and tipped. Tap the field to mark where the robot shoots from. Pick your station once and the team fills in from the schedule; typing a different team overrides it. Choosing **Playoff** switches to a quick form: role, tower, weaknesses, breaks, and strategy notes. **Whole alliance** scouts all three robots of an alliance at once, with a numbered, colored shot map for each. Counters start as "not scored", which is different from 0. |
| **Pit** | A tile for every team at the event with a "12 of 40 done" bar. Touch and hold a tile to mark it not scouted. Each form uses the 1678 robustness rubric (1–5) and records intake, shooting, climb, autos, and team questions inspired by other teams' pit forms. |
| **Teams** | A sortable table of every team: rank, EPA, OPR, and scouted averages. Each team page has stat tiles, a points-by-match chart, a shot heatmap, pit info, its schedule, and match notes. |
| **H2H** | Head-to-head, from 1678's OverRate: after a match, tap an alliance's robots from best to worst. This builds an Elo rating shown in Teams, the picklist, and team pages. |
| **Picks** | **Rank** mode: drag into order, swipe for DNP, sort by points, EPA, or OPR. **Alliance selection** mode: tap a team the moment it's picked. Best available stays on top, and Nexus or TBA alliance picks are marked automatically. |
| **Board** | Drag robots and draw routes on the 2026 field. Driver stations are shown beside each wall (flip them if your field is the other way). **Load match** (★ marks yours) or **Our next match** shows each robot's numbers and a predicted score per alliance. |
| **Data** | Your name, your team number, and **Find the event we're at** (or pick any event), plus API keys, QR codes, AirDrop and CSV exports. |

**Slack:** the **Share to Slack** buttons (match plan on the Board, team pages, picklist) build a formatted post. Pick Slack in the share sheet, then the channel or thread.

## Getting data from The Blue Alliance and Nexus

In **Data**, enter the event code (the TBA key, e.g. `2026camb`) and your API keys:
- The Blue Alliance read key from [thebluealliance.com/account](https://www.thebluealliance.com/account). It gives the event list, schedule, team names, OPR, rankings, and alliances.
- Statbotics EPA needs no key.
- Nexus key from [frc.nexus/api](https://frc.nexus/api). It gives the live schedule including practice matches, "now queuing", and pit numbers.

While the app is open it refreshes on its own: TBA and Statbotics every 5 minutes (and at launch), Nexus every minute.

Downloads are saved for offline use and included in **Export everything**. One iPad with internet can download, then AirDrop the export to scouts who have none. Keys stay on each iPad; they are never in this repo.

## Every device

- **iPad and iPhone (native):** this Xcode project runs on both, with one-column layouts on iPhone. Install with `./build.sh --device` (every plugged-in iPhone and iPad) or SideStore.
- **Android (native):** `android/` is a Kotlin + Jetpack Compose app with Match, Pit, Teams, and Setup, using the same records and sync. Build with `cd android && ./gradlew assembleDebug testDebugUnitTest`. To publish, copy `build/outputs/apk/debug/frc-scout-debug.apk` to `web/android/frc-scout.apk` and deploy the web app; scouts download it from Setup › Download FRC Scout for Android. Builds from this Mac share one signing key, so a new download installs over the old one.
- **Web (any phone or computer):** https://frc-scout-one.vercel.app. **Install app** on Android/desktop Chrome or Edge, or Share › Add to Home Screen on iPhone. It works offline, and on a computer the tabs become a sidebar with two-column forms.

## iPhone web app and team sync

**https://frc-scout-one.vercel.app** is FRC Scout for iPhones: match scouting (one robot or the whole match), pit scouting, teams, and setup. On the iPhone, Share › Add to Home Screen makes it open like an app.

Every device with the **team code** shares the event's scouting through the team server. Phones sync on every save and every 20 seconds. iPads sync every 20 seconds once the code is in Data › Team sync. So several devices can each scout a different robot in the same match.

How sync behaves:
- It only adds and updates, newest edit wins. It never deletes.
- Phones keep everything locally and catch up when they're back online.
- On the iPad, **Data › Team sync › Set up a phone** shows a QR code. Point an iPhone's camera at it, and the web app opens already set up.

The server lives in `web/`:
- Vercel functions in `web/api` handle sync, TBA, Nexus, and season EPA.
- An Upstash Redis database (from the Vercel Marketplace) stores the synced records.
- The TBA and Nexus keys and the team code are Vercel environment variables (`TBA_KEY`, `NEXUS_KEY`, `SYNC_CODE`), never in this repo or the browser.
- Deploy with `cd web && vercel deploy --prod`. Test with `npm test`.

## Install (each iPad)

1. In SideStore, open **Sources › +** and add
   `https://raw.githubusercontent.com/acurra3398/frc-scout/main/updates/source.json`
2. Install **FRC Scout** from that source. When a new version is published, SideStore shows it under **My Apps** as an update.

## Pushing an update (from anywhere)

1. Change the code. You can edit files right on github.com, including from a phone.
2. Go to **Actions › Release › Run workflow**. Enter a version higher than the last one (e.g. `1.1`) and what changed.
3. The workflow runs the checks, builds the IPA on a Mac runner, attaches it to a GitHub release, and adds it to `updates/source.json`. iPads see the update next time SideStore refreshes.

Scouting data lives in the app's Documents folder, so updates keep it. Fields added in a new version get default values for older records, and old scouts' QR codes still scan.

## Building locally

```sh
./build.sh --check        # data-logic checks (Checks/main.swift)
./build.sh --sim board    # run on an iPad simulator, opening a tab
./build.sh                # build/Scout.ipa to AirDrop and open with SideStore
./build.sh --device       # no SideStore: sign with your Xcode Apple ID and install on the plugged-in iPad (redo every 7 days)
```

Field image: WPILib's `2026-rebuilt.png` (BSD license). Point values: 2026 Game Manual section 6.
