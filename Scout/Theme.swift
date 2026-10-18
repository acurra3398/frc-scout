import SwiftUI

// FRC Scout's look: the icon's navy and FUEL yellow, rounded type, and cards on a grouped
// background. Each match phase has its own color so scouts always know where they are.

extension Color {
    static let fuel = Color(red: 0.96, green: 0.72, blue: 0.19)       // #F5B731, the icon's ball
    static let navy = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let redAlliance = Color(red: 0.85, green: 0.13, blue: 0.13)
    static let blueAlliance = Color(red: 0.12, green: 0.33, blue: 0.86)
    static let autoPhase = Color(red: 0.92, green: 0.35, blue: 0.05)   // orange-600
    static let telePhase = Color(red: 0.05, green: 0.58, blue: 0.53)   // teal-600
    static let endPhase = Color(red: 0.31, green: 0.27, blue: 0.90)    // indigo-600
    static let page = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let well = Color(.tertiarySystemFill)

    static func alliance(_ red: Bool) -> Color { red ? .redAlliance : .blueAlliance }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var color: Color = .accentColor
    var detail = ""
    var onClear: (() -> Void)?   // shows a Clear button that resets just this section

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.title3.bold())
            Spacer(minLength: 8)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            if let onClear {
                Button { withAnimation(.snappy) { onClear() } } label: {
                    Label("Clear", systemImage: "eraser").font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)
                .accessibilityLabel("Clear \(title)")
            }
        }
        .accessibilityElement(children: onClear == nil ? .combine : .contain)
    }
}

/// On/off capsule; faster to hit than a switch and readable from across the stands.
struct Chip: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var color: Color = .accentColor

    var body: some View {
        Button { isOn.toggle() } label: {
            Label(title, systemImage: isOn ? "checkmark.circle.fill" : systemImage)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? color : Color.well, in: Capsule())
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Big segmented choice; every option is a full-size button.
struct Choice<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var color: Color = .accentColor
    var base: Color = .well

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                Button { selection = value } label: {
                    Text(label)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selection == value ? Color.white : Color.primary)
                        .background(selection == value ? color : base,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(Pressable())
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Integer field that updates its binding on every keystroke (TextField(value:) waits for return).
struct NumberField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        TextField(title, text: Binding(
            get: { value == 0 ? "" : String(value) },
            set: { value = Int($0.filter(\.isNumber).prefix(5)) ?? 0 }))
        .keyboardType(.numberPad)
        .monospacedDigit()
    }
}

/// Big tap targets for counting while watching the field: -1, +1, +5, +10. Starts blank ("not
/// scored"); the first button reads 0 until something is recorded, and × clears it back to blank.
struct Counter: View {
    let title: String
    @Binding var value: Int?
    var steps = [1, 5, 10]
    var color: Color = .accentColor

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                if value != nil {
                    Button("Clear \(title)", systemImage: "xmark.circle.fill") { withAnimation(.snappy) { value = nil } }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let value {
                    Text("\(value)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(value)))
                } else {
                    Text("not scored").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                        .frame(height: 52)
                }
            }
            HStack(spacing: 8) {
                Button { withAnimation(.snappy) { value = max(0, (value ?? 1) - 1) } } label: {
                    Group {
                        if value == nil { Text("0").font(.title3.weight(.heavy)) } else { Image(systemName: "minus").font(.title3.bold()) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel(value == nil ? "\(title): none" : "Minus one \(title)")
                ForEach(steps, id: \.self) { step in
                    Button { withAnimation(.snappy) { value = (value ?? 0) + step } } label: {
                        Text("+\(step)")
                            .font(.title3.weight(.heavy))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white)
                            .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("Add \(step) \(title)")
                }
            }
            .buttonStyle(Pressable())
        }
        .sensoryFeedback(.increase, trigger: value)
    }
}

/// 1-5 rating; tapping the current value clears it back to 0 (not rated).
struct Rating: View {
    let title: String
    @Binding var value: Int
    var caption = ""
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button { value = value == n ? 0 : n } label: {
                        Text("\(n)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .foregroundStyle(value >= n ? Color.white : Color.primary)
                            .background(value >= n ? color.opacity(n == value ? 1 : 0.55) : Color.well,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel("\(title) \(n)")
                    .accessibilityAddTraits(value == n ? .isSelected : [])
                }
            }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.heavy)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Robustness 1-5 as a colored badge: red is risky, green is solid.
struct RobustBadge: View {
    let value: Int

    var body: some View {
        Text(value == 0 ? "–" : "\(value)")
            .font(.subheadline.weight(.heavy))
            .frame(minWidth: 28, minHeight: 24)
            .foregroundStyle(value == 0 ? Color.secondary : Color.white)
            .background(value == 0 ? Color.well : value <= 2 ? Color.redAlliance : value == 3 ? Color.orange : Color.green,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel(value == 0 ? "Not pit scouted" : "Robustness \(value) of 5")
    }
}

/// One robot's dots on the shot map.
struct ShotSeries {
    var shots: [[Double]]
    var color: Color = .fuel
    var label = ""               // drawn inside each dot so robots aren't told apart by color alone
}

/// The 2026 field with dots where robots shot from (normalized 0-1 points).
struct ShotField: View {
    let series: [ShotSeries]
    var onTap: ((CGPoint) -> Void)?

    init(shots: [[Double]], color: Color = .fuel, onTap: ((CGPoint) -> Void)? = nil) {
        series = [ShotSeries(shots: shots, color: color)]
        self.onTap = onTap
    }

    init(series: [ShotSeries], onTap: ((CGPoint) -> Void)? = nil) {
        self.series = series
        self.onTap = onTap
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Image("Field").resizable()
                ForEach(series.indices, id: \.self) { s in
                    ForEach(series[s].shots.indices, id: \.self) { i in
                        Circle()
                            .fill(series[s].color.opacity(onTap == nil ? 0.6 : 0.95))
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .overlay(Text(series[s].label).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white))
                            .frame(width: series[s].label.isEmpty ? 14 : 18, height: series[s].label.isEmpty ? 14 : 18)
                            .position(x: series[s].shots[i][0] * geo.size.width, y: series[s].shots[i][1] * geo.size.height)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                onTap?(CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height))
            }
        }
        .aspectRatio(16.541 / 8.069, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("\(series.map(\.shots.count).reduce(0, +)) shooting spots on the field")
    }
}

extension View {
    /// Asks before taking a team off the event: it leaves the lists and its data on this device is deleted.
    func confirmRemove(_ team: Binding<Int?>, store: Store, event: String, then done: @escaping () -> Void = {}) -> some View {
        confirmationDialog("Remove team \(team.wrappedValue.map(String.init) ?? "") from this event?",
                           isPresented: Binding(get: { team.wrappedValue != nil }, set: { if !$0 { team.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: team.wrappedValue) { t in
            Button("Remove " + String(t), role: .destructive) {
                store.remove(team: t, event: event)
                done()
            }
        } message: { _ in
            Text("It leaves this event's lists, and its match and pit data on this device is deleted. You can bring it back to the lists from Data.")
        }
    }
}

/// One decimal, or a dash for "no data" (EPA, OPR and the like use 0 for missing).
func f(_ x: Double) -> String { x == 0 ? "–" : String(format: "%.1f", x) }

/// Scouted numbers: a dash only when never scouted; a real 0 shows as 0.
func f(_ x: Double?) -> String { x.map { String(format: "%.1f", $0) } ?? "–" }

/// 0 means missing for TBA/Statbotics numbers.
func nz(_ x: Double) -> Double? { x == 0 ? nil : x }
