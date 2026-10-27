import SwiftUI
import UniformTypeIdentifiers
import DorothyCore

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow
    @Namespace private var ns
    var body: some View {
        ZStack {
            if m.compact {
                CompactView(ns: ns).transition(.opacity)
            } else {
                FullView(ns: ns).transition(.opacity)
            }
        }
        .frame(minWidth: m.compact ? 340 : 820, minHeight: 532)  // + 28pt hidden-titlebar safe area = 560 square
        .background(B.ground, ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(B.shadow, lineWidth: 3))
        .overlay(alignment: .topLeading) { WindowControls().padding(.leading, 17).padding(.top, 15).environment(\.colorScheme, .light) }  // sits on the yellow rail
        .background(B.shadow.opacity(m.fullScreen ? 0 : 1).offset(x: 6, y: 6))  // our hard shadow; the window has none
        .padding(m.fullScreen ? 0 : windowMargin)
        .ignoresSafeArea()
        .foregroundColor(B.ink)
        .background(WindowAccessor { m.attach($0) })
        .background {
            // Invisible key-equivalent buttons: ⌘, toggles settings, Esc closes them.
            Group {
                Button("") { m.toggleSettings() }.keyboardShortcut(",", modifiers: .command)
                // Main-menu equivalents, so ⌘Q/⌘W still work in menu-bar-only (.accessory) mode.
                Button("") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
                Button("") { m.closeMainWindow() }.keyboardShortcut("w", modifiers: .command)
                if m.showSettings {
                    Button("") {
                        if m.micPickerOpen { withAnimation(motion(springy)) { m.micPickerOpen = false } } else { m.toggleSettings() }
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .opacity(0)
        }
        .onAppear { m.openMain = { openWindow(id: "main") } }
    }
}

/// Brutalist stand-ins for the hidden traffic lights. Glyphs on group hover; all white when the window isn't key.
struct WindowControls: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.controlActiveState) private var state
    @State private var hover = false

    var body: some View {
        let key = state == .key
        HStack(spacing: 8) {
            control(.close, key ? B.pink : B.paper, "Close") { m.closeMainWindow() }
            control(.minus, B.paper, "Minimize") { m.minimizeMainWindow() }
            control(.plus, key ? B.mint : B.paper, "Full screen") { m.zoomMainWindow() }
        }
        .onHover { hover = $0 }
    }

    private func control(_ glyph: Glyph.Kind, _ fill: Color, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(glyph).stroke(state == .key && glyph != .minus ? B.onAccent : B.ink, lineWidth: 1.8).frame(width: 7, height: 7)
                .opacity(hover ? 1 : 0)
                .frame(width: 12, height: 12)
        }
        .buttonStyle(BrutalButtonStyle(fill: fill, shadow: 0, border: 2))
        .accessibilityLabel(label)
    }
}

// MARK: Full layout

struct FullView: View {
    @EnvironmentObject var m: AppModel
    let ns: Namespace.ID
    var body: some View {
        HStack(spacing: 0) {
            Rail(ns: ns).frame(width: 232)
            Rectangle().fill(B.shadow).frame(width: 3)
            if m.showSettings {
                SettingsView(compact: false).transition(.opacity)
            } else if let list = m.currentList {
                MainPane(list: list).transition(.opacity)
            } else {
                VStack(alignment: .leading) { Banners(compact: false); Spacer() }
                    .padding(.horizontal, 36).padding(.top, 40).padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct Rail: View {
    @EnvironmentObject var m: AppModel
    let ns: Namespace.ID
    @State private var adding = false
    @State private var newName = ""
    @State private var taken = false
    @State private var shakes: CGFloat = 0
    @State private var tabsHeight: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The pink dot is the wordmark's period: bottom on the text baseline, just after the "y".
            HStack(alignment: .lastTextBaseline, spacing: 1.5) {
                Text("Dorothy").font(.display(30)).tracking(-0.9)
                Circle().fill(B.pink).overlay(Circle().strokeBorder(B.onAccent, lineWidth: 2)).frame(width: 9.5, height: 9.5)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            }
            .padding(.bottom, 10)
            Caps("Lists", color: B.onAccent)
            // Tabs scroll (no visible scroller); capped at content height so "+ New list" sits right below them.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(m.data.lists) { ListTab(list: $0, ns: ns) }
                }
                .padding(.trailing, 6).padding(.bottom, 6)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { tabsHeight = $0 }
            }
            .frame(maxHeight: tabsHeight)
            .padding(.trailing, -6)
            newList
            if taken { Caps("That name's taken", size: 10, bold: true, track: 0.06, color: B.onAccent).transition(.opacity) }
            Spacer(minLength: 0)
            Button { m.toggleSettings() } label: {
                HStack(spacing: 6) {
                    Glyph(.gear).stroke(m.showSettings ? B.onInk : B.ink, lineWidth: 2).frame(width: 14, height: 14)
                    Caps("Settings", size: 10, bold: true, track: 0.08, color: m.showSettings ? B.onInk : B.ink)
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
            }
            .buttonStyle(BrutalButtonStyle(fill: m.showSettings ? B.inkFill : B.paper, shadow: 3, border: 2))
            HStack(spacing: 8) {
                Circle().fill(m.gemmaOnline ? B.mint : B.pink).overlay(Circle().strokeBorder(B.onAccent, lineWidth: 2)).frame(width: 10, height: 10)
                Caps(m.gemmaOnline ? "Gemma 4 · E4B · Local" : "Offline", track: 0.08, color: B.onAccent)
            }
        }
        .padding(.horizontal, 20).padding(.top, 44).padding(.bottom, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundColor(B.onAccent)  // the rail stays yellow, so its text stays dark ink
        .background(B.yellow, ignoresSafeAreaEdges: [])  // don't bleed into the transparent window margin
        .environment(\.colorScheme, .light)  // the yellow rail looks the same in both themes
    }

    @ViewBuilder private var newList: some View {
        Group {
            if adding {
                TextField("List name", text: $newName)
                    .textFieldStyle(.plain).font(.body(14, .bold)).focused($focused)
                    .onAppear { DispatchQueue.main.async { focused = true } }
                    .onSubmit {
                        if m.addList(newName) { adding = false; taken = false }
                        else { taken = true; withAnimation(motion(.linear(duration: 0.4))) { shakes += 1 } }
                    }
                    .onExitCommand { adding = false; taken = false }
                    .onChange(of: focused) { _, f in if !f { adding = false; taken = false } }
                    .onChange(of: newName) { taken = false }
            } else {
                Button { newName = ""; adding = true } label: {
                    Text("+ New list").font(.body(14, .bold)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 18)
        .padding(.vertical, 10).padding(.horizontal, 12)
        .padding(3)
        .dashedBorder(B.onAccent)
        .modifier(Shake(shakes: shakes))
    }
}

struct ListTab: View {
    @EnvironmentObject var m: AppModel
    let list: TodoList
    let ns: Namespace.ID
    @State private var hover = false
    @State private var confirm = false
    private var active: Bool { m.currentList?.id == list.id }

    var body: some View {
        HStack(spacing: 10) {
            Button { m.select(list.id); if m.showSettings { m.toggleSettings() } } label: {
                HStack(spacing: 10) {
                    Swatch(hex: list.color)
                    if active {
                        Text(list.name).font(.body(15, .bold)).lineLimit(1).matchedGeometryEffect(id: "title", in: ns)
                    } else {
                        Text(list.name).font(.body(15, .medium)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(list.name), \(list.items.filter { !$0.done }.count) open")
            .accessibilityAddTraits(active ? .isSelected : [])
            if hover && m.data.lists.count > 1 {
                Button { confirm ? m.deleteList(list.id) : (confirm = true) } label: {
                    Caps(confirm ? "Sure?" : "×", size: confirm ? 10 : 14, bold: true, track: 0.04, color: active && !confirm ? B.ink : B.onAccent)
                        .padding(.horizontal, 4)
                        .background(confirm ? B.pink : .clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(confirm ? "Confirm delete \(list.name)" : "Delete \(list.name)")
            } else {
                Text("\(list.items.filter { !$0.done }.count)").font(.mono(12, bold: active)).accessibilityHidden(true)
            }
        }
        .frame(height: 20)
        .padding(.vertical, 10).padding(.horizontal, 12)
        .padding(3)
        .foregroundColor(active ? B.ink : B.onAccent)
        .background(active ? B.paper : .clear)
        .overlay(Rectangle().strokeBorder(active ? B.onAccent : .clear, lineWidth: 3))
        .background(B.onAccent.opacity(active ? 1 : 0).offset(x: 5, y: 5))
        .contentShape(Rectangle())
        .offset(x: hover && !reduceMotion ? 2 : 0)
        .onHover { hover = $0; if !$0 { confirm = false } }
        .animation(motion(springy), value: active)
        .animation(motion(.spring(response: 0.3, dampingFraction: 0.7)), value: hover)
    }
}

struct MainPane: View {
    @EnvironmentObject var m: AppModel
    let list: TodoList
    @State private var renaming = false
    @State private var draft = ""
    @State private var taken = false
    @State private var shakes: CGFloat = 0
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if m.dataError != nil || !m.gemmaOnline { Banners(compact: false).transition(.opacity) }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Caps(taken ? "That name's taken" : dateLine(list), bold: taken)
                    title
                }
                Spacer(minLength: 0)
                GroupToggle(list: list, compact: false)
                Button { m.toggleCompact() } label: {
                    Glyph(.collapse).stroke(B.ink, lineWidth: 2.2).frame(width: 14, height: 14).frame(width: 32, height: 32)
                }
                .buttonStyle(BrutalButtonStyle(shadow: 4))
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .accessibilityLabel("Compact view")
            }
            // 8pt scroll inset + 10 = the 18pt gap between groups.
            VStack(alignment: .leading, spacing: 10) {
                ItemsView(list: list, compact: false)
                VStack(alignment: .leading, spacing: 6) {
                    QuickAdd(compact: false)
                    if let n = m.notice { NoticeLine(text: n) } else { Caps("Hold ⌃⌥D anywhere to talk", track: 0.06) }
                }
            }
        }
        .padding(.horizontal, 36).padding(.top, 40).padding(.bottom, 14)
        .onChange(of: list.id) { renaming = false; taken = false }
    }

    @ViewBuilder private var title: some View {
        if renaming {
            TextField("", text: $draft).textFieldStyle(.plain).font(.display(44)).focused($nameFocused)
                .onAppear { DispatchQueue.main.async { nameFocused = true } }
                .onSubmit { commitRename(blur: false) }
                .onExitCommand { renaming = false; taken = false }
                .onChange(of: nameFocused) { _, f in if !f { commitRename(blur: true) } }
                .onChange(of: draft) { taken = false }
                .modifier(Shake(shakes: shakes))
        } else {
            Text(list.name).font(.display(44)).tracking(-1.32).lineLimit(1)
                .onTapGesture(count: 2) { draft = list.name; renaming = true }
        }
    }

    /// Duplicate name: on Enter stay in the field and shake; on blur give up and say why.
    private func commitRename(blur: Bool) {
        guard renaming else { return }
        if m.renameList(list.id, draft) {
            renaming = false
        } else if blur {
            m.flashNotice("That name's taken")
            renaming = false
        } else {
            taken = true
            withAnimation(motion(.linear(duration: 0.4))) { shakes += 1 }
            return
        }
        taken = false
    }
}

func dateLine(_ list: TodoList) -> String {
    if list.items.isEmpty { return "Nothing here yet" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "EEEE d MMM"
    return "\(f.string(from: Date())) · \(list.items.filter { !$0.done }.count) open"
}

/// Pink banners: unreadable/unsaveable data file, then Gemma offline.
struct Banners: View {
    @EnvironmentObject var m: AppModel
    let compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if let e = m.dataError { banner(e.title, e.detail) }
            if !m.gemmaOnline {
                banner("Gemma offline", compact ? "Saved as typed." : "Items are saved as typed. Start Ollama to parse dates & priorities.")
            }
        }
    }

    private func banner(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Caps(title, size: compact ? 10 : 11, bold: true, track: 0.1, color: B.onAccent).fixedSize()
            Text(detail).font(.body(compact ? 12 : 14)).foregroundColor(B.onAccent).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, compact ? 6 : 10).padding(.horizontal, compact ? 10 : 14)
        .brutalBox(B.pink, border: compact ? 2 : 3, shadow: 0)
        .accessibilityElement(children: .combine)
    }
}

struct NoticeLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Swatch(hex: "#FF4FA3", size: 10)
            Caps(text, bold: true, track: 0.06)
        }
        .transition(.opacity)
    }
}

struct GroupToggle: View {
    @EnvironmentObject var m: AppModel
    let list: TodoList
    let compact: Bool
    var body: some View {
        Segmented(options: [GroupBy.priority, .deadline], selection: list.groupBy,
                  onSelect: { g in m.updateList(list.id) { $0.groupBy = g } }) { g, on in
            if compact {
                Group {
                    if g == .priority { Bars(color: on ? B.onInk : B.ink) }
                    else { Glyph(.calendar).stroke(on ? B.onInk : B.ink, lineWidth: 2).frame(width: 14, height: 14) }
                }
                .frame(width: 28, height: 28)
                .accessibilityLabel("Group by \(g.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
            } else {
                Caps(g.rawValue, size: 12, bold: true, track: 0.06, color: on ? B.onInk : B.ink)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .accessibilityLabel("Group by \(g.rawValue)")
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: Items

struct ItemsView: View {
    @EnvironmentObject var m: AppModel
    let list: TodoList
    let compact: Bool
    @State private var expanded: UUID?

    private enum Entry: Identifiable {
        case header(String, Int), item(Item)
        var id: String {
            switch self {
            case .header(let t, _): "h-" + t
            case .item(let i): i.id.uuidString
            }
        }
    }

    private var entries: [Entry] {
        groups(list.items, by: list.groupBy).enumerated().flatMap { i, g in [Entry.header(g.title, i)] + g.items.map(Entry.item) }
    }

    var body: some View {
        Group {
            if list.items.isEmpty {
                EmptyCard(compact: compact).transition(.opacity)
            } else {
                scroller
            }
        }
        .onChange(of: list.id) { expanded = nil }
    }

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                    ForEach(entries) { e in
                        switch e {
                        case .header(let title, let i):
                            GroupHeader(title: title, index: i, compact: compact)
                                .padding(.top, i == 0 ? 0 : compact ? 6 : 8)
                                .transition(.pop)
                        case .item(let item):
                            ItemRow(item: item, listID: list.id, compact: compact, expanded: $expanded)
                                .transition(.itemInsert)
                        }
                    }
                }
                .padding(.top, 4).padding(.bottom, 8).padding(.trailing, 6)
            }
            .padding(.trailing, -6)
            // Newly added items scroll into view so the yellow flash is seen.
            .onChange(of: m.flash) { old, new in
                if let id = list.items.first(where: { new.subtracting(old).contains($0.id) })?.id {
                    withAnimation(motion(springy)) { proxy.scrollTo(id.uuidString, anchor: .center) }
                }
            }
        }
    }
}

struct GroupHeader: View {
    let title: String
    let index: Int
    let compact: Bool
    @State private var wiggles = 0
    var body: some View {
        let (fill, fg, tilt): (Color, Color, Double) = switch title {
        case "High", "Danger zone": (B.pink, B.onAccent, -2)
        case "Data": (B.inkFill, B.onInk, 1.5)
        case "Medium": (B.orange, B.onAccent, 1.5)
        case "Low": (B.cobalt, .white, -1)
        default: (B.paper, B.ink, index.isMultiple(of: 2) ? -1.5 : 1)
        }
        HStack(spacing: compact ? 8 : 10) {
            Caps(title, size: compact ? 10 : 11, bold: true, track: 0.1, color: fg)
                .padding(.vertical, compact ? 2 : 3).padding(.horizontal, compact ? 6 : 8)
                .brutalBox(fill, border: 2, shadow: 0)
                .phaseAnimator([0.0, 1, -1, 0], trigger: wiggles) { chip, wobble in chip.rotationEffect(.degrees(tilt + wobble)) }
                .onHover { if $0 && !reduceMotion { wiggles += 1 } }
            Rectangle().fill(B.ink).frame(height: compact ? 2 : 3)
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject var m: AppModel
    let item: Item
    let listID: UUID
    let compact: Bool
    @Binding var expanded: UUID?
    @State private var draft = ""
    @State private var base = ""  // title when editing began; only a changed draft is written back
    @State private var notesDraft = ""
    @State private var confirmDelete = false
    @State private var hover = false
    @FocusState private var focused: Bool
    private var open: Bool { expanded == item.id }
    private var lift: Bool { hover && !item.done && !reduceMotion }
    private var revealed: Bool { m.revealedItem == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(spacing: compact ? 10 : 14) {
                Button { m.updateItem(listID, item.id) { $0.done.toggle() } } label: {
                    Checkbox(on: item.done, size: compact ? 16 : 22, border: compact ? 2 : 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.done ? "Mark \(item.title) not done" : "Mark \(item.title) done")
                if open {
                    TextField("", text: $draft).textFieldStyle(.plain)
                        .font(.body(compact ? 14 : 16, .semibold)).focused($focused)
                        .onAppear { DispatchQueue.main.async { focused = true } }
                        .onSubmit { expanded = nil }
                        .onExitCommand { draft = base; expanded = nil }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body(compact ? 14 : 16, item.done ? .medium : .semibold))
                            .strikethrough(item.done)
                            .foregroundColor(item.done ? B.grey : m.flash.contains(item.id) ? B.onAccent : B.ink)
                        if let notes = item.notes {
                            Text(notes).font(.body(compact ? 11 : 13)).foregroundColor(m.flash.contains(item.id) ? B.onAccent : B.grey).lineLimit(compact ? 1 : 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if !item.done, let d = item.deadline { DeadlineChip(date: d, compact: compact) }
                }
                .frame(width: compact ? 56 : 96)
            }
            if open { editor.transition(.opacity) }
        }
        .padding(.vertical, compact ? 8 : 12).padding(.horizontal, compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DeleteReveal(shown: revealed, compact: compact) { m.revealedItem = nil; m.deleteItem(listID, item.id) })
        .brutalBox(m.flash.contains(item.id) ? B.yellow : item.done ? B.doneBG : B.paper,
                   border: compact ? 2 : 3, shadow: item.done ? 0 : (compact ? 3 : 5) + (lift ? 1 : 0))
        .offset(x: lift ? -1 : 0, y: lift ? -1 : 0)
        .onHover { hover = $0 }
        .animation(motion(.spring(response: 0.3, dampingFraction: 0.7)), value: lift)
        .contentShape(Rectangle())
        .overlay(RightClickCatcher { m.toggleReveal(item.id) })
        .accessibilityAction(named: "Delete") { m.deleteItem(listID, item.id) }
        .onTapGesture {
            if m.revealedItem != nil { withAnimation(motion(springy)) { m.revealedItem = nil }; return }  // click just dismisses a reveal
            guard !open else { return }
            draft = item.title
            base = item.title
            notesDraft = item.notes ?? ""
            confirmDelete = false
            withAnimation(motion(springy)) { expanded = item.id }
        }
        .onChange(of: open) { _, isOpen in if !isOpen { commit() } }
        .onChange(of: item.title) { _, t in if draft == base { draft = t; base = t } }  // external rename while editing
        .onChange(of: item.notes) { old, new in if notesDraft == (old ?? "") { notesDraft = new ?? "" } }
        .onDisappear { if open { commit() } }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caps("Notes", size: 10)
                Spacer(minLength: 0)
                Caps("\(notesDraft.count)/\(Item.notesLimit)", size: 9)
            }
            TextField("Add a note…", text: $notesDraft, axis: .vertical).textFieldStyle(.plain)
                .font(.body(compact ? 12 : 14)).lineLimit(1...4)
                .padding(.vertical, 4).padding(.horizontal, 7)
                .brutalBox(border: 2, shadow: 0)
                .onChange(of: notesDraft) { _, v in
                    if v.count > Item.notesLimit { notesDraft = String(v.prefix(Item.notesLimit)) }
                }
            Caps("Priority", size: 10)
            HStack(spacing: 6) {
                ForEach(Priority.allCases, id: \.self) { p in
                    let (name, fill, fg): (String, Color, Color) = switch p {
                    case .high: ("High", B.pink, B.onAccent)
                    case .medium: ("Med", B.orange, B.onAccent)
                    case .low: ("Low", B.cobalt, .white)
                    case .none: ("None", B.ink, B.paper)
                    }
                    ChipButton(text: name, on: item.priority == p, fill: fill, fg: fg) { m.updateItem(listID, item.id) { $0.priority = p } }
                }
            }
            Caps("Deadline", size: 10)
            HStack(spacing: 6) {
                ForEach(deadlinePresets(), id: \.0) { name, date in
                    ChipButton(text: name, on: item.deadline == date, fill: B.inkFill, fg: B.onInk) { m.updateItem(listID, item.id) { $0.deadline = date } }
                }
                Spacer(minLength: 0)
                Button { confirmDelete ? m.deleteItem(listID, item.id) : (confirmDelete = true) } label: {
                    Caps(confirmDelete ? "Sure?" : "Delete", size: 10, bold: true, track: 0.06, color: confirmDelete ? B.onAccent : B.ink)
                        .padding(.vertical, 4).padding(.horizontal, 7)
                }
                .buttonStyle(BrutalButtonStyle(fill: confirmDelete ? B.pink : B.paper, shadow: 2, border: 2))
            }
        }
        .padding(.leading, compact ? 26 : 36)
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, draft != base, t != item.title { m.updateItem(listID, item.id) { $0.title = t } }
        let n = Item.normalizedNotes(notesDraft)
        if n != item.notes { m.updateItem(listID, item.id) { $0.notes = n } }
    }
}

/// Deadlines are UTC-midnight day stamps (DorothyCore.dayCalendar).
/// Right-click reveal: content shifts left, a pink Delete action sits flush right inside the row's border.
private struct DeleteReveal: ViewModifier {
    let shown: Bool
    let compact: Bool
    let delete: () -> Void
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
            if shown {
                HStack(spacing: 0) {
                    B.ink.frame(width: compact ? 2 : 3)
                    Button(action: delete) {
                        HStack(spacing: 8) {
                            Glyph(.trash).stroke(B.onAccent, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)).frame(width: 14, height: 14)
                            if !compact { Text("Delete").font(.body(15, .bold)).foregroundColor(B.onAccent) }
                        }
                        .frame(width: compact ? 54 : 101)
                        .frame(maxHeight: .infinity)
                        .background(B.pink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete")
                }
                .transition(.move(edge: .trailing))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
    }
}

private func deadlinePresets() -> [(String, Date?)] {
    let t = today()
    return [("Today", t),
            ("Tomorrow", dayCalendar.date(byAdding: .day, value: 1, to: t)),
            ("Next week", dayCalendar.nextDate(after: t, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)),
            ("None", nil)]
}

struct DeadlineChip: View {
    let date: Date
    let compact: Bool
    var body: some View {
        let t = today()
        let hot = date <= t
        Text(hot ? (date < t ? "LATE" : "TODAY") : label(t))
            .font(.mono(compact ? 10 : 11, bold: true))
            .foregroundColor(hot ? B.onAccent : B.paper)
            .padding(.vertical, compact ? 2 : 3).padding(.horizontal, compact ? 5 : 8)
            .brutalBox(hot ? B.pink : B.ink, border: hot ? 2 : 0, shadow: 0)
            .fixedSize()
    }

    private func label(_ today: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = dayCalendar
        f.timeZone = dayCalendar.timeZone
        let soon = date < dayCalendar.date(byAdding: .day, value: 7, to: today)!
        f.dateFormat = soon ? (compact ? "EEE" : "EEE d") : "MMM d"
        return f.string(from: date).uppercased()
    }
}

struct EmptyCard: View {
    let compact: Bool
    var body: some View {
        VStack(spacing: 14) {
            Color.clear.frame(width: compact ? 42 : 58, height: compact ? 42 : 58)
                .brutalBox(B.mint, shadow: 5)
                .rotationEffect(.degrees(-8))
            Text("Clean slate.").font(.display(22))
            Text("Type below or hold ⌃⌥D and say it.").font(.body(compact ? 13 : 15)).multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dashedBorder()
    }
}

// MARK: Input

struct QuickAdd: View {
    @EnvironmentObject var m: AppModel
    let compact: Bool
    @State private var text = ""
    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            HStack(spacing: compact ? 8 : 10) {
                Text("+").font(.display(compact ? 14 : 18))
                TextField("", text: $text)
                    .textFieldStyle(.plain).font(.body(compact ? 13 : 15))
                    .onSubmit {
                        let t = text
                        text = ""
                        Task { if !(await m.submit(t)) && text.isEmpty { text = t } }  // nothing saved → give the text back
                    }
                    .background(alignment: .leading) {
                        if text.isEmpty {
                            Text(compact ? "Add or say something…" : "“dentist next tuesday, urgent”")
                                .font(.body(compact ? 13 : 15)).foregroundColor(B.placeholder).allowsHitTesting(false)
                        }
                    }
                if !compact { Text("↵").font(.mono(11)) }
            }
            .padding(.horizontal, compact ? 8 : 12)
            .frame(height: compact ? 28 : 40)  // + 3pt borders = 34 / 46, same as the mic
            .brutalBox(shadow: compact ? 4 : 5)
            MicButton(side: compact ? 34 : 46)
        }
    }
}

/// Blue square → pink circle while recording (level-scaled pulse ring); rotating orange square while Gemma thinks.
struct MicButton: View {
    @EnvironmentObject var m: AppModel
    let side: CGFloat
    var body: some View {
        let rec = m.mic == .recording
        let inner = side - 6
        Button { m.micTapped() } label: {
            ZStack {
                switch m.mic {
                case .idle:
                    MicGlyph(line: side > 40 ? 2.2 : 1.8).frame(width: side * 0.36, height: side * 0.43).transition(.pop)
                case .recording:
                    Rectangle().fill(B.paper).overlay(Rectangle().strokeBorder(B.ink, lineWidth: 2.5))
                        .frame(width: side * 0.3, height: side * 0.3).transition(.pop)
                case .thinking:
                    TimelineView(.animation) { ctx in
                        Rectangle().fill(B.orange).overlay(Rectangle().strokeBorder(B.ink, lineWidth: 2.5))
                            .frame(width: side * 0.34, height: side * 0.34)
                            .rotationEffect(.degrees(reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) * 300))
                    }
                    .transition(.pop)
                }
            }
            .frame(width: inner, height: inner)
        }
        .buttonStyle(BrutalButtonStyle(fill: rec ? B.pink : B.cobalt, shadow: side > 40 ? 5 : 4, radius: rec ? side / 2 : 0))
        .background {
            if rec && !reduceMotion { MicPulse(level: { m.recorder.level }, side: side).transition(.opacity) }
        }
        .disabled(m.mic == .thinking)
        .accessibilityLabel(rec ? "Stop" : "Dictate")
        .animation(motion(.spring(response: 0.35, dampingFraction: 0.6)), value: m.mic)
    }
}

/// Sticker disc behind the mic that swells with your voice. Sampled at ~12 Hz and eased between samples
/// so it doesn't jitter; room noise is gated out so it rests flush with the button in silence.
struct MicPulse: View {
    let level: () -> Float
    let side: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { _ in
            let v = CGFloat(min(1, max(0, (level() - 0.35) / 0.45)))  // ponytail: fixed noise gate; per-device calibration if mics vary a lot
            Circle().fill(B.yellow).overlay(Circle().strokeBorder(B.ink, lineWidth: 3))
                .frame(width: side, height: side)
                .scaleEffect(1 + v * 0.4)
                .animation(.easeOut(duration: 0.12), value: v)
        }
    }
}

// MARK: Compact layout

struct CompactView: View {
    @EnvironmentObject var m: AppModel
    let ns: Namespace.ID
    /// Hosted in the menu-bar drop-down: never shows Settings; expand opens the main window instead.
    var menuBar = false
    var onExpand: (() -> Void)?
    @State private var picking = false

    var body: some View {
        if m.showSettings && !menuBar {
            SettingsView(compact: true).transition(.opacity)
        } else {
            content.transition(.opacity)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let list = m.currentList {
                header(list).zIndex(1)
                if m.dataError != nil || !m.gemmaOnline { Banners(compact: true).transition(.opacity) }
                ItemsView(list: list, compact: true)
            } else {
                Banners(compact: true)
                Spacer()
            }
            if let n = m.notice { NoticeLine(text: n) }
            QuickAdd(compact: true)
        }
        .padding(.horizontal, 12).padding(.top, menuBar ? 34 : 42).padding(.bottom, 12)  // 42 clears the window controls
    }

    private func header(_ list: TodoList) -> some View {
        HStack(spacing: 8) {
            Button { withAnimation(motion(springy)) { picking.toggle() } } label: {
                HStack(spacing: 8) {
                    Swatch(hex: list.color, size: 12)
                    Text(list.name).font(.display(18)).tracking(-0.36).lineLimit(1).matchedGeometryEffect(id: "title", in: ns)
                        .foregroundColor(B.onAccent)
                    Spacer(minLength: 0)
                    Glyph(.chevron).stroke(B.onAccent, lineWidth: 2.5).frame(width: 12, height: 8).rotationEffect(.degrees(picking ? 180 : 0))
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
            }
            .buttonStyle(BrutalButtonStyle(fill: B.yellow, shadow: 4))
            .overlay(alignment: .topLeading) {
                if picking { dropdown(list).offset(y: 46).transition(.pop) }
            }
            .zIndex(1)
            GroupToggle(list: list, compact: true)
            Button { if let onExpand { onExpand() } else { m.toggleCompact() } } label: {
                Glyph(.expand).stroke(B.ink, lineWidth: 2.2).frame(width: 14, height: 14).frame(width: 28, height: 28)
            }
            .buttonStyle(BrutalButtonStyle(shadow: 4))
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .accessibilityLabel("Full view")
        }
    }

    private func dropdown(_ current: TodoList) -> some View {
        VStack(spacing: 0) {
            ForEach(m.data.lists) { l in
                Button { m.select(l.id); withAnimation(motion(springy)) { picking = false } } label: {
                    HStack(spacing: 8) {
                        Swatch(hex: l.color, size: 12)
                        Text(l.name).font(.body(14, .semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(l.items.filter { !$0.done }.count)").font(.mono(11))
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .foregroundColor(l.id == current.id ? B.onAccent : B.ink)
                    .background(l.id == current.id ? B.yellow : B.paper)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .brutalBox(shadow: 4)
        .frame(width: 200)
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    let compact: Bool
    @AppStorage("reduceMotion") private var reduce = false
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage(Recorder.deviceKey) private var micID = ""
    @AppStorage("micDeviceName") private var micName = ""  // kept so a disconnected mic can still be named
    @State private var devices = Recorder.inputDevices()
    @State private var armed: Danger?
    @State private var phrase = ""
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool
    @State private var dataResult: (ok: Bool, text: String)?
    @State private var copied: String?

    enum Danger { case tasks, lists }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Caps("Shortcut")
                            Text("⌘ ,").font(.system(size: 13, weight: .bold)).foregroundColor(B.onInk)  // system font: Space Mono lacks ⌘
                                .padding(.horizontal, 7).frame(minHeight: 22).background(B.inkFill)
                        }
                        .accessibilityElement(children: .ignore).accessibilityLabel("Shortcut: Command comma")
                        Text("Settings").font(.display(compact ? 30 : 44)).tracking(compact ? -0.9 : -1.32)
                    }
                    Spacer()
                    Button { m.toggleSettings() } label: {
                        Glyph(.close).stroke(B.ink, lineWidth: 2.5).frame(width: 12, height: 12).frame(width: 32, height: 32)
                    }
                    .buttonStyle(BrutalButtonStyle(shadow: 4))
                    .accessibilityLabel("Close settings")
                }
                appearanceRow
                switchRow("Reduce motion", "Turns off hover wiggles, springs and pop-ins. Fades only.", $reduce)
                switchRow("Show in Dock", "Off = menu bar only. Dorothy keeps running when its window is closed.", $showInDock)
                    .onChange(of: showInDock) { m.applyDockPolicy(reactivate: true) }
                micRow
                VStack(alignment: .leading, spacing: 12) {
                    GroupHeader(title: "Connect an AI agent", index: 0, compact: false)
                    Text("Claude and other MCP clients can read and update your lists. Changes show up here live.")
                        .font(.body(13)).foregroundColor(Color(hex: "#444444"))
                        .fixedSize(horizontal: false, vertical: true)
                    snippet("Claude Code", MCPSetup.claudeCodeCommand(serverPath: mcpServerPath))
                    snippet("Other MCP clients (JSON)", MCPSetup.jsonConfig(serverPath: mcpServerPath))
                    Text("Then ask your agent things like \"what's due this week?\"")
                        .font(.body(13)).foregroundColor(Color(hex: "#444444"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    GroupHeader(title: "Data", index: 0, compact: false)
                    HStack(spacing: 12) {
                        plainButton("Export Markdown…", action: exportMarkdown)
                        plainButton("Import Markdown…", action: importMarkdown)
                    }
                    if let r = dataResult {
                        HStack(spacing: 8) {
                            Swatch(hex: r.ok ? "#22D39A" : "#FF4FA3", size: 10)
                            Text(r.text).font(.body(13))
                        }
                        .transition(.opacity)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    GroupHeader(title: "Danger zone", index: 0, compact: false)
                    HStack(spacing: 12) {
                        dangerButton("Clear all tasks", .tasks)
                        dangerButton("Clear all lists", .lists)
                    }
                    if let armed { confirmCard(armed).transition(.opacity.combined(with: .move(edge: .top))) }
                }
            }
            .padding(.trailing, 6).padding(.bottom, 6)
            // Mic dropdown floats above everything below the row; a clear layer catches click-away.
            .overlayPreferenceValue(MicPickerAnchor.self) { anchor in
                GeometryReader { g in
                    if m.micPickerOpen, let anchor {
                        let r = g[anchor]
                        ZStack(alignment: .topLeading) {
                            Color.white.opacity(0.001).onTapGesture { closeMic() }
                            micMenu.frame(width: r.width).offset(x: r.minX, y: r.maxY + 6)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.95, anchor: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .padding(.trailing, -6)
        .onReceive(NotificationCenter.default.publisher(for: Recorder.devicesChanged)) { _ in devices = Recorder.inputDevices() }
        .onDisappear { m.micPickerOpen = false }
        .padding(.horizontal, compact ? 16 : 36).padding(.top, compact ? 42 : 40).padding(.bottom, compact ? 16 : 28)
    }

    private func switchRow(_ title: String, _ detail: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body(16, .bold))
                Text(detail).font(.body(13)).foregroundColor(B.muted)
            }
            Spacer(minLength: 0)
            BrutalSwitch(on: on).accessibilityLabel(title)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .brutalBox()
    }

    private var appearanceRow: some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Appearance").font(.body(16, .bold))
                Text("Light, dark, or follow macOS.").font(.body(13)).foregroundColor(B.muted)
            }
            if !compact { Spacer(minLength: 0) }
            // The selected fill is B.ink, which is light in dark mode, so its label uses B.paper.
            Segmented(options: Appearance.allCases, selection: m.appearance, onSelect: { m.appearance = $0 }) { a, on in
                Caps(a.label, size: 10, bold: true, color: on ? B.paper : B.ink)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
            .accessibilityLabel("Appearance")
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .brutalBox()
    }

    private var micMissing: Bool { !micID.isEmpty && !devices.contains { $0.id == micID } }

    private var micLabel: String {
        if micID.isEmpty { return "System default" }
        return devices.first { $0.id == micID }?.name ?? "\((micName.isEmpty ? "Saved mic" : micName)) (disconnected)"
    }

    private var micRow: some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Microphone").font(.body(16, .bold))
                Text(micMissing ? "Disconnected — recording uses the system default." : "Used for ⌃⌥D and the mic button.")
                    .font(.body(13)).foregroundColor(B.muted)
            }
            if !compact { Spacer(minLength: 0) }
            Button { withAnimation(motion(springy)) { m.micPickerOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Text(micLabel).font(.body(14, .semibold)).foregroundColor(B.onAccent).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Glyph(.chevron).stroke(B.onAccent, lineWidth: 2.5).frame(width: 12, height: 8)
                        .rotationEffect(.degrees(m.micPickerOpen ? 180 : 0))
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .frame(maxWidth: compact ? .infinity : 260)
            }
            .buttonStyle(BrutalButtonStyle(fill: B.yellow, shadow: m.micPickerOpen ? 0 : 3))
            .accessibilityLabel("Microphone: \(micLabel)")
            .anchorPreference(key: MicPickerAnchor.self, value: .bounds) { $0 }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .brutalBox()
    }

    private var mcpServerPath: String {
        MCPSetup.serverURL(appExecutable: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).path
    }

    private func snippet(_ label: String, _ text: String) -> some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                Text(label).font(.body(14, .bold))
                if !compact { Spacer(minLength: 0) }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(motion(springy)) { copied = label }
                } label: {
                    Text(copied == label ? "Copied ✓" : "Copy").font(.body(13, .bold)).lineLimit(1)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                }
                .buttonStyle(BrutalButtonStyle(shadow: 3))
                .accessibilityLabel("Copy \(label) setup")
            }
            Text(text).font(.mono(12)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10).padding(.horizontal, 12)
                .brutalBox(shadow: 0)
        }
    }

    private var micMenu: some View {
        let options = [(id: "", name: "System default")] + devices
        return VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, d in
                if i > 0 { B.ink.frame(height: 2) }
                Button {
                    micID = d.id
                    micName = d.id.isEmpty ? "" : d.name
                    closeMic()
                } label: {
                    HStack(spacing: 8) {
                        Text(micID == d.id ? "✓" : "").font(.body(14, .bold)).frame(width: 12)
                        Text(d.name).font(.body(14, micID == d.id ? .bold : .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .foregroundColor(micID == d.id ? B.onAccent : B.ink)
                    .background(micID == d.id ? B.yellow : B.paper)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .brutalBox(shadow: 5)
    }

    private func closeMic() { withAnimation(motion(springy)) { m.micPickerOpen = false } }

    private func plainButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body(15, .bold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.horizontal, compact ? 10 : 14)
        }
        .buttonStyle(BrutalButtonStyle())
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Dorothy-\(formatDay(today())).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let items = m.data.lists.reduce(0) { $0 + $1.items.count }
        do {
            try MarkdownIO.export(m.data).write(to: url, atomically: true, encoding: .utf8)
            show(true, "Exported \(count(m.data.lists.count, "list")) · \(count(items, "task"))")
        } catch {
            show(false, "Couldn't save: \(error.localizedDescription)")
        }
    }

    private func importMarkdown() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["md", "markdown", "txt"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return show(false, "Couldn't read that file.") }
        let lists = MarkdownIO.parse(text)
        guard !lists.isEmpty else { return show(false, "No lists or tasks found in that file.") }
        let added = m.importLists(lists)
        show(true, added == (0, 0) ? "Nothing new to import." : "Added \(count(added.items, "task")) · \(count(added.lists, "new list"))")
    }

    private func show(_ ok: Bool, _ text: String) { withAnimation(motion(springy)) { dataResult = (ok, text) } }
    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private func dangerButton(_ title: String, _ d: Danger) -> some View {
        let on = armed == d
        return Button {
            withAnimation(motion(springy)) {
                armed = on ? nil : d
                phrase = Self.newPhrase()
                typed = ""
            }
        } label: {
            Text(title + (on ? " ↓" : "")).font(.body(15, .bold)).foregroundColor(on ? B.onInk : B.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.horizontal, compact ? 10 : 14)
        }
        .buttonStyle(BrutalButtonStyle(fill: on ? B.inkFill : B.paper, shadow: on ? 0 : 5))
    }

    private func confirmCard(_ d: Danger) -> some View {
        let matches = typed.trimmingCharacters(in: .whitespaces) == phrase
        let row = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: 12) {
            Text((d == .tasks ? "Deletes every task in every list." : "Deletes every list and every task. MCP agents lose them too.")
                 + " Type the phrase to confirm:")
                .font(.body(14)).fixedSize(horizontal: false, vertical: true)
            Text(phrase).font(.mono(16, bold: true)).tracking(0.64).foregroundColor(B.onAccent)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .brutalBox(B.yellow, border: 2, shadow: 0)
                .rotationEffect(.degrees(-1))
            row {
                TextField("", text: $typed).textFieldStyle(.plain).font(.mono(14))
                    .focused($fieldFocused).onAppear { DispatchQueue.main.async { fieldFocused = true } }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .brutalBox(shadow: 0)
                HStack(spacing: 10) {
                    Button {
                        guard matches else { return }
                        d == .tasks ? m.clearAllTasks() : m.clearAllLists()
                        withAnimation(motion(springy)) { armed = nil }
                    } label: {
                        Text(d == .tasks ? "Delete all tasks" : "Delete everything").font(.body(14, .bold)).fixedSize()
                            .foregroundColor(matches ? B.onAccent : B.placeholder)
                            .padding(.vertical, 10).padding(.horizontal, 14)
                    }
                    .buttonStyle(BrutalButtonStyle(fill: matches ? B.pink : B.disabledBG, shadow: matches ? 4 : 0))
                    .disabled(!matches)
                    Button { withAnimation(motion(springy)) { armed = nil } } label: {
                        Text("Cancel").font(.body(14, .bold)).fixedSize().padding(.vertical, 10).padding(.horizontal, 14)
                    }
                    .buttonStyle(BrutalButtonStyle(shadow: 0))
                }
            }
        }
        .padding(13)
        .brutalBox(B.dangerBG, shadow: 0)
    }

    static func newPhrase() -> String {
        let adjectives = ["tangerine", "fuzzy", "brave", "quiet", "sneaky", "lucky", "salty", "cosmic", "sleepy", "mighty"]
        let animals = ["walrus", "otter", "badger", "heron", "lemur", "gecko", "bison", "puffin", "marmot", "newt"]
        return "\(adjectives.randomElement()!)-\(animals.randomElement()!)-\(Int.random(in: 10...99))"
    }
}

private struct MicPickerAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}
