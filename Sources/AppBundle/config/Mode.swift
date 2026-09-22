import Common
import HotKey

struct Mode: ConvenienceMutable, Equatable, Sendable {
    var bindings: [String: HotkeyBinding]

    static let zero = Mode(bindings: [:])
}

private let parentBindingModeKey = "parent-binding-mode"

func parseModes(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext, _ mapping: [String: Key]) -> [String: Mode] {
    guard let rawTable = raw.asDictOrNil else {
        c.errors += [expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace)]
        return [:]
    }
    var result: [String: Mode] = [:]
    var parentBindingModes: [String: String] = [:]
    for (key, value) in rawTable {
        let (mode, parentBindingMode) = parseMode(value, backtrace + .key(key), &c, mapping)
        result[key] = mode
        parentBindingModes[key] = parentBindingMode
    }
    if !result.keys.contains(mainModeId) {
        c.errors += [.init(backtrace, "Please specify '\(mainModeId)' mode")]
    }
    return inheritParentBindingModes(result, parentBindingModes, backtrace, &c)
}

func parseMode(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext, _ mapping: [String: Key]) -> (mode: Mode, parentBindingMode: String?) {
    guard let rawTable: OrderedJson.JsonDict = raw.asDictOrNil else {
        c.errors += [expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace)]
        return (.zero, nil)
    }

    var result: Mode = .zero
    var parentBindingMode: String? = nil
    for (key, value) in rawTable {
        let backtrace = backtrace + .key(key)
        switch key {
            case "binding":
                result.bindings = parseBindings(value, backtrace, &c, mapping)
            case parentBindingModeKey:
                parentBindingMode = parseString(value, backtrace).getOrNil(appendErrorTo: &c.errors)
            default:
                c.errors += [unknownKeyDiagnostic(backtrace)]
        }
    }
    return (result, parentBindingMode)
}

// The mode inherits all the bindings of its 'parent-binding-mode' (transitively).
// Bindings declared in the mode itself take precedence over the inherited ones.
private func inheritParentBindingModes(
    _ modes: [String: Mode],
    _ parentBindingModes: [String: String],
    _ backtrace: ConfigBacktrace,
    _ c: inout ConfigParserContext,
) -> [String: Mode] {
    var result: [String: Mode] = [:]
    for modeId in modes.keys.sorted() {
        let parentBindingModeBacktrace = backtrace + .key(modeId) + .key(parentBindingModeKey)
        var ancestors: [String] = [modeId] // [modeId, parent, grandparent, ...]
        while let parent = parentBindingModes[ancestors.last.orDie()] {
            if !modes.keys.contains(parent) {
                if ancestors.count == 1 { // Report the error only once, for the mode that declares the parent
                    c.errors += [.init(parentBindingModeBacktrace, "Binding mode '\(parent)' doesn't exist")]
                }
                break
            }
            if ancestors.contains(parent) {
                if parent == modeId && modeId == ancestors.min() { // Report the cycle only once
                    let cycle = (ancestors + [parent]).joined(separator: " -> ")
                    c.errors += [.init(parentBindingModeBacktrace, "Cyclic '\(parentBindingModeKey)' dependency: \(cycle)")]
                }
                break
            }
            ancestors.append(parent)
        }
        var bindings: [String: HotkeyBinding] = [:]
        for ancestor in ancestors.reversed() {
            bindings.merge(modes[ancestor].orDie().bindings) { _, child in child }
        }
        result[modeId] = Mode(bindings: bindings)
    }
    return result
}
