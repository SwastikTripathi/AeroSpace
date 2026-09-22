import AppKit
import Common

struct Gaps: ConvenienceMutable, Equatable, Sendable {
    var inner: Inner
    var outer: Outer

    static let zero = Gaps(inner: .zero, outer: .zero)

    struct Inner: ConvenienceMutable, Equatable, Sendable {
        var vertical: DynamicConfigValue<PixelsOrPercent>
        var horizontal: DynamicConfigValue<PixelsOrPercent>

        static let zero = Inner(vertical: .pixels(0), horizontal: .pixels(0))

        init(vertical: PixelsOrPercent, horizontal: PixelsOrPercent) {
            self.vertical = .constant(vertical)
            self.horizontal = .constant(horizontal)
        }

        init(vertical: DynamicConfigValue<PixelsOrPercent>, horizontal: DynamicConfigValue<PixelsOrPercent>) {
            self.vertical = vertical
            self.horizontal = horizontal
        }
    }

    struct Outer: ConvenienceMutable, Equatable, Sendable {
        var left: DynamicConfigValue<PixelsOrPercent>
        var bottom: DynamicConfigValue<PixelsOrPercent>
        var top: DynamicConfigValue<PixelsOrPercent>
        var right: DynamicConfigValue<PixelsOrPercent>

        static let zero = Outer(left: .pixels(0), bottom: .pixels(0), top: .pixels(0), right: .pixels(0))

        init(left: PixelsOrPercent, bottom: PixelsOrPercent, top: PixelsOrPercent, right: PixelsOrPercent) {
            self.left = .constant(left)
            self.bottom = .constant(bottom)
            self.top = .constant(top)
            self.right = .constant(right)
        }

        init(left: DynamicConfigValue<PixelsOrPercent>, bottom: DynamicConfigValue<PixelsOrPercent>, top: DynamicConfigValue<PixelsOrPercent>, right: DynamicConfigValue<PixelsOrPercent>) {
            self.left = left
            self.bottom = bottom
            self.top = top
            self.right = right
        }
    }
}

struct ResolvedGaps {
    let inner: Inner
    let outer: Outer

    struct Inner {
        let vertical: CGFloat
        let horizontal: CGFloat

        func get(_ orientation: Orientation) -> CGFloat {
            orientation == .h ? horizontal : vertical
        }
    }

    struct Outer {
        let left: CGFloat
        let bottom: CGFloat
        let top: CGFloat
        let right: CGFloat
    }

    /// Horizontal gaps are resolved against the monitor width, and vertical gaps are resolved against the monitor height
    @MainActor init(gaps: Gaps, monitor: any MonitorInfo) {
        let width = monitor.visibleRect.width
        let height = monitor.visibleRect.height

        inner = .init(
            vertical: gaps.inner.vertical.getValue(for: monitor).toPixels(hundredPercent: height),
            horizontal: gaps.inner.horizontal.getValue(for: monitor).toPixels(hundredPercent: width),
        )

        outer = .init(
            left: gaps.outer.left.getValue(for: monitor).toPixels(hundredPercent: width),
            bottom: gaps.outer.bottom.getValue(for: monitor).toPixels(hundredPercent: height),
            top: gaps.outer.top.getValue(for: monitor).toPixels(hundredPercent: height),
            right: gaps.outer.right.getValue(for: monitor).toPixels(hundredPercent: width),
        )
    }
}

private let gapsParser: [String: any ParserProtocol<Gaps>] = [
    "inner": Parser(\.inner, parseInner),
    "outer": Parser(\.outer, parseOuter),
]

private let innerParser: [String: any ParserProtocol<Gaps.Inner>] = [
    "vertical": Parser(\.vertical, parseGapDynamicValue),
    "horizontal": Parser(\.horizontal, parseGapDynamicValue),
]

private let outerParser: [String: any ParserProtocol<Gaps.Outer>] = [
    "left": Parser(\.left, parseGapDynamicValue),
    "bottom": Parser(\.bottom, parseGapDynamicValue),
    "top": Parser(\.top, parseGapDynamicValue),
    "right": Parser(\.right, parseGapDynamicValue),
]

private func parseGapDynamicValue(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> DynamicConfigValue<PixelsOrPercent> {
    parseDynamicValue(raw, .pixels(0), backtrace, &c)
}

func parseGaps(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Gaps {
    parseTable(raw, .zero, gapsParser, backtrace, &c)
}

func parseInner(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Gaps.Inner {
    parseTable(raw, Gaps.Inner.zero, innerParser, backtrace, &c)
}

func parseOuter(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Gaps.Outer {
    parseTable(raw, Gaps.Outer.zero, outerParser, backtrace, &c)
}
