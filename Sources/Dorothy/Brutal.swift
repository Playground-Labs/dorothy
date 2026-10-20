import SwiftUI
import CoreText

enum B {
    static let ink = Color(hex: "#111111")
    static let yellow = Color(hex: "#FFD60A")
    static let pink = Color(hex: "#FF4FA3")
    static let orange = Color(hex: "#FF7A1A")
    static let cobalt = Color(hex: "#2E5BFF")
    static let mint = Color(hex: "#22D39A")
    static let doneBG = Color(hex: "#F2F2F2")
    static let grey = Color(hex: "#555555")
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

/// Registers bundled TTFs; Font.custom falls back to the system font when they're missing (e.g. `swift run`).
func registerFonts() {
    guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
          let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
    for url in urls where url.pathExtension == "ttf" {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .custom("Archivo Black", size: size) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Space Grotesk", size: size).weight(weight) }
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size) }
}

// MARK: Motion

/// The one reduce-motion switch: in-app setting (UserDefaults "reduceMotion") OR the system setting.
var reduceMotion: Bool { UserDefaults.standard.bool(forKey: "reduceMotion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
/// Reduced → nil: layout changes snap; transitions fall back to plain opacity (see AnyTransition below).
func motion(_ a: Animation) -> Animation? { reduceMotion ? nil : a }
let springy = Animation.spring(response: 0.4, dampingFraction: 0.75)

/// Horizontal shake; bump `shakes` inside withAnimation to play it once.
struct Shake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat { get { shakes } set { shakes = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 4), y: 0))
    }
}

struct Tilt: ViewModifier {
    let degrees: Double
    func body(content: Content) -> some View { content.rotationEffect(.degrees(degrees)) }
}

extension AnyTransition {
    static var itemInsert: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .move(edge: .top)).combined(with: .opacity)
                .combined(with: .modifier(active: Tilt(degrees: -3), identity: Tilt(degrees: 0))),
            removal: .move(edge: .trailing).combined(with: .opacity))
    }
    static var pop: AnyTransition { reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity) }
}

// MARK: Boxes & buttons

extension View {
    func brutalBox(_ fill: Color = .white, border: CGFloat = 3, shadow: CGFloat = 5) -> some View {
        padding(border)
            .background(fill)
            .overlay(Rectangle().strokeBorder(B.ink, lineWidth: border))
            .background(B.ink.opacity(shadow > 0 ? 1 : 0).offset(x: shadow, y: shadow))
    }
    func dashedBorder() -> some View {
        overlay(Rectangle().strokeBorder(B.ink, style: StrokeStyle(lineWidth: 3, dash: [7, 4])))
    }
}

/// Hover lifts (shadow +2, offset -1); press squashes into the page (offset +shadow, shadow 0).
struct BrutalButtonStyle: ButtonStyle {
    var fill: Color = .white
    var shadow: CGFloat = 5
    var border: CGFloat = 3
    var radius: CGFloat = 0
    func makeBody(configuration: Configuration) -> some View { BrutalBody(configuration: configuration, style: self) }

    private struct BrutalBody: View {
        let configuration: Configuration
        let style: BrutalButtonStyle
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            let pressed = configuration.isPressed && !reduceMotion
            let lift = hover && enabled && !reduceMotion
            let s = pressed ? 0 : lift ? style.shadow + 2 : style.shadow
            let shift = pressed ? style.shadow : lift ? -1 : 0
            let shape = RoundedRectangle(cornerRadius: style.radius)
            configuration.label
                .padding(style.border)
                .background(shape.fill(style.fill))
                .overlay(shape.strokeBorder(B.ink, lineWidth: style.border))
                .background(shape.fill(B.ink).offset(x: s, y: s))
                .contentShape(shape)
                .offset(x: shift, y: shift)
                .onHover { hover = $0 }
                .animation(motion(.spring(response: 0.25, dampingFraction: 0.6)), value: pressed)
                .animation(motion(.spring(response: 0.25, dampingFraction: 0.6)), value: hover)
        }
    }
}

// MARK: Components

/// Uppercase, tracked Space Mono label.
struct Caps: View {
    let text: String
    var size: CGFloat = 11
    var bold = false
    var track: CGFloat = 0.12
    var color = B.ink
    init(_ text: String, size: CGFloat = 11, bold: Bool = false, track: CGFloat = 0.12, color: Color = B.ink) {
        self.text = text; self.size = size; self.bold = bold; self.track = track; self.color = color
    }
    var body: some View {
        Text(text.uppercased()).font(.mono(size, bold: bold)).tracking(size * track).foregroundColor(color).lineLimit(1)
    }
}

struct Swatch: View {
    let hex: String
    var size: CGFloat = 14
    var body: some View {
        Rectangle().fill(Color(hex: hex)).frame(width: size, height: size).overlay(Rectangle().strokeBorder(B.ink, lineWidth: 2))
    }
}

struct Checkbox: View {
    let on: Bool
    var size: CGFloat = 22
    var border: CGFloat = 3
    var body: some View {
        ZStack {
            Rectangle().fill(on ? B.mint : .white)
            Glyph(.check).trim(from: 0, to: on ? 1 : 0)
                .stroke(B.ink, style: StrokeStyle(lineWidth: border, lineCap: .square))
                .frame(width: size * 0.64, height: size * 0.64)
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().strokeBorder(B.ink, lineWidth: border))
        .animation(motion(.spring(response: 0.35, dampingFraction: 0.55)), value: on)
    }
}

struct ChipButton: View {
    let text: String
    let on: Bool
    var fill: Color = B.ink
    var fg: Color = B.ink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Caps(text, size: 10, bold: true, track: 0.06, color: on ? fg : B.ink)
                .padding(.vertical, 4).padding(.horizontal, 7)
        }
        .buttonStyle(BrutalButtonStyle(fill: on ? fill : .white, shadow: on ? 0 : 2, border: 2))
    }
}

/// Generic segmented toggle; selected black fill slides via matchedGeometryEffect.
struct Segmented<T: Hashable, L: View>: View {
    let options: [T]
    let selection: T
    let onSelect: (T) -> Void
    @ViewBuilder let label: (T, Bool) -> L
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { o in
                Button { withAnimation(motion(springy)) { onSelect(o) } } label: {
                    label(o, o == selection)
                        .background { if o == selection { B.ink.matchedGeometryEffect(id: "sel", in: ns) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .brutalBox(border: 3, shadow: 4)
    }
}

/// Brutal on/off switch: black knob slides, yellow when on.
struct BrutalSwitch: View {
    @Binding var on: Bool
    var body: some View {
        Button { withAnimation(motion(springy)) { on.toggle() } } label: {
            Rectangle().fill(B.ink).frame(width: 22, height: 20)
                .frame(width: 52, alignment: on ? .trailing : .leading)
                .padding(3)
                .brutalBox(on ? B.yellow : .white, shadow: 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Bars: View {
    let color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach([4.0, 8, 12], id: \.self) { Rectangle().fill(color).frame(width: 3, height: $0) }
        }
        .frame(width: 14, height: 14, alignment: .bottom)
    }
}

struct MicGlyph: View {
    var line: CGFloat = 2.5
    var body: some View {
        ZStack {
            Glyph(.micStand).stroke(B.ink, lineWidth: line)
            Glyph(.micBody).fill(.white)
            Glyph(.micBody).stroke(B.ink, lineWidth: line)
        }
    }
}

/// Icon paths from the Paper artboards (SVG viewBox coordinates, scaled to the frame).
struct Glyph: Shape {
    enum Kind { case collapse, expand, check, chevron, calendar, micBody, micStand, close, gear, minus, plus }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }

    func path(in r: CGRect) -> Path {
        var p = Path()
        var box = CGSize(width: 14, height: 14)
        func line(_ pts: [(CGFloat, CGFloat)]) { p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) }) }
        switch kind {
        case .collapse: line([(12.5, 1.5), (8, 6)]); line([(8, 2), (8, 6), (12, 6)]); line([(1.5, 12.5), (6, 8)]); line([(6, 12), (6, 8), (2, 8)])
        case .expand: line([(8, 1.5), (12.5, 1.5), (12.5, 6)]); line([(6, 12.5), (1.5, 12.5), (1.5, 8)]); line([(12.5, 1.5), (8, 6)]); line([(1.5, 12.5), (6, 8)])
        case .check: line([(2, 7.5), (5.5, 11), (12, 3)])
        case .chevron: box = CGSize(width: 12, height: 8); line([(1, 1.5), (6, 6.5), (11, 1.5)])
        case .calendar: p.addRect(CGRect(x: 1.25, y: 2.75, width: 11.5, height: 10)); line([(1.25, 6), (12.75, 6)]); line([(4.5, 1), (4.5, 4)]); line([(9.5, 1), (9.5, 4)])
        case .close: box = CGSize(width: 12, height: 12); line([(1.5, 1.5), (10.5, 10.5)]); line([(10.5, 1.5), (1.5, 10.5)])
        case .minus: box = CGSize(width: 12, height: 12); line([(1.5, 6), (10.5, 6)])
        case .plus: box = CGSize(width: 12, height: 12); line([(1.5, 6), (10.5, 6)]); line([(6, 1.5), (6, 10.5)])
        case .gear:
            p.addEllipse(in: CGRect(x: 4, y: 4, width: 6, height: 6))
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                line([(7 + 4.5 * cos(a), 7 + 4.5 * sin(a)), (7 + 6.5 * cos(a), 7 + 6.5 * sin(a))])
            }
        case .micBody: box = CGSize(width: 20, height: 24); p.addRoundedRect(in: CGRect(x: 6, y: 1.5, width: 8, height: 13), cornerSize: CGSize(width: 4, height: 4))
        case .micStand:
            box = CGSize(width: 20, height: 24)
            p.addArc(center: CGPoint(x: 10, y: 11), radius: 7.5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            line([(10, 18.5), (10, 22.5)])
        }
        return p.applying(CGAffineTransform(translationX: r.minX, y: r.minY).scaledBy(x: r.width / box.width, y: r.height / box.height))
    }
}

/// Hands the hosting NSWindow to a callback once the view is installed.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
