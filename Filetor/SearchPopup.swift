import SwiftUI

/// Popup search field (⌘F), styled like the action palette (⌘K). Typing filters the active pane;
/// with AI on, a sentence is turned into filters after a short pause.
struct SearchPopup: View {
    let app: AppModel
    @FocusState private var focused: Bool
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("aiProvider") private var aiProvider = 0
    @State private var appeared = false
    @State private var listening = false
    @State private var closeWhenDone = false
    @State private var historyVersion = 0
    @State private var silenceTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var s: CGFloat { UIScale.value(textSize) }
    private var aiOn: Bool { aiProvider != 0 }

    private static let aiColors: [Color] = [
        Color(red: 0.23, green: 0.51, blue: 0.96),
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.93, green: 0.28, blue: 0.60),
    ]
    /// Deeper violet used for the soft glow, so it stays calm and see-through.
    private static let glow = Color(red: 0.36, green: 0.20, blue: 0.78)
    private static let defaultSuggestions = ["VectorCraft and Illustrator files from last week", "PDFs from last week", "Photos from last week", "Zip files from this month"]

    /// Searches you repeat (at least twice) come first, the rest is filled with the standard examples.
    private var suggestions: [String] {
        _ = historyVersion
        var list = SearchHistory.frequent(4)
        for text in Self.defaultSuggestions where list.count < 4 {
            if !list.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) { list.append(text) }
        }
        return list
    }

    private func close() { app.showSearchPopup = false }

    /// Starts or stops the macOS Dictation in the search field (same as pressing the Dictation shortcut).
    private func stopListening() {
        silenceTask?.cancel()
        listening = false
        NSApp.sendAction(Selector(("stopDictation:")), to: nil, from: nil)
    }

    private func toggleDictation() {
        if listening {
            stopListening()
        } else {
            focused = true
            listening = true
            DispatchQueue.main.async {
                // If nothing handles the action (Dictation not available), the mic does not stay in the listening state.
                if !NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil) { listening = false }
            }
        }
    }

    private var micButton: some View {
        Button { toggleDictation() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.system(size: 16 * s, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: Self.aiColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: listening ? Self.glow.opacity(0.55) : .clear, radius: 6)
                Image(systemName: "sparkle")
                    .font(.system(size: 7 * s, weight: .bold))
                    .foregroundStyle(Self.aiColors[2])
                    .shadow(color: listening ? Self.glow.opacity(0.55) : .clear, radius: 4)
                    .symbolEffect(.pulse, isActive: listening && !reduceMotion)
                    .offset(x: 5 * s, y: -3 * s)
            }
            .frame(width: 24 * s, height: 24 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(listening ? "Stop dictation" : "Dictate")
    }

    private func ask(_ text: String, pane: PaneModel) {
        pane.filter = text
        pane.askAI(text)
    }

    /// The coloured ring. It turns slowly while the AI is reading, and stands still otherwise.
    private func ring(asking: Bool) -> some View {
        TimelineView(.animation(paused: !asking || reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let angle = asking && !reduceMotion ? seconds.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360 : 20
            let blue = Self.aiColors[0], violet = Self.aiColors[1], pink = Self.aiColors[2]
            // While reading: a bright comet runs around a dim ring. At rest: the full ring.
            let stops: [Gradient.Stop] = asking
                ? [.init(color: violet.opacity(0.12), location: 0), .init(color: violet.opacity(0.12), location: 0.45),
                   .init(color: blue, location: 0.7), .init(color: violet, location: 0.85), .init(color: pink, location: 0.97),
                   .init(color: violet.opacity(0.12), location: 1)]
                : [.init(color: blue, location: 0), .init(color: violet, location: 0.5), .init(color: pink, location: 0.75), .init(color: blue, location: 1)]
            RoundedRectangle(cornerRadius: 16.5)
                .fill(AngularGradient(stops: stops, center: .center, angle: .degrees(angle)))
        }
    }

    var body: some View {
        @Bindable var pane = app.active
        ZStack(alignment: .top) {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if aiOn {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20 * s, weight: .medium))
                            .foregroundStyle(LinearGradient(colors: Self.aiColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .symbolEffect(.pulse, isActive: pane.aiAsking && !reduceMotion)
                    } else {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    }
                    TextField(aiOn ? "Search or describe what you need…" : "Search this folder…", text: $pane.filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16 * s))
                        .focused($focused)
                        .onSubmit {
                            if listening { stopListening() }
                            guard aiOn, pane.filter.split(separator: " ").count >= 2 else { close(); return }
                            let text = pane.filter.trimmingCharacters(in: .whitespacesAndNewlines)
                            if pane.aiAsking {
                                closeWhenDone = true
                            } else if pane.aiQuery != nil, pane.aiMessage == nil, pane.lastAsked == text {
                                close()
                            } else {
                                closeWhenDone = true
                                pane.askAI(text)
                            }
                        }
                    if aiOn { micButton }
                    if !pane.filter.isEmpty {
                        Button { pane.clearAI() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .frame(width: 38 * s)
                    } else {
                        Text("esc")
                            .font(.system(size: 11 * s))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                            .frame(width: 38 * s)
                    }
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 20 * s)
                    Button { pane.searchSubfolders.toggle() } label: {
                        Image(systemName: pane.searchSubfolders ? "folder.fill" : "folder")
                            .font(.system(size: 16 * s))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(pane.searchSubfolders ? Color.filetor : Color.secondary)
                    .help(pane.searchSubfolders ? "Searching subfolders" : "Search subfolders")
                }
                .padding(.horizontal, 16)
                .frame(height: 56 * s)

                if aiOn, pane.filter.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Try asking")
                            .font(.system(size: 11.5 * s, weight: .semibold))
                            .foregroundStyle(.secondary)
                        SuggestionFlow(spacing: 8) {
                            ForEach(suggestions, id: \.self) { text in
                                Button { ask(text, pane: pane) } label: {
                                    Text(text)
                                        .font(.system(size: 13 * s))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6 * s)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if SearchHistory.frequent(50).contains(text) {
                                        Button("Remove from suggestions") {
                                            SearchHistory.remove(text)
                                            historyVersion += 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else if aiOn, pane.aiAsking || pane.aiQuery != nil || pane.aiMessage != nil || pane.filter.split(separator: " ").count >= 2 {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12 * s))
                            .foregroundStyle(LinearGradient(colors: Self.aiColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .padding(.top, 4 * s)
                        if pane.aiAsking || (pane.aiQuery == nil && pane.aiMessage == nil) {
                            Text("Reading your request…").foregroundStyle(.secondary).padding(.top, 2 * s)
                        } else if let query = pane.aiQuery {
                            SuggestionFlow(spacing: 6) {
                                Text("Understood").foregroundStyle(.secondary).fixedSize().padding(.vertical, 3 * s)
                                ForEach(query.chips, id: \.self) { chip in
                                    AIChip(text: chip, scale: s)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let message = pane.aiMessage {
                            Text(message).foregroundStyle(.secondary).padding(.top, 2 * s)
                        }
                    }
                    .font(.system(size: 12.5 * s))
                    .frame(minHeight: 26 * s, alignment: .top)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10 * s)
                }

                Divider()
                HStack(spacing: 18) {
                    HStack(spacing: 6) { key("↩"); Text("Show results") }
                    HStack(spacing: 6) { key("esc"); Text("Close") }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12 * s))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 16)
                .frame(height: 34 * s)
                .background(Color.primary.opacity(0.03))
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14.5))
            .padding(aiOn ? 2 : 0)
            .background {
                if aiOn {
                    ring(asking: pane.aiAsking)
                        .opacity(pane.aiAsking ? 1 : 0)
                        .animation(.easeOut(duration: 0.25), value: pane.aiAsking)
                }
            }
            .overlay {
                if !aiOn || !pane.aiAsking { RoundedRectangle(cornerRadius: 14.5).strokeBorder(Color.primary.opacity(0.12)) }
            }
            .frame(width: 560 * s)
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .shadow(color: aiOn && pane.aiAsking ? Self.glow.opacity(0.28) : .clear, radius: 22)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.97, anchor: .top)
            .padding(.top, 92)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.16)) { appeared = true }
            DispatchQueue.main.async { focused = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { focused = true }
        }
        .onChange(of: pane.filter) {
            guard listening else { return }
            // Dictation sends no "silence" signal. When the text stops changing for a moment, stop listening.
            silenceTask?.cancel()
            silenceTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, listening else { return }
                stopListening()
            }
        }
        .onChange(of: pane.aiAsking) { _, asking in
            if asking {
                if listening { stopListening() }
            } else if closeWhenDone {
                closeWhenDone = false
                // Close only when the AI understood the sentence. On an error the popup stays open with the message.
                if pane.aiMessage == nil { close() }
            }
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { listening = false } }
    }

    private func key(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11 * s))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.1)))
    }
}

/// Remembers the searches asked through the AI, on this Mac only.
enum SearchHistory {
    private struct Entry: Codable {
        var text: String
        var count: Int
        var last: Date
    }

    private static let key = "aiSearchHistory"

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    static func record(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var entries = load()
        if let index = entries.firstIndex(where: { $0.text.caseInsensitiveCompare(clean) == .orderedSame }) {
            entries[index].count += 1
            entries[index].text = clean
            entries[index].last = Date()
        } else {
            entries.append(Entry(text: clean, count: 1, last: Date()))
        }
        if entries.count > 50 {
            entries.sort { ($0.count, $0.last) > ($1.count, $1.last) }
            entries = Array(entries.prefix(50))
        }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func remove(_ text: String) {
        let entries = load().filter { $0.text.caseInsensitiveCompare(text) != .orderedSame }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// The most used searches, only those asked at least twice.
    static func frequent(_ limit: Int) -> [String] {
        load()
            .filter { $0.count >= 2 }
            .sorted { ($0.count, $0.last) > ($1.count, $1.last) }
            .prefix(limit)
            .map(\.text)
    }
}

/// Places items left to right and wraps them to the next row when the width runs out.
struct SuggestionFlow: Layout {
    var spacing: CGFloat

    private func place(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (points, CGSize(width: maxX, height: y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = place(subviews, width: bounds.width)
        for (view, point) in zip(subviews, result.points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// One filter the AI understood. Always on one line, with softly rounded corners.
struct AIChip: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 3 * scale)
            .background(Color.filetor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(Color.filetor)
    }
}
