import SwiftUI

/// The ? button on every tab: what the screen is for and the things a new scout wouldn't know.
struct HelpButton: View {
    let title: String
    let items: [(String, String)]
    @State private var showing = false

    var body: some View {
        Button("Help", systemImage: "questionmark.circle") { showing = true }
            .popover(isPresented: $showing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title).font(.title2.bold())
                        ForEach(items, id: \.0) { heading, body in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(heading).font(.headline)
                                Text(.init(body)).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(24)
                }
                .frame(idealWidth: 460, idealHeight: 560)
                .presentationCompactAdaptation(.sheet)
            }
    }
}

enum Help {
    static let match: [(String, String)] = [
        ("Match number", "With the schedule downloaded, only real matches can be picked: use the arrows, or tap the number for the list (each match shows its six teams). After you save, it moves to the next scheduled match by itself."),
        ("Team badges", "\"No pit data\" means nobody has pit scouted that team yet. \"First match\" means nobody has match scouted them at this event; otherwise it shows how many matches we have."),
        ("Station", "Your seat for the event (Red 1 to Blue 3). Once the schedule is downloaded, the team fills in by itself when you type the match number. Type a different team to override it. Each seat is its own robot: switching from Red 1 to Blue 1 starts Blue 1 fresh, and switching back brings Red 1's answers back."),
        ("Count only fuel in the ACTIVE hub", "Both hubs are active in auto, the 10 s transition, and the last 30 s. During shifts 1-4 only one alliance's hub is active, and fuel in an inactive hub scores nothing, so don't count it."),
        ("Passes", "Volleys a robot shoots or pushes from midfield back to its own side for a partner to score. One volley = one tap, not one ball."),
        ("Shot map", "Tap where the robot shoots from. It builds a heatmap on the team's page. The arrow removes the last spot."),
        ("Ratings", "1 to 5, tap the same number again to clear it. Leave Defense blank if they didn't play defense."),
        ("Clearing", "Every section has a Clear button that resets just that part for the robot you're on. The trash icon on the shot map removes all of its spots at once. Clear this robot's answers (below Save) starts the robot over but keeps the team and match."),
        ("Didn't shoot / drive only", "The robot never shot: it only drove around, pushed, or played defense."),
        ("E-stop vs A-stop", "E-stopped: the drive team hit the emergency stop and the robot sat dead for the rest of the match. A-stopped: they stopped it during auto only, and it came back in teleop."),
        ("Not scored vs 0", "Counters and the tower start blank, meaning \"not scored\". Tap 0 when they really scored none. The × next to a counter clears it back to blank. Blanks are left out of averages, so a scout who missed auto doesn't drag a team's numbers down."),
        ("Whole match", "Switch to Whole match to scout several robots at once. All six are separate: Red 1-3 on the top row, Blue 1-3 below. Tap a robot's button (or its R1-B3 tag above the shot map) to switch, then count and tap the field for that robot. Each robot's spots show its own tag and color. Save stores only the robots you recorded something for, with a QR code for each."),
        ("Est. points", "Auto fuel + 15 for an auto Level 1 climb + teleop fuel + 10/20/30 for the tower level at the end."),
        ("Playoffs", "Choosing Playoff switches to a quick form for the elims strategists: role, weaknesses, breaks, and strategy notes."),
        ("After you save", "A QR code appears. The lead scout scans it in Data › Scan QR codes. No Wi-Fi needed."),
    ]

    static let pit: [(String, String)] = [
        ("The grid", "Every team at the event. Green tiles are done, and the badge is their robustness rating. Tap a tile to scout it."),
        ("To do only", "The filter button hides teams that are already pit scouted."),
        ("Touch and hold a tile", "Mark it as not scouted (deletes its pit answers), or remove the team from this event's lists."),
        ("Robustness 1-5", "1678's rubric: 5 looks indestructible, 3 is a normal robot, 1 will probably break. Look at load paths, shafts, chains, and how tidy and protected the wiring is."),
        ("Ask them to show you", "Teams overestimate. Count fuel into the hopper yourself and watch the intake run when you can. The team page puts their claims next to what scouts actually saw."),
        ("Trench and bump", "The trench is the low structure robots drive under; the bump is the ramp they drive over. Both connect their zone to the neutral zone."),
        ("Passing", "Shooting or pushing fuel from midfield back to their own side so a partner can score it."),
    ]

    static let teams: [(String, String)] = [
        ("Rank", "Qualification rank from The Blue Alliance."),
        ("H2H", "Head-to-head rating from the H2H tab. Everyone starts at 1500; beating robots in comparisons raises it."),
        ("EPA", "Statbotics' Expected Points Added for the whole 2026 season: how many points a robot typically adds to its alliance."),
        ("Live", "EPA updated after every match at this event from TBA's real scores (fouls removed). It starts at the season EPA and moves when a robot does better or worse than expected."),
        ("OPR", "TBA's Offensive Power Rating: each robot's share of its alliances' scores at this event. Only appears once matches are played."),
        ("Pts, Auto, Tele, Tower", "Averages from your scouts. The small \"6m\" next to a team number is how many matches were scouted. Passes and accuracy are on each team's page."),
        ("Drive, Def", "Average 1-5 ratings from scouts. Blank ratings are left out of the average."),
        ("Robust", "The pit robustness rating, 1-5. Red is risky."),
        ("Not scouted yet", "Shows only teams with no scouted matches, with each one's next match and seat so you can send a scout."),
        ("Pre-scouting", "Open a team and fill in its Pre-scout card before the event: a tier (T1 elite to T4 weak) and notes from videos, TBA, or past events. The tier shows next to the team number here and can count in the weighted picklist."),
        ("Past events", "Scouting from every competition is kept. Team pages show notes from other events, and Data › Events on this device switches back to an old event."),
        ("Tips", "Tap a column header to sort. Search by number or name. The share button posts an event overview to Slack."),
    ]

    static let h2h: [(String, String)] = [
        ("What it's for", "Numbers miss things like defense, smart driving, and robots that make partners better. After each match, rank an alliance's robots by who helped the alliance most. This is 1678's OverRate idea."),
        ("How to use it", "Pick the match and alliance (the robots fill in from the schedule), tap the robots best first, then save. Tap a robot again to start over."),
        ("How ratings work", "Every ranking turns into pairs (1st beat 2nd, 1st beat 3rd, 2nd beat 3rd). Ratings start at 1500 and move like chess Elo: beating a higher-rated robot moves you more."),
        ("Fixing mistakes", "Tap the trash next to a comparison to delete it, or delete all of this event's comparisons at the bottom."),
    ]

    static let picks: [(String, String)] = [
        ("Rank mode", "Your picklist. Tap Edit to drag teams into order. Swipe left for DNP or Taken, swipe right to remove a team. Sort fills the order from points, EPA, live EPA, OPR, or head-to-head."),
        ("Weighted picklist", "Sort › Weighted lets you mix factors (points, tower, EPA, robustness, reliability, pre-scout tier and more) with sliders. Each is scaled 0-100 across the event and combined by your weights. Apply it, then drag to fine-tune."),
        ("More info", "In alliance selection, the ⓘ on any team opens its full page (notes, chart, pit answers). Rows show the latest match note, and the best-available card shows the key numbers and recent notes."),
        ("Alliance selection mode", "For the field: tap a team the moment it's picked or becomes a captain. The best available team stays big at the top. Pull down to load picks from Nexus or TBA."),
        ("1678's rule of thumb", "During quals, don't move a team up more than two spots after one match. Reliability matters more than one great match."),
        ("Share to Slack", "Posts the list with taken teams crossed out and DNPs marked."),
    ]

    static let board: [(String, String)] = [
        ("Drawing", "Draw routes with a finger or Apple Pencil. Pick a color, use the eraser, undo the last line, or clear everything."),
        ("Robots", "Drag the six robots anywhere. The circular arrow puts them back at the start."),
        ("Driver stations", "The boxes beside each wall are the driver stations, with the team standing in each. The manual puts each tower between Stations 2 and 3. If your event's field is laid out the other way, tap the up-down arrow to flip them. Your team has a yellow outline."),
        ("Load match", "Fills in the six teams from the schedule. Your team's matches have a ★."),
        ("Our next match", "Loads your next match: the one queuing now (with Nexus), or the first one after the latest match you scouted. Set your team number in Data."),
        ("Predicted score", "Adds up each robot's live EPA, or its scouted average when there's no live EPA yet, or its season EPA."),
        ("Share to Slack", "Posts the match plan with both alliances, predictions, and each team's recent scout notes."),
    ]

    static let data: [(String, String)] = [
        ("Set up each device", "Enter your name and team number, then Find the event we're at (needs a TBA key), or Choose any event. Everything the scouts save is tagged with the event."),
        ("Team sync", "Enter the team code once on each device. Then every iPad and phone shares this event's scouting by itself every 20 seconds while the app is open, so each one can scout a different robot in the same match. iPhones can run this app too; Android phones and computers use frc-scout-one.vercel.app (Setup there has the Android app). Sync only adds and updates records; deleting something on one device doesn't delete it anywhere else."),
        ("Keys", "The Blue Alliance read key comes from thebluealliance.com/account. The Nexus key (optional) comes from frc.nexus/api; pick the Pull API, not webhooks. Statbotics needs no key."),
        ("Automatic updates", "While the app is open it re-downloads TBA and Statbotics data every 5 minutes, and Nexus every minute."),
        ("Getting data to the lead scout", "Scouts open Show my QR codes and swipe through; the lead taps Scan QR codes and points the camera. Or use Export everything and AirDrop the file, then Import on the lead's iPad."),
        ("Scouts without internet", "One iPad downloads the event data, then AirDrops Export everything to the others, who use Import."),
        ("Spreadsheets", "The CSV exports open in Google Sheets or Excel."),
    ]
}
