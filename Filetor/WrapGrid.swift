import SwiftUI

/// Equal-width cells that wrap into rows; every row is as tall as its tallest cell.
struct WrapGrid: Layout {
    var cellWidth: CGFloat
    var rowSpacing: CGFloat

    private func columns(_ width: CGFloat) -> Int { max(1, Int(width / cellWidth)) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? cellWidth * 4
        let cols = columns(width)
        let rowHeights = rows(subviews, cols: cols, cellW: width / CGFloat(cols))
        let h = rowHeights.reduce(0, +) + rowSpacing * CGFloat(max(rowHeights.count - 1, 0))
        return CGSize(width: width, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columns(bounds.width)
        let cellW = bounds.width / CGFloat(cols)
        let heights = rows(subviews, cols: cols, cellW: cellW)
        var y = bounds.minY
        for (r, rh) in heights.enumerated() {
            for c in 0..<cols {
                let i = r * cols + c
                guard i < subviews.count else { break }
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(c) * cellW, y: y),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(width: cellW, height: rh))
            }
            y += rh + rowSpacing
        }
    }

    private func rows(_ subviews: Subviews, cols: Int, cellW: CGFloat) -> [CGFloat] {
        var result: [CGFloat] = []
        var i = 0
        while i < subviews.count {
            let slice = subviews[i..<min(i + cols, subviews.count)]
            result.append(slice.map { $0.sizeThatFits(ProposedViewSize(width: cellW, height: nil)).height }.max() ?? 0)
            i += cols
        }
        return result
    }
}
