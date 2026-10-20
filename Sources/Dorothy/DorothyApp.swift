import SwiftUI
import DorothyCore

@main
struct DorothyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() { registerFonts() }
    var body: some Scene {
        // Single re-openable window; closing it leaves Dorothy running in the menu bar.
        Window("Dorothy", id: "main") {
            RootView().environmentObject(delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960 + 2 * windowMargin, height: 640 + 2 * windowMargin)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.applyDockPolicy(reactivate: false)
        menuBar = MenuBar(model: model)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.showMainWindow() }
        return true
    }
}

enum MicState { case idle, recording, thinking }

/// Transparent gap around the square app frame (holds our hard shadow, keeps clear of the system's rounded window mask).
/// Window frame = visible square + 2 × margin; 0 in full screen.
let windowMargin: CGFloat = 10
private let compactWindow = CGSize(width: 340 + 2 * windowMargin, height: 560 + 2 * windowMargin)

@MainActor
final class AppModel: ObservableObject {
    let store = Store()
    let recorder = Recorder()
    @Published private(set) var data: DorothyData
    @Published var selectedListID: UUID? { didSet { UserDefaults.standard.set(selectedListID?.uuidString, forKey: "selectedList") } }
    @Published var compact = UserDefaults.standard.bool(forKey: "compact") { didSet { UserDefaults.standard.set(compact, forKey: "compact") } }
    @Published var gemmaOnline = true
    @Published var mic = MicState.idle
    @Published var flash: Set<UUID> = []
    @Published var showSettings = false
    @Published var micPickerOpen = false
    @Published var fullScreen = false
    /// Banner text when the data file can't be read or written; edits fail loudly while set.
    @Published var dataError: (title: String, detail: String)?
    /// Short-lived inline message (e.g. mic permission) shown under the add bar.
    @Published var notice: String?
    private weak var window: NSWindow?
    /// Set by RootView (SwiftUI's openWindow); recreates the main window if it was closed.
    var openMain: (() -> Void)?
    /// Set by MenuBar; closes its drop-down / menu panel.
    var closeMenuBarPanel: (() -> Void)?
    private var hotKey: HotKey?
    private var watcher: AnyObject?
    private var hudRecording = false

    init() {
        data = DorothyData()
        selectedListID = UserDefaults.standard.string(forKey: "selectedList").flatMap(UUID.init(uuidString:))
        reload()
        watcher = store.watch { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        hotKey = HotKey(onPress: { [weak self] in MainActor.assumeIsolated { self?.startRecording(hud: true) } },
                        onRelease: { [weak self] in MainActor.assumeIsolated { self?.finishRecording(hud: true) } })
        Task {
            while true {
                setOnline(await Gemma.isReachable())
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    var currentList: TodoList? { data.lists.first { $0.id == selectedListID } ?? data.lists.first }

    // MARK: Data

    /// Re-reads the file. On failure keeps the last good data on screen and shows the error banner.
    private func reload() {
        do {
            let loaded = try store.load()
            dataError = nil
            // Zero lists (MCP / hand edit) would leave nowhere to type: re-seed an Inbox.
            if loaded.lists.isEmpty {
                mutate { if $0.lists.isEmpty { $0.lists = [TodoList(name: "Inbox", color: TodoList.palette[0])] } }
            } else {
                set(loaded)
            }
        } catch { report(error) }
    }

    private func report(_ error: Error) {
        dataError = error is Store.Corrupt ? ("Data file unreadable", store.url.path) : ("Couldn't save", error.localizedDescription)
    }

    /// Applies new data with a spring; ids that weren't there before flash yellow for 0.8 s.
    private func set(_ new: DorothyData) {
        guard new != data else { return }
        let ids = { (d: DorothyData) in Set(d.lists.flatMap { $0.items.map(\.id) }) }
        let added = ids(new).subtracting(ids(data))
        withAnimation(motion(springy)) { data = new }
        guard !added.isEmpty else { return }
        flash.formUnion(added)
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeOut(duration: 0.3)) { flash.subtract(added) }
        }
    }

    /// Every write goes through here; failures surface in the banner (the store never writes on error).
    @discardableResult
    func mutate(_ f: (inout DorothyData) -> Void) -> Bool {
        do {
            set(try store.mutate(f))
            dataError = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func updateList(_ id: UUID, _ f: (inout TodoList) -> Void) -> Bool {
        mutate { d in if let i = d.lists.firstIndex(where: { $0.id == id }) { f(&d.lists[i]) } }
    }

    func updateItem(_ listID: UUID, _ itemID: UUID, _ f: (inout Item) -> Void) {
        updateList(listID) { l in if let i = l.items.firstIndex(where: { $0.id == itemID }) { f(&l.items[i]) } }
    }

    func deleteItem(_ listID: UUID, _ itemID: UUID) { updateList(listID) { $0.items.removeAll { $0.id == itemID } } }

    /// false = a list with that name (case-insensitive) already exists; nothing written.
    func addList(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return true }
        var taken = false
        var list = TodoList(name: name, color: "")
        let ok = mutate { d in
            taken = d.lists.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            guard !taken else { return }
            list.color = TodoList.palette[d.lists.count % TodoList.palette.count]
            d.lists.append(list)
        }
        if ok && !taken { selectedListID = list.id }
        return !taken
    }

    func renameList(_ id: UUID, _ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return true }
        var taken = false
        mutate { d in
            taken = d.lists.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if !taken, let i = d.lists.firstIndex(where: { $0.id == id }) { d.lists[i].name = name }
        }
        return !taken
    }

    func deleteList(_ id: UUID) { mutate { $0.lists.removeAll { $0.id == id } } }

    func select(_ id: UUID) { selectedListID = id }

    func toggleSettings() { withAnimation(motion(springy)) { showSettings.toggle() } }

    func importLists(_ lists: [TodoList]) -> (lists: Int, items: Int) {
        var counts = (lists: 0, items: 0)
        mutate { counts = MarkdownIO.merge(lists, into: &$0) }
        return counts
    }

    func clearAllTasks() { mutate { d in for i in d.lists.indices { d.lists[i].items = [] } } }

    func clearAllLists() {
        mutate { $0.lists = [TodoList(name: "Inbox", color: TodoList.palette[0])] }
        selectedListID = data.lists.first?.id
    }

    private func setOnline(_ online: Bool) {
        if online != gemmaOnline { withAnimation(motion(springy)) { gemmaOnline = online } }
    }

    // MARK: Input

    /// Typed input: Gemma parses when online; otherwise (or if it yields nothing) the raw text becomes one item.
    /// Returns false only when nothing could be saved, so the caller keeps the text.
    func submit(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let list = currentList else { return false }
        if gemmaOnline {
            let showThinking = mic == .idle
            if showThinking { mic = .thinking }
            defer { if showThinking { mic = .idle } }
            do {
                let parsed = try await Gemma.parse(text: text, lists: data.lists.map(\.name))
                var added = 0
                guard mutate({ added = Gemma.apply(parsed, sourceText: text, defaultListID: list.id, to: &$0).count }) else { return false }
                if added > 0 { return true }
            } catch {
                if Self.isConnectionError(error) { setOnline(false) }
            }
        }
        return updateList(list.id) { $0.items.append(Item(title: text)) }
    }

    /// Only network failures mean "offline"; a reachable model replying with junk does not.
    static func isConnectionError(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        return [.cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost, .notConnectedToInternet].contains(e.code)
    }

    func flashNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if notice == text { notice = nil }
        }
    }

    func micTapped() { mic == .recording ? finishRecording(hud: false) : startRecording(hud: false) }

    func startRecording(hud: Bool) {
        guard mic == .idle else { return }
        do { try recorder.start() } catch {
            hud ? HUD.show(.failed(error.localizedDescription)) : flashNotice(error.localizedDescription)
            return
        }
        hudRecording = hud
        mic = .recording
        if hud { HUD.show(.listening, level: { [recorder] in recorder.level }) }
    }

    func finishRecording(hud: Bool) {
        guard mic == .recording, hud == hudRecording else { return }
        guard let wav = recorder.stop(), let list = currentList else {
            mic = .idle
            if hud { HUD.hide() }
            return
        }
        mic = .thinking
        if hud { HUD.show(.thinking) }
        Task {
            defer { mic = .idle }
            do {
                let r = try await Gemma.parse(audioWAV: wav, lists: data.lists.map(\.name))
                var result = (count: 0, list: list.name)
                let saved = mutate { result = Gemma.apply(r.items, sourceText: r.transcript, defaultListID: list.id, to: &$0) }
                let failure = !saved ? "Couldn't save" : result.count == 0 ? "No to-dos heard" : nil
                if let failure {
                    hud ? HUD.show(.failed(failure)) : flashNotice(failure)
                } else if hud {
                    HUD.show(.added(count: result.count, list: result.list))
                }
            } catch {
                let online = await Gemma.isReachable()
                setOnline(online)
                let failure = online ? "Couldn't parse that" : "Gemma offline"
                hud ? HUD.show(.failed(failure)) : flashNotice(failure)
            }
        }
    }

    // MARK: Window

    func showMainWindow(settings: Bool = false, full: Bool = false) {
        closeMenuBarPanel?()
        NSApp.activate()
        if let openMain { openMain() } else { window?.makeKeyAndOrderFront(nil) }
        if settings { withAnimation(motion(springy)) { showSettings = true } }
        if full && compact { DispatchQueue.main.async { self.toggleCompact() } }
    }

    func closeMainWindow() { window?.performClose(nil) }
    func minimizeMainWindow() { window?.miniaturize(nil) }
    /// Like the modern green button: full screen; option-click = classic zoom.
    func zoomMainWindow() {
        NSEvent.modifierFlags.contains(.option) ? window?.zoom(nil) : window?.toggleFullScreen(nil)
    }

    /// "Show in Dock" (UserDefaults "showInDock", default on): .regular vs .accessory (menu bar only).
    func applyDockPolicy(reactivate: Bool) {
        let show = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        // Dropping to .accessory deactivates the app; bring the window back to key.
        if reactivate { DispatchQueue.main.async { NSApp.activate(); self.window?.makeKeyAndOrderFront(nil) } }
    }

    func attach(_ w: NSWindow) {
        guard window !== w else { return }
        window = w
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        w.isMovableByWindowBackground = true
        w.titlebarAppearsTransparent = true
        // Pure square: no system background, rounded corners or shadow; RootView draws its own.
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        for (name, value) in [(NSWindow.willEnterFullScreenNotification, true), (NSWindow.willExitFullScreenNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fullScreen = value }
            }
        }
        if compact { resize(w, to: compactWindow, animate: false) }
    }

    func toggleCompact() {
        guard let w = window else { compact.toggle(); return }
        if compact {
            let saved = NSSizeFromString(UserDefaults.standard.string(forKey: "fullSize") ?? "")
            let full = saved.width >= 820 + 2 * windowMargin && saved.height >= 560 + 2 * windowMargin
                ? saved : CGSize(width: 960 + 2 * windowMargin, height: 640 + 2 * windowMargin)
            resize(w, to: full, animate: !reduceMotion)
            withAnimation(motion(.easeInOut(duration: 0.25))) { compact = false }
        } else {
            UserDefaults.standard.set(NSStringFromSize(w.frame.size), forKey: "fullSize")
            withAnimation(motion(.easeInOut(duration: 0.25))) { compact = true }
            DispatchQueue.main.async { self.resize(w, to: compactWindow, animate: !reduceMotion) }
        }
    }

    /// Keeps the top-left corner fixed. setFrame(animate:) runs synchronously.
    private func resize(_ w: NSWindow, to size: CGSize, animate: Bool) {
        var f = w.frame
        f.origin.y += f.height - size.height
        f.size = size
        w.setFrame(f, display: true, animate: animate)
    }
}
