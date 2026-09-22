import AppKit
import Common
import HotKey

private let keyMappingParser: [String: any ParserProtocol<KeyMapping>] = [
    "preset": Parser(\.preset, parsePreset),
    "key-notation-to-key-code": Parser(\.rawKeyNotationToKeyCode, parseKeyNotationToKeyCode),
]

// The right-hand side of 'key-mapping.key-notation-to-key-code'. Mixing keys and modifiers is not supported
enum KeyCodeOrModifiers: Equatable, Sendable {
    case keyCode(Key) // Can be used only as a suffix in bindings. E.g. 'alt-unicorn'
    case modifiers(NSEvent.ModifierFlags) // Can be used only as a prefix in bindings. E.g. 'hyper-c'
}

struct KeyMapping: ConvenienceMutable, Equatable, Sendable {
    enum Preset: String, CaseIterable, Sendable {
        case qwerty, dvorak, colemak
    }

    init(
        preset: Preset = .qwerty,
        rawKeyNotationToKeyCode: [String: KeyCodeOrModifiers] = [:],
    ) {
        self.preset = preset
        self.rawKeyNotationToKeyCode = rawKeyNotationToKeyCode
    }

    fileprivate var preset: Preset = .qwerty
    fileprivate var rawKeyNotationToKeyCode: [String: KeyCodeOrModifiers] = [:]

    func resolve() -> [String: KeyCodeOrModifiers] {
        getKeysPreset(preset).mapValues(KeyCodeOrModifiers.keyCode) + rawKeyNotationToKeyCode
    }
}

func parseKeyMapping(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> KeyMapping {
    parseTable(raw, KeyMapping(), keyMappingParser, backtrace, &c)
}

private func parsePreset(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<KeyMapping.Preset> {
    parseString(raw, backtrace).flatMap { parseEnum($0, KeyMapping.Preset.self).toParsedConfig(backtrace) }
}

private func parseKeyNotationToKeyCode(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [String: KeyCodeOrModifiers] {
    var result: [String: KeyCodeOrModifiers] = [:]
    guard let table = raw.asDictOrNil else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace))
        return result
    }
    for (key, value): (String, OrderedJson) in table {
        if isValidKeyNotation(key) {
            let backtrace = backtrace + .key(key)
            if let value = parseString(value, backtrace).getOrNil(appendErrorTo: &c.errors) {
                switch parseKeyCodeOrModifiers(value) {
                    case .modifiers where modifiersMap.keys.contains(key):
                        c.errors.append(.init(backtrace, "\(key.singleQuoted) is a built-in modifier. It can't be redefined as a modifier alias"))
                    case let value?: result[key] = value
                    case nil: c.errors.append(.init(backtrace, "\(value.singleQuoted) is neither a key code nor a combination of modifiers"))
                }
            }
        } else {
            c.errors.append(.init(backtrace, "\(key.singleQuoted) is invalid key notation"))
        }
    }
    return result
}

private func parseKeyCodeOrModifiers(_ raw: String) -> KeyCodeOrModifiers? {
    if let keyCode = keyNotationToKeyCode[raw] {
        return .keyCode(keyCode)
    }
    var modifiers: NSEvent.ModifierFlags = []
    for rawModifier in raw.split(separator: "-", omittingEmptySubsequences: false) {
        guard let modifier = modifiersMap[String(rawModifier)] else { return nil }
        modifiers.insert(modifier)
    }
    return .modifiers(modifiers)
}

private func isValidKeyNotation(_ str: String) -> Bool {
    str.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !str.contains("-")
}
