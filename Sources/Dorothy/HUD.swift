import AppKit
import SwiftUI

enum HUDState: Equatable { case listening, thinking, added(count: Int, list: String), failed(String) }

enum HUD {
    private static var panel: NSPanel?
    private static let model = HUDModel()
    private static var generation = 0
    private static let size = NSSize(width: 280, height: 140)  // room for shadow + pop-in overshoot
    private static let bottomInset: CGFloat = 24

    static func show(_ state: HUDState, level: @escaping () -> Float = { 0 }) {
        let p = panel ?? makePanel()
        if !p.isVisible || !model.visible {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let vf = screen?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 48 - bottomInset))
            }
            p.orderFrontRegardless()
        }
        model.level = level
        if state == .listening && (model.state != .listening || !model.visible) { model.since = Date() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            model.state = state
            model.visible = true
        }
        generation += 1
        switch state {
        case .added, .failed:
            let g = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if g == generation { hide() } }
        default: break
        }
    }

    static func hide() {
        generation += 1
        let g = generation
        withAnimation(.easeIn(duration: 0.18)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if g == generation { panel?.orderOut(nil) } }
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.contentView = NSHostingView(rootView: HUDView(model: model, bottomInset: bottomInset))
        panel = p
        return p
    }
}

private final class HUDModel: ObservableObject {
    @Published var state: HUDState = .listening
    @Published var visible = false
    var since = Date()
    var level: () -> Float = { 0 }
}

private func rgb(_ hex: UInt32) -> Color {
    Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

private let ink = B.ink

private func mono(_ size: CGFloat) -> Font {
    NSFontManager.shared.availableFontFamilies.contains("Space Mono")
        ? .custom("Space Mono", size: size).bold()
        : .system(size: size, weight: .bold, design: .monospaced)
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    let bottomInset: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.visible {
                pill.transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .offset(y: 20)).combined(with: .opacity),
                    removal: .scale(scale: 0.85).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, bottomInset)
    }

    private var pill: some View {
        HStack(spacing: 8) { content }
            .font(mono(11))
            .foregroundColor(onFill)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(width: 220, alignment: .leading)
            .frame(minHeight: 38)
            .background(background)
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 3))
            .background(ink.offset(x: 4, y: 4))
    }

    private var background: Color {
        switch model.state {
        case .listening: rgb(0xFFD60A)
        case .thinking: B.paper
        case .added: rgb(0x22D39A)
        case .failed: rgb(0xFF4FA3)
        }
    }

    /// Text on the accent fills stays dark ink; the paper (thinking) pill follows the theme.
    private var onFill: Color {
        if case .thinking = model.state { return B.ink }
        return B.onAccent
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .listening:
            Circle().fill(rgb(0xFF4FA3)).overlay(Circle().strokeBorder(B.onAccent, lineWidth: 2)).frame(width: 16, height: 16)
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let level = CGFloat(model.level())
                let s = max(0, Int(ctx.date.timeIntervalSince(model.since)))
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { i in
                            let wobble = reduceMotion ? 0.8 : 0.55 + 0.45 * abs(sin(t * 6 + Double(i) * 1.3))
                            Rectangle().fill(B.onAccent).frame(width: 3, height: 3 + 15 * level * wobble)
                        }
                    }
                    .frame(height: 18)
                    Spacer(minLength: 0)
                    Text(String(format: "%d:%02d", s / 60, s % 60))
                }
            }
        case .thinking:
            TimelineView(.animation(paused: reduceMotion)) { ctx in
                Rectangle().fill(rgb(0xFF7A1A)).overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(12 + (reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate * 45)))
            }
            .frame(width: 16, height: 16)
            Text("THINKING…").tracking(11 * 0.08)
        case let .added(count, list):
            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
            Text("+\(count) → \(list.uppercased())").tracking(11 * 0.08).lineLimit(1)
        case let .failed(message):
            Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
            Text(message).lineLimit(2)
        }
    }
}
