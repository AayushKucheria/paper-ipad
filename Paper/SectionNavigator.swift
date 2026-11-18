import CoreGraphics

/// Pure logic for moving between EPUB spine sections by scrolling past their edges.
struct SectionNavigator: Equatable {
    enum Edge { case previous, next }
    enum Arrival { case saved, top, bottom }

    private(set) var index: Int
    let count: Int

    init(index: Int, count: Int) {
        self.count = count
        self.index = Self.resumeIndex(saved: index, count: count)
    }

    static func resumeIndex(saved: Int, count: Int) -> Int {
        min(max(0, saved), max(0, count - 1))
    }

    /// Which edge, if any, a finger release at `offset` has pulled past by at least `threshold`.
    static func boundary(offset: CGFloat, contentHeight: CGFloat, viewport: CGFloat, threshold: CGFloat) -> Edge? {
        let maxOffset = max(0, contentHeight - viewport)
        if offset - maxOffset >= threshold { return .next }
        if -offset >= threshold { return .previous }
        return nil
    }

    func neighbour(_ edge: Edge) -> Int? {
        let target = edge == .next ? index + 1 : index - 1
        return (0..<count).contains(target) ? target : nil
    }

    /// Moves to the neighbouring section and reports where it should open: the top when moving forward, the bottom when moving back.
    @discardableResult
    mutating func step(_ edge: Edge) -> Arrival? {
        guard let target = neighbour(edge) else { return nil }
        index = target
        return edge == .next ? .top : .bottom
    }

    mutating func jump(to target: Int) {
        index = Self.resumeIndex(saved: target, count: count)
    }

    /// Requested reading offset; the reader clamps `.greatestFiniteMagnitude` to the section's real end.
    static func startOffset(_ arrival: Arrival, savedOffset: CGFloat) -> CGFloat {
        switch arrival {
        case .saved: savedOffset
        case .top: 0
        case .bottom: .greatestFiniteMagnitude
        }
    }
}
