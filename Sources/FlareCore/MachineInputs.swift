// MachineInputs.swift: state machine inputs and transition conditions. An input
// is a named bool or number with a default; a condition compares one input with
// a constant using `==`, `<` or `>`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A bool or number input value. Encoded as `{"bool": true}` or `{"number": 2}`
/// so the type never depends on how a JSON decoder reads `1` or `true`.
public enum InputValue: Codable, Sendable, Hashable {
    case bool(Bool)
    case number(Double)

    private enum CodingKeys: String, CodingKey { case bool, number }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let b = try c.decodeIfPresent(Bool.self, forKey: .bool) {
            self = .bool(b)
        } else if let n = try c.decodeIfPresent(Double.self, forKey: .number) {
            self = .number(n)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "input value needs bool or number"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let b): try c.encode(b, forKey: .bool)
        case .number(let n): try c.encode(n, forKey: .number)
        }
    }

    func sameType(as other: InputValue) -> Bool {
        switch (self, other) {
        case (.bool, .bool), (.number, .number): return true
        default: return false
        }
    }

    var isFinite: Bool {
        if case .number(let n) = self { return n.isFinite }
        return true
    }
}

/// A declared input. Its type is the type of `defaultValue`.
public struct MachineInput: Codable, Sendable, Hashable {
    public var name: String
    public var defaultValue: InputValue

    public init(name: String, defaultValue: InputValue) {
        self.name = name
        self.defaultValue = defaultValue
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case defaultValue = "default"
    }
}

public enum ConditionOp: String, Codable, Sendable, Hashable {
    case equal = "=="
    case less = "<"
    case greater = ">"
}

/// Holds when `input op value`. `<` and `>` apply to numbers only.
public struct Condition: Codable, Sendable, Hashable {
    public var input: String
    public var op: ConditionOp
    public var value: InputValue

    public init(input: String, op: ConditionOp, value: InputValue) {
        self.input = input
        self.op = op
        self.value = value
    }

    /// Whether the condition holds for `current`. A missing value or a type
    /// mismatch never holds.
    func holds(_ current: InputValue?) -> Bool {
        switch (op, current, value) {
        case (.equal, let lhs?, let rhs): return lhs == rhs
        case (.less, .number(let lhs)?, .number(let rhs)): return lhs < rhs
        case (.greater, .number(let lhs)?, .number(let rhs)): return lhs > rhs
        default: return false
        }
    }
}
