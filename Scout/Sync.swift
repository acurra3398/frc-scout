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
    @State private var downloading = false
    @State private var downloadLog: [String] = []
    @State private var scanning = false
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        // One code per record: mine at this event, plus every pit record (newest wins on merge).
        let codes = store.db.matches
            .filter { $0.event == event && $0.scout == scout }
            .sorted { $0.match > $1.match }
            .map { ("Match \($0.match) · \($0.team)", Snapshot(matches: [$0])) }
            + store.db.pits.map { ("Pit · \($0.team)", Snapshot(pits: [$0])) }
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $scout)
                    TextField("Event code, e.g. 2026camb", text: $event)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("This iPad")
                } footer: {
                    Text("New records are tagged with your name and the event. Teams and Picklist show the current event only.")
                }

                Section {
                    SecureField("The Blue Alliance read API key", text: $tbaKey)
                    SecureField("Nexus API key", text: $nexusKey)
                    Button(downloading ? "Downloading…" : "Download schedule, teams and OPRs", systemImage: "arrow.down.circle") {
                        Task { await download() }
                    }
                    .disabled(downloading || event.isEmpty || (tbaKey.isEmpty && nexusKey.isEmpty))
                    ForEach(downloadLog, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    if let info = store.db.info, info.key == event, info.fetched > .distantPast {
                        LabeledContent("Last download", value: info.fetched.formatted(date: .abbreviated, time: .shortened))
                    }
                } header: {
                    Text("The Blue Alliance & Nexus")
                } footer: {
                    Text("Get keys at [thebluealliance.com/account](https://www.thebluealliance.com/account) and [frc.nexus/api](https://frc.nexus/api). The event code is the TBA event key. Downloads are kept for offline use and ride along in Export everything, so scouts with no internet can import them. With a Nexus key, the schedule and \"now queuing\" refresh every minute while the app is open.")
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

                Section("Collect from scouts") {
                    Button("Scan QR codes", systemImage: "qrcode.viewfinder") { scanning = true }
                    Button("Import an export file", systemImage: "square.and.arrow.down") { importing = true }
                    if let message { Text(message).foregroundStyle(.secondary) }
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
            .sheet(isPresented: $scanning) {
                ScanSheet()
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let added = store.db.merge(try Snapshot.decode(Data(contentsOf: url)))
                    message = "Imported \(added) new or updated records."
                } catch {
                    message = "Couldn't read that file. Is it a FRC Scout export?"
                }
            }
        }
    }
}

extension DataView {
    private func download() async {
        downloading = true
        let (info, log) = await Fetch.event(event, tbaKey: tbaKey, nexusKey: nexusKey, into: store.db.info)
        store.db.info = info
        downloadLog = log
        downloading = false
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

/// Shown right after saving, so the lead scout can scan it on the spot.
struct QRSheet: View {
    let title: String
    let snapshot: Snapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRCode(snapshot: snapshot)
                .frame(maxWidth: 520)
                .padding()
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
