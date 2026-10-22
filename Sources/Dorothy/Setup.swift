import SwiftUI
import DorothyCore

/// Gets Ollama installed, running and Gemma pulled. Every step throws a readable error; nothing here crashes.
enum Ollama {
    static let download = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
    /// Ollama Inc's Developer ID team, read from the signature of the official download above (codesign -dv).
    static let teamID = "3MU9H2V9Y9"

    /// Download → unzip → verify signature + team → move to /Applications (or ~/Applications) → launch.
    /// Checks for cancellation between steps; a cancelled step's process is terminated.
    static func install(_ onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dorothy-ollama-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (zip, resp) = try await URLSession.shared.download(from: download, delegate: DownloadProgress(onProgress))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw SetupError("Couldn't download Ollama.") }
        try FileManager.default.moveItem(at: zip, to: tmp.appendingPathComponent("Ollama.zip"))

        try Task.checkCancellation()
        try await run("/usr/bin/ditto", ["-x", "-k", tmp.appendingPathComponent("Ollama.zip").path, tmp.path])
        let app = tmp.appendingPathComponent("Ollama.app")
        do {
            try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict",
                                                "-R=anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\"", app.path])
        } catch {
            try Task.checkCancellation()
            throw SetupError("Ollama's signature didn't check out, so Dorothy didn't install it.")
        }
        try Task.checkCancellation()

        let dir = FileManager.default.isWritableFile(atPath: "/Applications") ? "/Applications" : NSHomeDirectory() + "/Applications"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dest = URL(fileURLWithPath: dir).appendingPathComponent("Ollama.app")
        try FileManager.default.moveItem(at: app, to: dest)
        try Task.checkCancellation()
        try await NSWorkspace.shared.openApplication(at: dest, configuration: .init())
        try await waitForServer()
    }

    /// Ollama.app if present; else Homebrew's service; else a detached `ollama serve`.
    static func start() async throws {
        let fm = FileManager.default
        if let app = Gemma.ollamaApps.first(where: { fm.fileExists(atPath: $0) }) {
            try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app), configuration: .init())
        } else if let cli = Gemma.ollamaCLIs.first(where: { fm.fileExists(atPath: $0) }) {
            let brew = URL(fileURLWithPath: cli).deletingLastPathComponent().appendingPathComponent("brew").path
            let real = (try? fm.destinationOfSymbolicLink(atPath: cli)) ?? cli
            if real.contains("/Cellar/") && fm.fileExists(atPath: brew) {
                try await run(brew, ["services", "start", "ollama"])
            } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: cli)
                p.arguments = ["serve"]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try p.run()
            }
        } else {
            throw SetupError("Couldn't find Ollama.")
        }
        try await waitForServer()
    }

    private static func waitForServer() async throws {
        for _ in 0..<30 {
            if [.noModel, .ready].contains(await Gemma.setupState()) { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw SetupError("Ollama didn't start. Open it yourself, then try again.")
    }

    private static func run(_ path: String, _ args: [String]) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                p.terminationHandler = { p in
                    p.terminationStatus == 0 ? c.resume() : c.resume(throwing: SetupError("\((path as NSString).lastPathComponent) failed (\(p.terminationStatus))."))
                }
                do { try p.run() } catch { c.resume(throwing: error) }
            }
        } onCancel: { p.terminate() }
    }

    /// Reports the download task's fractionCompleted (off the main actor).
    private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let onProgress: @Sendable (Double) -> Void
        var observation: NSKeyValueObservation?
        init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }
        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            observation = task.progress.observe(\.fractionCompleted) { [onProgress] p, _ in onProgress(p.fractionCompleted) }
        }
    }
}

/// The one in-flight setup action. Owned by AppModel, so closing/reopening the dialog shows it and can't start a second.
@MainActor
final class SetupRun: ObservableObject {
    /// Step being worked on; the dialog shows this instead of the live state while running.
    @Published private(set) var step: GemmaSetup?
    @Published private(set) var progress: (text: String, fraction: Double?)?
    @Published var error: String?
    private var task: Task<Void, Never>?

    func start(_ s: GemmaSetup, refresh: @escaping @MainActor () async -> Void) {
        guard task == nil, s != .ready else { return }
        error = nil
        step = s
        task = Task {
            do {
                switch s {
                case .noOllama:
                    show("Downloading Ollama", 0)
                    try await Ollama.install { f in
                        Task { @MainActor in self.show(f < 1 ? "Downloading Ollama · \(Int(f * 100))%" : "Verifying & installing", f) }
                    }
                case .notRunning:
                    show("Starting Ollama", nil)
                    try await Ollama.start()
                case .noModel:
                    show("Connecting", nil)
                    try await Gemma.pull { t in self.show(Self.label(t), t.fraction) }
                case .ready: break
                }
            } catch {
                if !Task.isCancelled { withAnimation(motion(springy)) { self.error = error.localizedDescription } }
            }
            await refresh()
            withAnimation(motion(springy)) { progress = nil; step = nil }
            task = nil
        }
    }

    func cancel() { task?.cancel() }

    /// Never moves the bar backwards (download progress callbacks can arrive out of order).
    private func show(_ text: String, _ fraction: Double?) {
        guard task != nil || step != nil else { return }
        let f = fraction.map { max($0, progress?.fraction ?? 0) }
        withAnimation(motion(.easeOut(duration: 0.2))) { progress = (text, f) }
    }

    private static func label(_ t: PullTally) -> String {
        let gb = { (b: Double) in String(format: "%.1f", b / 1e9) }
        switch t.status {
        case "", "pulling manifest": return "Connecting"
        case let s where s.hasPrefix("pulling"): return "Downloading Gemma · \(gb(t.completedBytes)) / \(gb(t.totalBytes)) GB"
        case let s where s.hasPrefix("verifying"): return "Verifying"
        default: return "Finishing up"
        }
    }
}

/// Brutal card over the window: three checklist steps, one primary action for the current one.
struct SetupDialog: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var run: SetupRun
    private var busy: Bool { run.step != nil }
    private var state: GemmaSetup { run.step ?? m.setup }

    private var steps: Int {
        switch state { case .noOllama: 0; case .notRunning: 1; case .noModel: 2; case .ready: 3 }
    }

    private var copy: (title: String, detail: String, action: String) {
        switch state {
        case .noOllama: ("Install Ollama", "Gemma runs on your Mac through Ollama, a free app. Nothing you say leaves your computer.", "Download & install Ollama")
        case .notRunning: ("Start Ollama", "Ollama is installed but not running.", "Start Ollama")
        case .noModel: ("Download Gemma", "One-time download of \(Gemma.model). Grab a coffee.", "Download Gemma (~6.6 GB)")
        case .ready: ("Gemma's ready.", "Type or hold ⌃⌥D: dates and priorities sort themselves.", "Done")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Caps("Set up Gemma")
                Spacer()
                Button(action: close) {
                    Glyph(.close).stroke(B.ink, lineWidth: 2.5).frame(width: 10, height: 10).frame(width: 26, height: 26)
                }
                .buttonStyle(BrutalButtonStyle(shadow: 3, border: 2))
                .accessibilityLabel("Close setup")
            }
            Text(copy.title).font(.display(28)).tracking(-0.84)
            Text(copy.detail).font(.body(14)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(["Ollama installed", "Ollama running", "Gemma downloaded"].enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 10) {
                        Checkbox(on: steps > i, size: 16, border: 2)
                        Text(s).font(.body(14, steps == i ? .bold : .medium)).foregroundColor(steps > i ? B.grey : B.ink)
                    }
                }
            }
            if let p = run.progress {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { g in
                        Rectangle().fill(B.yellow).frame(width: g.size.width * (p.fraction ?? 0))
                            .overlay(alignment: .trailing) { if (p.fraction ?? 0) > 0 { B.ink.frame(width: 2) } }
                    }
                    .frame(height: 14)
                    .brutalBox(border: 2, shadow: 0)
                    Caps(p.text, size: 10, track: 0.06)
                }
                .transition(.opacity)
            }
            if let e = run.error {
                Text(e).font(.body(13, .semibold)).fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .brutalBox(B.pink, border: 2, shadow: 0)
                    .transition(.opacity)
            }
            (m.compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                Button { state == .ready ? close() : run.start(state) { await m.refreshSetup() } } label: {
                    Text(run.error != nil ? "Try again" : copy.action).font(.body(15, .bold)).fixedSize()
                        .foregroundColor(busy ? Color(hex: "#888888") : B.ink)
                        .padding(.vertical, 10).padding(.horizontal, 14)
                }
                .buttonStyle(BrutalButtonStyle(fill: busy ? Color(hex: "#E6E6E6") : state == .ready ? B.mint : B.yellow, shadow: busy ? 0 : 4))
                .disabled(busy)
                if state != .ready {
                    Button { busy ? run.cancel() : close() } label: {
                        Text(busy ? "Cancel" : "Not now").font(.body(15, .bold)).fixedSize().padding(.vertical, 10).padding(.horizontal, 14)
                    }
                    .buttonStyle(BrutalButtonStyle(shadow: 0))
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 440, alignment: .leading)
        .brutalBox(shadow: 8)
        .foregroundColor(B.ink)  // overlay sits outside RootView's ink; dark mode would turn text white
        .onChange(of: m.setup) { if !busy { run.error = nil } }
    }

    /// Hides only; an action in flight keeps going and shows again on reopen.
    private func close() { withAnimation(motion(springy)) { m.showSetup = false } }
}

