import SwiftUI

/// Pit scouting. Robustness follows the 1678 District Event readme rubric.
struct PitForm: View {
    @Environment(Store.self) private var store
    @State private var p = PitRecord()
    @State private var camera = false
    @State private var shared: PitRecord?
    @State private var photo: UIImage?

    static let rubric = [
        1: ("I expect this to fail on the field. Likely DNP. Bad in an unfixable way.",
            "Big loads on unsupported hex shafts, undersized structure, high-load live hex axles, no cross bracing.",
            "Rat's nest of wires, wires in motion paths or too short, no strain relief, no ferrules, poor connections."),
        2: ("Looks unreliable. Some reservations about picking. Bad in a potentially fixable way.",
            "Structure moves under load (could break in a big hit), undersized, missing, or loose fasteners, untensioned chains.",
            "Loose wires in risky areas, long unsecured wires, inconsistent connectors, no strain relief."),
        3: ("A normal robot. Can likely play elims with no incap.",
            "Some small cantilevered loads, supported structure, minimal superstructure wiggle, long chains tensioned.",
            "Routes thought out but untidy, zip ties hold things roughly in place, good practices with poor attention to detail."),
        4: ("Sturdy and well built. No work necessary.",
            "Sturdy structure, right-sized motion parts, hex shafts short or low-load, long spans are spline or large tube, chains tensioned.",
            "Tidy wiring with no obvious issues."),
        5: ("Appears indestructible. We could learn from them.",
            "Short load paths, large dead-axle pivots, rigid structure, oversized motion parts, tensioned belts and chains.",
            "Short secured wire runs, protected critical parts, soldered CAN, ferrules, hot-glued ethernet."),
    ]

    var body: some View {
        Form {
            Section {
                NumberField(title: "Team number", value: $p.team)
                    .font(.title2.bold())
                    .onChange(of: p.team) { _, team in
                        p = store.pit(team) ?? PitRecord(team: team)
                        photo = Photos.load(team)
                    }
            } footer: {
                let name = store.db.info?.names[String(p.team)]
                let pit = store.db.info?.pits[String(p.team)]
                Text([name, pit.map { "pit \($0)" }, store.pit(p.team) == nil ? nil : "already scouted, saving replaces it"]
                    .compactMap { $0 }.joined(separator: " · "))
            }

            Section("Robustness") {
                Picker("Rating", selection: $p.robustness) {
                    Text("–").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                if let level = Self.rubric[p.robustness] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(level.0).font(.headline)
                        Text("Mechanical: ").bold() + Text(level.1)
                        Text("Electrical: ").bold() + Text(level.2)
                    }
                    .font(.callout)
                }
            }

            Section("Robot") {
                Picker("Drivetrain", selection: $p.drivetrain) {
                    ForEach(["Swerve", "Tank", "Mecanum", "Other"], id: \.self) { Text($0) }
                }
                LabeledContent("Fuel it holds") {
                    NumberField(title: "0", value: $p.hopper).multilineTextAlignment(.trailing)
                }
                Toggle("Fits under the trench", isOn: $p.trench)
                Toggle("Drives over the bump", isOn: $p.bump)
                Toggle("Shoots while moving", isOn: $p.shootsOnMove)
                Picker("Highest climb", selection: $p.maxClimb) {
                    Text("None").tag(0)
                    ForEach(1...3, id: \.self) { Text("Level \($0)").tag($0) }
                }
                Toggle("Climbs in auto", isOn: $p.autoClimb)
            }

            Section("Photo") {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 320)
                }
                Button(photo == nil ? "Take photo" : "Retake photo", systemImage: "camera") { camera = true }
                    .disabled(p.team == 0)
            }

            Section("Notes") {
                TextField("Architecture, autos, anything odd…", text: $p.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Button("Save pit record") {
                    store.save(p)
                    shared = store.pit(p.team)
                    p = PitRecord()
                    photo = nil
                }
                .font(.headline)
                .disabled(p.team == 0)
            }
        }
        .navigationTitle("Pit scouting")
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                Photos.save(image, team: p.team)
                photo = Photos.load(p.team)
                camera = false
            } onCancel: { camera = false }
            .ignoresSafeArea()
        }
        .sheet(item: $shared) { pit in
            QRSheet(title: "Pit · \(pit.team)", snapshot: Snapshot(pits: [pit]))
        }
    }
}

/// Robot photos stay on the iPad that took them (too big for a QR code).
enum Photos {
    static func url(_ team: Int) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos/\(team).jpg")
    }

    static func save(_ image: UIImage, team: Int) {
        let url = url(team)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? image.jpeg()?.write(to: url, options: .atomic)
    }

    static func load(_ team: Int) -> UIImage? { UIImage(contentsOfFile: url(team).path) }
}

/// System camera; falls back to the photo library where there's no camera (the simulator).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) } else { parent.onCancel() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

extension UIImage {
    /// Shrinks the photo so a team's worth of robots doesn't fill the iPad.
    func jpeg(maxSide: CGFloat = 1600) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).jpegData(withCompressionQuality: 0.75) { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
