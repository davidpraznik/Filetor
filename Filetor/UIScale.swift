import SwiftUI

/// Text size steps from Settings (S, M, L, XL, Turbo). Scales text and icons across the whole UI.
enum UIScale {
    static let factors: [CGFloat] = [0.92, 1.0, 1.12, 1.4, 1.68]

    static func value(_ index: Int) -> CGFloat {
        factors[min(max(index, 0), factors.count - 1)]
    }

    static func controlSize(_ scale: CGFloat) -> ControlSize {
        scale >= 1.4 ? .extraLarge : (scale >= 1.12 ? .large : .regular)
    }
}
