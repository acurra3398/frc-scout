import PencilKit
import SwiftUI

/// Strategy whiteboard: drag the six robots around the REBUILT field and draw routes with a
/// finger or Apple Pencil. Field art is WPILib's 2026 field image, cropped to the carpet.
struct BoardView: View {
    @Environment(Store.self) private var store
    @State private var canvas = PKCanvasView()
    @State private var robots = BoardView.start
    @State private var teams = Array(repeating: 0, count: 6)
    @State private var ink = Color.yellow
    @State private var erasing = false

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
                    let size = geo.size
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
                    .onChange(of: size.width) { old, new in
                        // Keep drawn routes lined up with the field when the iPad rotates.
                        if old > 0 { canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(scaleX: new / old, y: new / old)) }
                    }
                }
                .aspectRatio(Self.fieldAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 14) {
                    ForEach(Self.inks, id: \.0) { name, color in
                        Button { ink = color; erasing = false } label: {
                            Circle().fill(color)
                                .overlay(Circle().stroke(Color.primary, lineWidth: ink == color && !erasing ? 3 : 0.5))
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("\(name) pen")
                    }
                    Button { erasing.toggle() } label: {
                        Image(systemName: erasing ? "eraser.fill" : "eraser").font(.title2)
                    }
                    .accessibilityLabel("Eraser")
                    Spacer()
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        if !canvas.drawing.strokes.isEmpty { canvas.drawing.strokes.removeLast() }
                    }
                    Button("Clear", systemImage: "trash") { canvas.drawing = PKDrawing() }
                    Button("Reset robots", systemImage: "arrow.counterclockwise") {
                        withAnimation { robots = Self.start }
                    }
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .font(.title3)

                HStack(spacing: 8) {
                    Menu("Load match") {
                        ForEach(store.db.info?.schedule ?? [], id: \.self) { m in
                            Button("\(m.label): \((m.red + m.blue).map(String.init).joined(separator: " "))") {
                                teams = (m.red + m.blue + [0, 0, 0, 0, 0, 0]).prefix(6).map { $0 }
                            }
                        }
                    }
                    .disabled(store.db.info?.schedule.isEmpty ?? true)
                    ForEach(0..<6, id: \.self) { i in
                        NumberField(title: i < 3 ? "Red \(i + 1)" : "Blue \(i - 2)", value: $teams[i])
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 110)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(i < 3 ? Color.red : .blue, lineWidth: 2))
                        if i == 2 { Spacer() }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Strategy board")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: setTool)
            .onChange(of: ink) { setTool() }
            .onChange(of: erasing) { setTool() }
        }
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
