import Foundation

/// Minimal JSON tree for building demo payloads with literals.
public enum JSONValue: Encodable, Equatable, Sendable,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByNilLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case string(String)
    case int(Int)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }

    public static func optional(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    public subscript(key: String) -> JSONValue? {
        get { if case let .object(o) = self { o[key] } else { nil } }
        set {
            guard case var .object(o) = self else { return }
            o[key] = newValue
            self = .object(o)
        }
    }

    public var stringValue: String? {
        if case let .string(s) = self { s } else { nil }
    }

    public var boolValue: Bool? {
        if case let .bool(b) = self { b } else { nil }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(v): try c.encode(v)
        case let .int(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .bool(v): try c.encode(v)
        case .null: try c.encodeNil()
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }

    /// Round-trips through the real API decoder.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try LifeOSJSON.makeDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}
