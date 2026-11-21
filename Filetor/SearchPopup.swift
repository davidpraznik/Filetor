import SwiftUI

/// Popup search field (⌘F), styled like the action palette (⌘K). Typing filters the active pane;
/// with AI on, a sentence is turned into filters after a short pause.
struct SearchPopup: View {
    let app: AppModel
    @FocusState private var focused: Bool
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("aiProvider") private var aiProvider = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var s: CGFloat { UIScale.value(textSize) }
    private var aiOn: Bool { aiProvider != 0 }

    private static let aiColors: [Color] = [
        Color(red: 0.23, green: 0.51, blue: 0.96),
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.93, green: 0.28, blue: 0.60),
    ]
    private static let suggestions = ["PDFs larger than 5 MB", "Images from last month", "Videos over 100 MB", "Changed this week"]

    private func close() { app.showSearchPopup = false }

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
                            if aiOn, pane.filter.split(separator: " ").count >= 2 { pane.askAI(pane.filter) }
                            close()
                        }
                    if !pane.filter.isEmpty {
                        Button { pane.clearAI() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("esc")
                            .font(.system(size: 11 * s))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
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
                            ForEach(Self.suggestions, id: \.self) { text in
                                Button { ask(text, pane: pane) } label: {
                                    Text(text)
                                        .font(.system(size: 13 * s))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6 * s)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else if aiOn, pane.aiAsking || pane.aiQuery != nil || pane.aiMessage != nil {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12 * s))
                            .foregroundStyle(LinearGradient(colors: Self.aiColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .padding(.top, 4 * s)
                        if pane.aiAsking {
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
                if aiOn { ring(asking: pane.aiAsking) }
            }
            .overlay {
                if !aiOn { RoundedRectangle(cornerRadius: 14.5).strokeBorder(Color.primary.opacity(0.12)) }
            }
            .frame(width: 560 * s)
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .shadow(color: aiOn ? Self.aiColors[1].opacity(pane.aiAsking ? 0.45 : 0.18) : .clear, radius: 22)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.97, anchor: .top)
            .padding(.top, 92)
        }
        .onAppear {
            focused = true
            withAnimation(.easeOut(duration: 0.16)) { appeared = true }
        }
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
