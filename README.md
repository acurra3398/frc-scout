# FRC Scout

iPad scouting for FRC 2026 **REBUILT**, sideloaded with SideStore. It works offline: scouts hand data to the lead with QR codes, and nothing needs Wi-Fi at the venue.

| Tab | What it's for |
|---|---|
| **Match** | Objective scouting of one robot per match. Fuel uses +1/+5/+10 counters, as most Chief Delphi teams settled on. It also covers auto L1 climb, neutral-zone autos, passes, role, tower level, 1–5 ratings (accuracy, driver, defense), died/tipped, and notes. Pick your station once and the team fills in from the schedule. Typing a different team overrides it. |
| **Pit** | The 1678 robustness rubric (1–5, mechanical and electrical), drivetrain, how much fuel it holds, trench and bump, climb level, shooting on the move, a photo, and notes. |
| **Teams** | A sortable table of every team at the event: rank and OPR (from TBA) beside your scouted averages. Tap a team for its pit info, pit number, schedule, and every match note. |
| **Picklist** | Drag teams into pick order (Edit). Swipe a team to mark it **DNP** or **Picked**, then share the list as text for Slack. |
| **Board** | The REBUILT field. Drag the six robots around and draw routes with a finger or Apple Pencil. **Load match** fills in team numbers from the schedule. |
| **Data** | Your name and event code, TBA and Nexus downloads, QR codes, AirDrop export/import, and CSV for Sheets. |

## Getting data from The Blue Alliance and Nexus

In **Data**, enter the event code (the TBA key, e.g. `2026camb`) and your API keys:
- The Blue Alliance read key from [thebluealliance.com/account](https://www.thebluealliance.com/account). It gives the schedule, team names, OPR, and rankings.
- Nexus key from [frc.nexus/api](https://frc.nexus/api). It gives the live schedule including practice matches, "now queuing", and pit numbers. While the app is open it refreshes every minute.

Downloads are saved for offline use and included in **Export everything**. One iPad with internet can download, then AirDrop the export to scouts who have none. Keys stay on each iPad; they are never in this repo.

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
```

Field image: WPILib's `2026-rebuilt.png` (BSD license). Point values: 2026 Game Manual section 6.
