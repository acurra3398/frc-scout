import PencilKit
import SwiftUI

/// Strategy whiteboard: drag the six robots around the REBUILT field and draw routes with a
/// finger or Apple Pencil. Field art is WPILib's 2026 field image, cropped to the carpet.
struct BoardView: View {
    @Environment(Store.self) private var store
    @AppStorage("event") private var event = ""
    @AppStorage("ourTeam") private var ourTeam = 0
    @AppStorage("flipStations") private var flipStations = false
    @AppStorage("plannerCollapsed") private var plannerCollapsed = false
    @State private var canvas = PKCanvasView()
    @State private var robots = BoardView.start
    @State private var teams = Array(repeating: 0, count: 6)
    @State private var ink = Color.yellow
    @State private var erasing = false
    @State private var loaded = ""
    @Environment(\.horizontalSizeClass) private var hSize
    private var compact: Bool { hSize == .compact }   // iPhone
    /// Each driver-station column as a fraction of field length; wider on iPhone so team numbers fit.
    private var stationWidth: Double { compact ? 0.1 : 0.075 }

    /// Positions as fractions of the field (x: red wall → blue wall, y: top → bottom).
    static let start: [CGPoint] = [
        CGPoint(x: 0.21, y: 0.2), CGPoint(x: 0.21, y: 0.5), CGPoint(x: 0.21, y: 0.8),
        CGPoint(x: 0.79, y: 0.2), CGPoint(x: 0.79, y: 0.5), CGPoint(x: 0.79, y: 0.8),
    ]
    static let inks: [(String, Color)] = [("Yellow", .yellow), ("White", .white), ("Black", .black), ("Red", .red), ("Blue", .blue), ("Green", .green)]
    static let fieldAspect = 16.541 / 8.069       // meters, from WPILib's field JSON
    static let robotSize = 0.9 / 16.541           // ~0.9 m bumper-to-bumper, as a fraction of field length

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let size = CGSize(width: geo.size.width / (1 + 2 * stationWidth), height: geo.size.height)
                    HStack(spacing: 0) {
                    stations(red: true)
                    ZStack {
                        Image("Field").resizable()
                        DrawingCanvas(canvas: canvas)
                        ForEach(robots.indices, id: \.self) { i in
                            robot(i, side: size.width * Self.robotSize)
                                .gesture(DragGesture(coordinateSpace: .named("field")).onChanged { drag in
                                    robots[i] = CGPoint(x: min(max(drag.location.x / size.width, 0), 1),
                                                        y: min(max(drag.location.y / size.height, 0), 1))
                                })
                                .position(x: robots[i].x * size.width, y: robots[i].y * size.height)
                        }
                    }
                    .coordinateSpace(.named("field"))
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: size.width) { old, new in
                        // Keep drawn routes lined up with the field when the iPad rotates.
                        if old > 0 { canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(scaleX: new / old, y: new / old)) }
                    }
                    stations(red: false)
                    }
                }
                .aspectRatio(Self.fieldAspect * (1 + 2 * stationWidth), contentMode: .fit)

                // The field stays put; everything under it scrolls (the planner runs long on iPhone).
                ScrollView { VStack(spacing: 12) {

                (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))) {
                  HStack(spacing: compact ? 10 : 14) {
                    ForEach(Self.inks, id: \.0) { name, color in
                        Button { ink = color; erasing = false } label: {
                            Circle().fill(color)
                                .overlay(Circle().stroke(Color.primary, lineWidth: ink == color && !erasing ? 3 : 0.5))
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("\(name) pen")
                        .buttonStyle(.plain)
                    }
                    Button { erasing.toggle() } label: {
                        Image(systemName: erasing ? "eraser.fill" : "eraser").font(.title2)
                    }
                    .accessibilityLabel("Eraser")
                  }
                  if !compact { Spacer() }
                  HStack(spacing: 14) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        if !canvas.drawing.strokes.isEmpty { canvas.drawing.strokes.removeLast() }
                    }
                    Button("Clear", systemImage: "trash") { canvas.drawing = PKDrawing() }
                    Button("Reset robots", systemImage: "arrow.counterclockwise") {
                        withAnimation { robots = Self.start }
                    }
                    Button("Flip driver stations", systemImage: "arrow.up.arrow.down") { flipStations.toggle() }
                  }
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .font(.title3)

                HStack(spacing: 8) {
                    Menu("Load match") {
                        ForEach(store.db.info?.schedule ?? [], id: \.self) { m in
                            let ours = (m.red + m.blue).contains(ourTeam)
                            Button("\(ours ? "★ " : "")\(m.label): \((m.red + m.blue).map(String.init).joined(separator: " "))") { load(m) }
                        }
                    }
                    .disabled(store.db.info?.schedule.isEmpty ?? true)
                    Button("Our next match", systemImage: "star.fill") {
                        let scouted = store.db.matches.filter { $0.event == event }.map { Fetch.order($0.type, $0.match) }.max()
                        if let next = Fetch.nextMatch(for: ourTeam, in: store.db.info?.schedule ?? [],
                                                      queuing: store.db.info?.nowQueuing ?? "", lastScouted: scouted) {
                            load(next)
                        } else {
                            loaded = "No upcoming \(ourTeam) match in the schedule"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ourTeam == 0 || (store.db.info?.schedule.isEmpty ?? true))
                    Spacer()
                }
                .lineLimit(1)
                (compact ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                    ForEach([0, 3], id: \.self) { start in
                        HStack(spacing: 8) {
                            ForEach(start..<start + 3, id: \.self) { i in
                                NumberField(title: i < 3 ? "Red \(i + 1)" : "Blue \(i - 2)", value: $teams[i])
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: compact ? .infinity : 110)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(i < 3 ? Color.red : .blue, lineWidth: 2))
                            }
                        }
                        if start == 0 && !compact { Spacer() }
                    }
                }
                if teams.contains(where: { $0 > 0 }) { planner } else if !loaded.isEmpty { Text(loaded).foregroundStyle(.secondary) }
                } }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding()
            .navigationTitle("Strategy board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { HelpButton(title: "Strategy board", items: Help.board) }
            .onAppear(perform: setTool)
            .onChange(of: ink) { setTool() }
            .onChange(of: erasing) { setTool() }
        }
    }

    /// Match planner: each robot's numbers and a predicted score per alliance (scouted average
    /// when there is one, Statbotics EPA otherwise).
    private var planner: some View {
        let stats = Dictionary(uniqueKeysWithValues: store.db.stats(event: event).map { ($0.team, $0) })
        let title = loaded.isEmpty ? "Match plan" : loaded
        let total = { (red: Bool) in Int(teams[red ? 0..<3 : 3..<6].map { Slack.predicted(stats[$0]) }.reduce(0, +).rounded()) }
        return VStack(alignment: .leading, spacing: 10) {
          HStack {
            Button { withAnimation(.snappy) { plannerCollapsed.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down").font(.headline)
                        .rotationEffect(.degrees(plannerCollapsed ? -90 : 0))
                    Text(title).font(.title3.bold())
                    if plannerCollapsed {
                        Text("Red \(total(true))").font(.headline).foregroundStyle(Color.redAlliance)
                        Text("Blue \(total(false))").font(.headline).foregroundStyle(Color.blueAlliance)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(plannerCollapsed ? "Show match plan" : "Hide match plan")
            Spacer()
            ShareLink(item: Slack.match(title, red: Array(teams[0..<3]), blue: Array(teams[3..<6]), db: store.db, event: event)) {
                Label("Share to Slack", systemImage: "square.and.arrow.up")
            }
          }
          if !plannerCollapsed {
          (compact ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
            ForEach([true, false], id: \.self) { red in
                let alliance = Array(teams[red ? 0..<3 : 3..<6])
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(red ? "Red" : "Blue").font(.headline).foregroundStyle(Color.alliance(red))
                        Spacer()
                        Text("Predicted \(Int(alliance.map { Slack.predicted(stats[$0]) }.reduce(0, +).rounded()))")
                            .font(.headline).monospacedDigit()
                    }
                    ForEach(alliance.filter { $0 > 0 }, id: \.self) { team in
                        let s = stats[team]
                        let numbers = Text("\(f(s?.points)) pts · \((s?.liveEPA ?? 0) > 0 ? "live" : "EPA") \(f((s?.liveEPA ?? 0) > 0 ? s!.liveEPA : s?.epa ?? 0)) · tower \(f(s?.tower))")
                                .font(.caption.weight(.semibold)).monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 10) {
                                Text(verbatim: "\(team)").font(.headline).frame(width: 56, alignment: .leading)
                                if team == ourTeam { pill("US", .accentColor) }
                                Text(s?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                if !compact { numbers }
                                if let s { RobustBadge(value: Int(s.robustness)) }
                            }
                            if compact { numbers }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.alliance(red).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
          }
          }
        }
    }

    /// The alliance's three driver stations beside its wall. The manual puts each TOWER between
    /// Driver Stations 2 and 3, so red reads 1, 2, tower, 3 from the top and blue is the same turned
    /// around (the field is rotationally symmetric). Flip if your event's field is the other way.
    private func stations(red: Bool) -> some View {
        let topDown = red != flipStations ? [1, 2, 0, 3] : [3, 0, 2, 1]   // 0 = the tower
        return VStack(spacing: 4) {
            ForEach(topDown, id: \.self) { n in
                if n == 0 {
                    Text("TOWER").font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                        .frame(height: 16)
                        .accessibilityHidden(true)
                } else {
                    let team = teams[(red ? 0 : 3) + n - 1]
                    VStack(spacing: 2) {
                        Text(compact ? "\(red ? "R" : "B")\(n)" : red ? "RED \(n)" : "BLUE \(n)").font(.system(size: compact ? 9 : 10, weight: .heavy))
                        Text(team == 0 ? "–" : String(team)).font(.headline.weight(.heavy)).minimumScaleFactor(0.6).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.alliance(red), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(team != 0 && team == ourTeam ? Color.fuel : .clear, lineWidth: 3))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(red ? "Red" : "Blue") driver station \(n), \(team == 0 ? "empty" : "team \(team)")")
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func load(_ m: ScheduledMatch) {
        teams = (m.red + m.blue + [0, 0, 0, 0, 0, 0]).prefix(6).map { $0 }
        loaded = m.label
    }

    private func robot(_ i: Int, side: CGFloat) -> some View {
        let red = i < 3
        let label = teams[i] == 0 ? (red ? "R\(i + 1)" : "B\(i - 2)") : "\(teams[i])"
        return RoundedRectangle(cornerRadius: side * 0.18)
            .fill(red ? Color(red: 0.85, green: 0.1, blue: 0.1) : Color(red: 0.1, green: 0.25, blue: 0.9))
            .overlay(RoundedRectangle(cornerRadius: side * 0.18).stroke(.white, lineWidth: 2))
            .overlay(Text(label).font(.system(size: side * 0.34, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1).padding(2).foregroundStyle(.white))
            .frame(width: side, height: side)
            .contentShape(Rectangle().inset(by: -12))   // easier to grab than the robot itself
            .shadow(radius: 3)
            .accessibilityLabel("\(red ? "Red" : "Blue") robot \(label)")
    }

    private func setTool() {
        if erasing {
            canvas.tool = PKEraserTool(.vector)
        } else {
            canvas.tool = PKInkingTool(.pen, color: UIColor(ink), width: 6)
        }
    }
}

struct DrawingCanvas: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput          // finger or Pencil
        canvas.isScrollEnabled = false
        canvas.overrideUserInterfaceStyle = .light // PencilKit would otherwise invert ink colors in dark mode
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}
}
