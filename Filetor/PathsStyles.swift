import SwiftUI
import Observation

/// Flat controls in the Paths style: rounded rectangles instead of capsules.
struct PathsButtonStyle: ButtonStyle {
    var scale: CGFloat = 1
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        configuration.label
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 5 * scale)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                shape.fill(prominent ? AnyShapeStyle(Color.filetor) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
            )
            .overlay(shape.strokeBorder(Color.primary.opacity(prominent ? 0 : 0.18)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct PathsCheckboxStyle: ToggleStyle {
    var scale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8 * scale) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
                    .frame(width: 15 * scale, height: 15 * scale)
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark").font(.system(size: 10 * scale, weight: .semibold))
                        }
                    }
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

/// Segmented control with a light track and a white selected segment.
struct SegmentedChoice: View {
    let options: [String]
    @Binding var selection: Int
    var scale: CGFloat = 1
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i])
                    .padding(.horizontal, 12 * scale)
                    .padding(.vertical, 4 * scale)
                    .frame(minWidth: 34 * scale, maxWidth: width == nil ? nil : .infinity)
                    .background {
                        if selection == i {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.12), radius: 0.8, y: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = i }
            }
        }
        .padding(3)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
        .fixedSize(horizontal: width == nil, vertical: true)
    }
}

struct PathsTextFieldStyle: TextFieldStyle {
    var scale: CGFloat = 1

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 6 * scale)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.18)))
    }
}

// MARK: - Accent colour and click-outside panels

/// Observable copy of the accent choice, so every view that reads Color.filetor redraws when it changes.
@Observable
final class AccentStore {
    static let shared = AccentStore()
    var index = UserDefaults.standard.integer(forKey: "accent")
}

extension Color {
    /// The accent chosen in Settings.
    static var filetor: Color {
        let i = AccentStore.shared.index
        return SettingsSheet.accents[min(max(i, 0), SettingsSheet.accents.count - 1)]
    }
}

extension EnvironmentValues {
    @Entry var closePanel: () -> Void = {}
}

private struct FloatingPanel<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var panel: () -> Panel

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                    panel()
                        .environment(\.closePanel, { isPresented = false })
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
                }
            }
        }
    }
}

extension View {
    /// Like .sheet, but a click on the dimmed area outside the panel closes it too.
    func floatingPanel<Panel: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Panel) -> some View {
        modifier(FloatingPanel(isPresented: isPresented, panel: content))
    }
}
