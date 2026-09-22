import Foundation

/// A size that is either an absolute number of pixels, or a percentage of the size it's relative to
public enum PixelsOrPercent: Equatable, Sendable {
    case pixels(Int)
    case percent(Int)

    public func toPixels(hundredPercent: CGFloat) -> CGFloat {
        switch self {
            case .pixels(let pixels): CGFloat(pixels)
            case .percent(let percent): hundredPercent * CGFloat(percent) / 100
        }
    }

    /// Parses non-negative values: '30' and '5%'
    public static func parse(_ raw: String) -> PixelsOrPercent? {
        let isPercent = raw.hasSuffix("%")
        let digits = isPercent ? raw.dropLast() : Substring(raw)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits) else { return nil }
        return isPercent ? .percent(number) : .pixels(number)
    }
}
