import SwiftUI
import DorothyCore

/// Ollama status + next step. Shared by the first-open modal and Settings → Local model.
struct OllamaSetupPanel: View {
    @EnvironmentObject var m: AppModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch m.ollama {
            case .checking:
                status(nil, "Checking for Ollama…")
            case .notInstalled:
                status("#FF4FA3", "Ollama isn't installed")
                detail("Dorothy uses Ollama to run Gemma locally. Items are saved as typed until it's set up.")
                buttons { primary("Download Ollama") { m.downloadOllama() }; secondary("Check again") { m.refreshOllama() } }
            case .notRunning:
                status("#FF4FA3", "Ollama isn't running")
                detail("Start it to parse dates & priorities.")
                buttons { primary("Start Ollama") { m.startOllama() }; secondary("Check again") { m.refreshOllama() } }
            case .missingModel:
                status("#FFD60A", "Model \(Gemma.model) not downloaded (~9.5 GB)")
                if let p = m.pull {
                    progress(p)
                } else {
                    buttons { primary("Download model") { m.pullModel() }; secondary("Check again") { m.refreshOllama() } }
                }
            case .ready:
                status("#22D39A", "Ready: \(Gemma.model) running locally")
            }
            if let e = m.pullError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Swatch(hex: "#FF4FA3", size: 10)
                    Text(e).font(.body(13)).fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(_ hex: String?, _ text: String) -> some View {
        HStack(spacing: 8) {
            if let hex { Swatch(hex: hex, size: 12) }
            Text(text).font(.body(compact ? 14 : 15, .bold)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.body(13)).foregroundColor(B.muted).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func buttons<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 10) { content() }
        } else {
            HStack(spacing: 12) { content() }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Caps(title, size: 11, bold: true, track: 0.08, color: B.onAccent)
                .padding(.vertical, 9).padding(.horizontal, 12)
        }
        .buttonStyle(BrutalButtonStyle(fill: B.yellow, shadow: 3))
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Caps(title, size: 11, bold: true, track: 0.08)
                .padding(.vertical, 9).padding(.horizontal, 12)
        }
        .buttonStyle(BrutalButtonStyle(shadow: 3))
    }

    private func progress(_ p: OllamaSetup.PullProgress) -> some View {
        let label = p.fraction.map { "\(p.status) · \(Int($0 * 100))%" } ?? p.status
        return GeometryReader { g in
            let filled = g.size.width * (p.fraction ?? 0)
            let text = { (c: Color) in
                Caps(label, size: 10, bold: true, track: 0.06, color: c)
                    .padding(.horizontal, 8).frame(width: g.size.width, height: g.size.height, alignment: .leading)
            }
            ZStack(alignment: .leading) {
                B.paper
                text(B.ink)
                // The part of the label over the yellow fill uses B.onAccent (L1), so it reads in dark mode too.
                ZStack(alignment: .leading) { B.yellow; text(B.onAccent) }
                    .mask(alignment: .leading) { Rectangle().frame(width: filled) }
            }
        }
        .frame(height: 24)
        .brutalBox(border: 2, shadow: 0)
        .animation(motion(.easeOut(duration: 0.3)), value: p.fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Downloading model")
        .accessibilityValue(label)
    }
}

/// First-open card over a dimmed window. Overlay, not .sheet: the window has a hidden title bar and custom frame.
struct OllamaSetupModal: View {
    @EnvironmentObject var m: AppModel
    let compact: Bool

    var body: some View {
        ZStack {
            B.shadow.opacity(0.35).contentShape(Rectangle()).onTapGesture {}  // swallows clicks; Esc / Not now closes
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Caps("Local model")
                    Text("Set up local AI").font(.display(compact ? 24 : 32)).tracking(compact ? -0.7 : -0.96)
                }
                OllamaSetupPanel(compact: compact)
                HStack {
                    Spacer()
                    Button { m.dismissOllamaSetup() } label: {
                        Caps(m.ollama == .ready ? "Done" : "Not now", size: 11, bold: true, track: 0.08,
                             color: m.ollama == .ready ? B.onAccent : B.ink)
                            .padding(.vertical, 9).padding(.horizontal, 14)
                    }
                    .buttonStyle(BrutalButtonStyle(fill: m.ollama == .ready ? B.mint : B.paper, shadow: 3))
                }
            }
            .padding(compact ? 16 : 24)
            .frame(maxWidth: compact ? .infinity : 460)
            .brutalBox(B.paper, shadow: 6)
            .padding(.horizontal, compact ? 16 : 36)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}
