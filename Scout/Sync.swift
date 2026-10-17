import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Moving data between iPads without Wi-Fi: scouts show QR codes and the lead scans them
/// (the 1678 way), or AirDrop an export file.
struct DataView: View {
    @Environment(Store.self) private var store
    @AppStorage("scout") private var scout = ""
    @AppStorage("event") private var event = ""
    @AppStorage("tbaKey") private var tbaKey = ""
    @AppStorage("nexusKey") private var nexusKey = ""
    @AppStorage("ourTeam") private var ourTeam = 0
    @AppStorage("syncURL") private var syncURL = Fetch.defaultServer
    @AppStorage("syncCode") private var syncCode = ""
    @State private var syncingNow = false
    @AppStorage("eventName") private var eventName = ""
    @State private var choosing = false
    @State private var finding = false
    @State private var downloading = false
    @State private var downloadLog: [String] = []
    @State private var scanning = false
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        // One code per record: my matches and comparisons at this event, plus every pit record (newest wins on merge).
        let codes = store.db.matches
            .filter { $0.event == event && $0.scout == scout }
            .sorted { $0.match > $1.match }
            .map { ("Match \($0.match) · \($0.team)", Snapshot(matches: [$0])) }
            + store.db.rankings.filter { $0.event == event && $0.scout == scout }
                .map { ("Compare · match \($0.match)", Snapshot(rankings: [$0])) }
            + store.db.pits.map { ("Pit · \($0.team)", Snapshot(pits: [$0])) }
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $scout)
                    LabeledContent("Our team number") {
                        NumberField(title: "e.g. 1678", value: $ourTeam).multilineTextAlignment(.trailing)
                    }
                    Button { choosing = true } label: {
                        LabeledContent {
                            Text(event.isEmpty ? "Choose" : event).foregroundStyle(.secondary)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Event").foregroundStyle(Color.primary)
                                if !eventName.isEmpty { Text(eventName).font(.caption).foregroundStyle(Color.gray) }
                            }
                        }
                    }
                    Button(finding ? "Looking…" : "Find the event we're at", systemImage: "location.magnifyingglass") {
                        Task { await findMine() }
                    }
                    .disabled(finding || ourTeam == 0 || (tbaKey.isEmpty && syncCode.isEmpty))
                } header: {
                    Text("This iPad")
                } footer: {
                    Text("Find looks up your team on The Blue Alliance and picks the event happening today, or your next one. Choosing an event downloads every team, the schedule, OPR, EPA, and pit numbers. New records are tagged with your name and the event.")
                }

                Section {
                    Button(downloading ? "Downloading…" : "Refresh event data", systemImage: "arrow.down.circle") {
                        Task { await download() }
                    }
                    .disabled(downloading || event.isEmpty)
                    ForEach(downloadLog, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                    if let info = store.db.info, info.key == event, info.fetched > .distantPast {
                        LabeledContent("Last download", value: info.fetched.formatted(date: .abbreviated, time: .shortened))
                    }
                    SecureField("The Blue Alliance read API key", text: $tbaKey)
                    SecureField("Nexus API key (optional)", text: $nexusKey)
                } header: {
                    Text("The Blue Alliance, Statbotics & Nexus")
                } footer: {
                    Text("Get keys at [thebluealliance.com/account](https://www.thebluealliance.com/account) and [frc.nexus/api](https://frc.nexus/api). Statbotics EPA needs no key. Downloads are kept for offline use and ride along in Export everything, so scouts with no internet can import them. While the app is open it refreshes on its own: TBA and Statbotics every 5 minutes, and with a Nexus key, \"now queuing\" and alliance picks every minute.")
                }

                Section {
                    ShareLink(item: Slack.overview(db: store.db, event: event, eventName: eventName, ourTeam: ourTeam)) {
                        Label("Share event overview", systemImage: "text.bubble")
                    }
                } header: {
                    Text("Slack")
                } footer: {
                    Text("Top scorers, climbers, defense, red flags, our matches, and DNPs. Pick Slack in the share sheet. Match plans (Board), team pages, and the picklist have their own Share to Slack buttons.")
                }

                Section("Send to the lead scout") {
                    NavigationLink("Show my QR codes (\(codes.count))") {
                        QRPager(codes: codes)
                    }
                    .disabled(codes.isEmpty)
                    ShareLink(item: ExportFile(name: "FRC Scout \(event).json", data: store.db.encoded()),
                              preview: SharePreview("Everything (JSON)")) {
                        Label("Export everything (AirDrop to the lead)", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: ExportFile(name: "Matches \(event).csv", data: Data(csv(store.db.matches).utf8)),
                              preview: SharePreview("Matches (CSV)")) {
                        Label("Export matches for Sheets (CSV)", systemImage: "tablecells")
                    }
                    ShareLink(item: ExportFile(name: "Pits \(event).csv", data: Data(csv(store.db.pits).utf8)),
                              preview: SharePreview("Pit records (CSV)")) {
                        Label("Export pit records (CSV)", systemImage: "wrench.and.screwdriver")
                    }
                }

                Section {
                    SecureField("Team code", text: $syncCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(syncingNow ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task {
                            syncingNow = true
                            await store.runSync(server: syncURL, code: syncCode, event: event)
                            syncingNow = false
                        }
                    }
                    .disabled(syncingNow || syncCode.isEmpty || event.isEmpty)
                    if !store.syncStatus.isEmpty { Text(store.syncStatus).font(.callout).foregroundStyle(.secondary) }
                    NavigationLink {
                        PhoneSetup(link: phoneLink)
                    } label: {
                        Label("Set up a phone", systemImage: "iphone")
                    }
                    .disabled(syncCode.isEmpty || event.isEmpty)
                    TextField("Server", text: $syncURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Team sync")
                } footer: {
                    Text("With the team code, every iPad and phone shares this event's scouting automatically (every 20 seconds while the app is open), so each device can scout a different robot in the same match. Phones use the web app at [frc-scout-one.vercel.app](https://frc-scout-one.vercel.app). The team server also holds the TBA and Nexus keys, so devices without their own keys still get event data. Sync only adds and updates; it never deletes anything.")
                }

                Section("Collect from scouts") {
                    Button("Scan QR codes", systemImage: "qrcode.viewfinder") { scanning = true }
                    Button("Import an export file", systemImage: "square.and.arrow.down") { importing = true }
                    if let message { Text(message).foregroundStyle(.secondary) }
                }

                let events = Set(store.db.matches.map(\.event) + store.db.rankings.map(\.event)).filter { !$0.isEmpty }.sorted()
                if !events.isEmpty {
                    Section {
                        ForEach(events, id: \.self) { key in
                            Button {
                                Task { await choose(EventSummary(key: key, name: store.db.eventNames[key] ?? "")) }
                            } label: {
                                LabeledContent {
                                    Text(key == event ? "current" : "\(store.db.matches.filter { $0.event == key }.count) matches")
                                } label: {
                                    Text(store.db.eventNames[key] ?? key).foregroundStyle(Color.primary)
                                    Text(key).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(key == event)
                        }
                    } header: {
                        Text("Events on this iPad")
                    } footer: {
                        Text("Scouting from every competition stays here. Tap one to look at it again; nothing from other events is ever deleted. Team pages also show each team's notes from other events.")
                    }
                }

                if let gone = store.db.removed[event], !gone.isEmpty {
                    Section {
                        Text(gone.map(String.init).joined(separator: ", "))
                        Button("Put them back on the lists", systemImage: "arrow.uturn.backward") {
                            store.db.removed[event] = nil
                        }
                    } header: {
                        Text("Removed teams")
                    } footer: {
                        Text("Their deleted scouting data doesn't come back, but scanning a scout's QR codes again restores it.")
                    }
                }

                Section {
                    LabeledContent("Matches", value: "\(store.db.matches.count)")
                    LabeledContent("Pit records", value: "\(store.db.pits.count)")
                } header: {
                    Text("On this iPad")
                } footer: {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"). Updates arrive through SideStore.")
                }
            }
            .navigationTitle("Data")
            .toolbar { HelpButton(title: "Data", items: Help.data) }
            .sheet(isPresented: $choosing) {
                EventPicker(ourTeam: ourTeam, tbaKey: tbaKey, nexusKey: nexusKey) { picked in
                    Task { await choose(picked) }
                }
            }
            .sheet(isPresented: $scanning) {
                ScanSheet()
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let added = store.db.merge(try Snapshot.decode(Data(contentsOf: url)))
                    if added > 0 { UserDefaults.standard.set(true, forKey: "syncPushAll") }   // share imported records too
                    message = "Imported \(added) new or updated records."
                } catch {
                    message = "Couldn't read that file. Is it a FRC Scout export?"
                }
            }
        }
    }
}

extension DataView {
    /// Opens the web app already set up: team code, event, and team number ride after the #.
    private var phoneLink: String {
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "code", value: syncCode), URLQueryItem(name: "event", value: event),
                            URLQueryItem(name: "name", value: eventName), URLQueryItem(name: "team", value: String(ourTeam))]
        return syncURL + "/#" + (parts.percentEncodedQuery ?? "")
    }

    private func findMine() async {
        finding = true
        let (mine, _, errors) = await Fetch.events(team: ourTeam, tbaKey: tbaKey, nexusKey: "")
        if let current = Fetch.current(mine) {
            await choose(current)
        } else {
            downloadLog = errors.isEmpty ? ["No \(Calendar.current.component(.year, from: Date())) events found for team \(ourTeam)."] : errors
        }
        finding = false
    }

    private func choose(_ e: EventSummary) async {
        event = e.key
        eventName = e.name
        if !e.name.isEmpty { store.db.eventNames[e.key] = e.name }
        await download()
    }

    private func download() async {
        downloading = true
        let (info, log) = await Fetch.event(event, tbaKey: tbaKey, nexusKey: nexusKey, into: store.db.info)
        store.db.info = info
        downloadLog = log
        downloading = false
    }
}

/// This year's events to pick from, with your team's own on top.
struct EventPicker: View {
    let ourTeam: Int
    let tbaKey: String
    let nexusKey: String
    let onPick: (EventSummary) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mine: [EventSummary] = []
    @State private var all: [EventSummary] = []
    @State private var errors: [String] = []
    @State private var loading = true
    @State private var search = ""
    @State private var code = ""

    var body: some View {
        let today = Fetch.day(Date())
        let found = all.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || $0.key.localizedCaseInsensitiveContains(search) || $0.place.localizedCaseInsensitiveContains(search)
        }
        NavigationStack {
            List {
                if tbaKey.isEmpty && nexusKey.isEmpty {
                    Text("Add a TBA key in Data to browse events, or type the event code below.").foregroundStyle(.secondary)
                }
                ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red) }
                if !mine.isEmpty && search.isEmpty {
                    Section("Team \(ourTeam)") { ForEach(mine) { row($0, today: today) } }
                }
                if !found.isEmpty {
                    Section(search.isEmpty ? "All events" : "Results") { ForEach(found) { row($0, today: today) } }
                }
                Section("Not listed? Type the event code") {
                    HStack {
                        TextField("e.g. 2026camb", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Use") { pick(EventSummary(key: code.lowercased().trimmingCharacters(in: .whitespaces))) }
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .overlay { if loading { ProgressView("Loading events…") } }
            .searchable(text: $search, prompt: "Name, city, or code")
            .navigationTitle("Choose event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
            .task {
                (mine, all, errors) = await Fetch.events(team: ourTeam, tbaKey: tbaKey, nexusKey: nexusKey)
                loading = false
            }
        }
    }

    private func row(_ e: EventSummary, today: String) -> some View {
        Button { pick(e) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(e.name).font(.headline).foregroundStyle(Color.primary)
                    if e.start <= today && today <= e.end { pill("NOW", .green) }
                }
                Text([e.key, e.place, e.start == e.end ? e.start : "\(e.start) – \(e.end)"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func pick(_ e: EventSummary) {
        onPick(e)
        dismiss()
    }
}

/// A QR the iPhone camera opens straight into the web app, already set up.
struct PhoneSetup: View {
    let link: String

    var body: some View {
        VStack(spacing: 20) {
            if let image = QRCode.image(link) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .padding(20).background(.white)
                    .frame(maxWidth: 420)
                    .accessibilityLabel("Phone setup QR code")
            }
            Text("Open the Camera on the iPhone and point it at this code, then tap the link. FRC Scout opens with the team code, event, and team number filled in. Then: Share › Add to Home Screen.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text("Anyone with this code can read and add your team's scouting, so only show it to your team.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Set up a phone")
    }
}

struct ExportFile: Transferable {
    let name: String
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

struct QRCode: View {
    let snapshot: Snapshot

    var body: some View {
        if let image = Self.image(String(decoding: snapshot.encoded(), as: UTF8.self)) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(20)
                .background(.white)
                .accessibilityLabel("Scouting QR code")
        } else {
            ContentUnavailableView("Too much for one QR code", systemImage: "qrcode",
                description: Text("Shorten the notes, or use Export in Data."))
        }
    }

    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Shown right after saving, so the lead scout can scan it on the spot. Several records (a whole
/// alliance) get one code each; swipe between them.
struct QRSheet: View {
    let title: String
    let codes: [(String, Snapshot)]
    @Environment(\.dismiss) private var dismiss

    init(title: String, snapshot: Snapshot) { self.init(title: title, codes: [(title, snapshot)]) }

    init(title: String, codes: [(String, Snapshot)]) {
        self.title = title
        self.codes = codes
    }

    var body: some View {
        NavigationStack {
            Group {
                if codes.count == 1 {
                    QRCode(snapshot: codes[0].1).frame(maxWidth: 520).padding()
                } else {
                    QRPager(codes: codes)
                }
            }
            .navigationTitle("Saved: \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct QRPager: View {
    let codes: [(String, Snapshot)]

    var body: some View {
        TabView {
            ForEach(codes.indices, id: \.self) { i in
                VStack(spacing: 16) {
                    Text(codes[i].0).font(.title2.bold())
                    QRCode(snapshot: codes[i].1).frame(maxWidth: 520)
                    Text("\(i + 1) of \(codes.count) · swipe for the next").foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle("My QR codes")
    }
}

/// Point the camera at scouts' codes one after another; each new record is merged in as it's seen.
struct ScanSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var added = 0
    @State private var seen = Set<String>()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if let error {
                    ContentUnavailableView("Can't scan", systemImage: "camera", description: Text(error))
                } else if DataScannerViewController.isSupported {
                    QRScanner { code in
                        guard seen.insert(code).inserted else { return }
                        if let snapshot = try? Snapshot.decode(Data(code.utf8)) {
                            added += store.db.merge(snapshot)
                            UserDefaults.standard.set(true, forKey: "syncPushAll")   // share scanned records with the team too
                        }
                    } onError: { error = $0 }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Can't scan", systemImage: "camera",
                        description: Text("This iPad's camera can't scan QR codes."))
                }
                Text("\(added) new records · \(seen.count) codes scanned")
                    .font(.headline)
                    .padding()
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 30)
            }
            .navigationTitle("Scan scouts' codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerHost {
        let host = ScannerHost()
        host.scanner.delegate = context.coordinator
        host.onError = onError
        return host
    }

    func updateUIViewController(_ host: ScannerHost, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue { onCode(code) }
            }
        }
    }
}

/// Holds the scanner and starts it once it's on screen. Started any earlier (right after it's
/// created), the camera never comes up and the screen stays black.
final class ScannerHost: UIViewController {
    let scanner = DataScannerViewController(
        recognizedDataTypes: [.barcode(symbologies: [.qr])],
        qualityLevel: .accurate,
        recognizesMultipleItems: true,
        isHighlightingEnabled: true)
    var onError: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            try scanner.startScanning()
        } catch DataScannerViewController.ScanningUnavailable.cameraRestricted {
            onError?("Camera access is off. Turn it on in Settings › FRC Scout.")
        } catch {
            onError?("This iPad can't scan QR codes.")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }
}
