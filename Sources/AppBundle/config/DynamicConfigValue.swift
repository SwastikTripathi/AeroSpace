import Common

struct PerMonitorValue<Value: Equatable>: Equatable {
    let description: MonitorDescription
    let value: Value
}
extension PerMonitorValue: Sendable where Value: Sendable {}

enum DynamicConfigValue<Value: Equatable>: Equatable {
    case constant(Value)
    case perMonitor([PerMonitorValue<Value>], default: Value)
}
extension DynamicConfigValue: Sendable where Value: Sendable {}

/// A value that ``DynamicConfigValue`` can hold. It's parsed from a single TOML scalar
protocol SimpleConfigValue: Equatable {
    static func parseSimple(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Self>
}

extension PixelsOrPercent: SimpleConfigValue {
    static func parseSimple(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<PixelsOrPercent> {
        parsePixelsOrPercent(raw, backtrace)
    }
}

extension DynamicConfigValue {
    @MainActor func getValue(for monitor: any MonitorInfo) -> Value {
        switch self {
            case .constant(let value): return value
            case .perMonitor(let array, let defaultValue):
                let sortedMonitors = sortedMonitorInfos
                return array
                    .lazy
                    .compactMap {
                        $0.description.resolveMonitor(sortedMonitors: sortedMonitors)?.rect.topLeftCorner == monitor.rect.topLeftCorner
                            ? $0.value
                            : nil
                    }
                    .first ?? defaultValue
        }
    }
}

func parseDynamicValue<T: SimpleConfigValue>(
    _ raw: OrderedJson,
    _ fallback: T,
    _ backtrace: ConfigBacktrace,
    _ c: inout ConfigParserContext,
) -> DynamicConfigValue<T> {
    guard let array = raw.asArrayOrNil else {
        return .constant(T.parseSimple(raw, backtrace).getOrNil(appendErrorTo: &c.errors) ?? fallback)
    }

    guard let last = array.last else {
        c.errors.append(.init(backtrace, "The array must not be empty"))
        return .constant(fallback)
    }

    guard let defaultValue = T.parseSimple(last, backtrace + .index(array.count - 1)).getOrNil(appendErrorTo: &c.errors) else {
        return .constant(fallback)
    }

    if array.dropLast().isEmpty {
        c.errors.append(.init(backtrace, "The array must contain at least one monitor pattern"))
        return .constant(fallback)
    }

    let rules: [PerMonitorValue<T>] = parsePerMonitorValues(array.dropLast(), backtrace, &c)

    return .perMonitor(rules, default: defaultValue)
}

func parsePerMonitorValues<T: SimpleConfigValue>(_ array: OrderedJson.JsonArray, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [PerMonitorValue<T>] {
    array.enumerated().compactMap { (index: Int, raw: OrderedJson) -> PerMonitorValue<T>? in
        var backtrace = backtrace + .index(index)

        guard let (key, value) = raw.unwrapTableWithSingleKey(expectedKey: "monitor", &backtrace)
            .flatMap({ $0.value.unwrapTableWithSingleKey(expectedKey: nil, &backtrace) })
            .getOrNil(appendErrorTo: &c.errors)
        else {
            return nil
        }

        let monitorDescriptionResult = parseMonitorDescription(.string(key), backtrace)

        guard let monitorDescription = monitorDescriptionResult.getOrNil(appendErrorTo: &c.errors) else { return nil }

        guard let value = T.parseSimple(value, backtrace).getOrNil(appendErrorTo: &c.errors) else { return nil }

        return PerMonitorValue(description: monitorDescription, value: value)
    }
}
