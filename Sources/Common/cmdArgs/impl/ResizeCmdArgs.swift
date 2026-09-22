public struct ResizeCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .resize,
        help: resize_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.dimension, parseDimension, placeholder: "(smart|smart-opposite|width|height)"),
            newMandatoryPosArgParser(\.units, parseUnits, placeholder: "[+|-]<number>[%]"),
        ],
    )

    public var dimension: Lateinit<ResizeCmdArgs.Dimension> = .uninitialized
    public var units: Lateinit<ResizeCmdArgs.Units> = .uninitialized

    public init(
        rawArgs: [String],
        dimension: Dimension,
        units: Units,
    ) {
        self.commonState = .init(rawArgs.slice)
        self.dimension = .initialized(dimension)
        self.units = .initialized(units)
    }

    public enum Dimension: String, CaseIterable, Equatable, Sendable {
        case width, height, smart
        case smartOpposite = "smart-opposite"
    }

    public enum Units: Equatable, Sendable {
        case set(PixelsOrPercent)
        case add(PixelsOrPercent)
        case subtract(PixelsOrPercent)
    }
}

func parseResizeCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ResizeCmdArgs> {
    parseSpecificCmdArgs(ResizeCmdArgs(rawArgs: args), args)
}

private func parseDimension(i: PosArgParserInput) -> ParsedCliArgs<ResizeCmdArgs.Dimension> {
    .init(parseEnum(i.arg, ResizeCmdArgs.Dimension.self), advanceBy: 1)
}

private func parseUnits(i: PosArgParserInput) -> ParsedCliArgs<ResizeCmdArgs.Units> {
    if let number = PixelsOrPercent.parse(i.arg.removePrefix("+").removePrefix("-")) {
        switch true {
            case i.arg.starts(with: "+"): .succ(.add(number), advanceBy: 1)
            case i.arg.starts(with: "-"): .succ(.subtract(number), advanceBy: 1)
            default: .succ(.set(number), advanceBy: 1)
        }
    } else {
        .fail("<number> argument must be a number, optionally suffixed with '%'", advanceBy: 1)
    }
}
