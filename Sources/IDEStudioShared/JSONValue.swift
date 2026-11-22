import Foundation

/// A JSON value that keeps object keys in the order they were written, so saving a file the IDE
/// edited (globalConfig.json, a Dashboard Studio definition) does not reshuffle it.
public indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(String)          // kept as written, so 1.0 and 1 survive a round trip
    case string(String)
    case array([JSONValue])
    case object([JSONMember])

    public struct JSONMember: Equatable {
        public var key: String
        public var value: JSONValue
        public init(_ key: String, _ value: JSONValue) { self.key = key; self.value = value }
    }

    // MARK: Convenience constructors

    public static func int(_ v: Int) -> JSONValue { .number(String(v)) }
    public static func double(_ v: Double) -> JSONValue {
        v == v.rounded() && abs(v) < 1e15 ? .number(String(Int(v))) : .number(String(v))
    }
    public static func obj(_ pairs: KeyValuePairs<String, JSONValue>) -> JSONValue {
        .object(pairs.map { JSONMember($0.key, $0.value) })
    }

    // MARK: Reading

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return Double(n) }; return nil }
    public var intValue: Int? { doubleValue.map { Int($0) } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var members: [JSONMember]? { if case .object(let m) = self { return m }; return nil }
    public var keys: [String] { members?.map(\.key) ?? [] }
    public var isObject: Bool { members != nil }

    /// Reads or writes a member of an object. Writing `nil` removes the key; writing to a
    /// non-object turns it into an object.
    public subscript(key: String) -> JSONValue? {
        get { members?.first { $0.key == key }?.value }
        set {
            var m = members ?? []
            if let i = m.firstIndex(where: { $0.key == key }) {
                if let v = newValue { m[i].value = v } else { m.remove(at: i) }
            } else if let v = newValue {
                m.append(JSONMember(key, v))
            }
            self = .object(m)
        }
    }

    public subscript(index: Int) -> JSONValue? {
        get { arrayValue.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
        set {
            guard var a = arrayValue, a.indices.contains(index), let v = newValue else { return }
            a[index] = v
            self = .array(a)
        }
    }

    /// Reads a value at a path of keys.
    public func at(_ path: String...) -> JSONValue? {
        var cur: JSONValue? = self
        for p in path { cur = cur?[p] }
        return cur
    }

    /// Writes a value at a path of keys, creating objects on the way.
    public mutating func set(_ value: JSONValue?, at path: [String]) {
        guard let first = path.first else { return }
        if path.count == 1 { self[first] = value; return }
        var child = self[first] ?? .object([])
        if !child.isObject { child = .object([]) }
        child.set(value, at: Array(path.dropFirst()))
        self[first] = child
    }

    // MARK: Parsing

    public struct ParseError: Error, LocalizedError, Equatable {
        public var message: String
        public var line: Int
        public var errorDescription: String? { "JSON error on line \(line): \(message)" }
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(Array(text.unicodeScalars))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        if p.i < p.s.count { throw p.error("unexpected text after the end of the document") }
        return v
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        func error(_ m: String) -> ParseError {
            ParseError(message: m, line: 1 + s[..<min(i, s.count)].filter { $0 == "\n" }.count)
        }
        mutating func skipSpace() {
            while i < s.count, s[i] == " " || s[i] == "\n" || s[i] == "\t" || s[i] == "\r" || s[i] == "\u{FEFF}" { i += 1 }
        }
        mutating func literal(_ word: String, _ v: JSONValue) throws -> JSONValue {
            let w = Array(word.unicodeScalars)
            guard i + w.count <= s.count, Array(s[i..<i + w.count]) == w else { throw error("unexpected character") }
            i += w.count
            return v
        }
        mutating func value() throws -> JSONValue {
            guard i < s.count else { throw error("unexpected end of document") }
            switch s[i] {
            case "{":
                i += 1
                var members: [JSONMember] = []
                skipSpace()
                if i < s.count, s[i] == "}" { i += 1; return .object(members) }
                while true {
                    skipSpace()
                    guard i < s.count, s[i] == "\"" else { throw error("expected a key in quotes") }
                    let k = try string()
                    skipSpace()
                    guard i < s.count, s[i] == ":" else { throw error("expected ':' after key \"\(k)\"") }
                    i += 1
                    skipSpace()
                    members.append(JSONMember(k, try value()))
                    skipSpace()
                    guard i < s.count else { throw error("object is not closed") }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "}" { i += 1; return .object(members) }
                    throw error("expected ',' or '}'")
                }
            case "[":
                i += 1
                var items: [JSONValue] = []
                skipSpace()
                if i < s.count, s[i] == "]" { i += 1; return .array(items) }
                while true {
                    skipSpace()
                    items.append(try value())
                    skipSpace()
                    guard i < s.count else { throw error("array is not closed") }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "]" { i += 1; return .array(items) }
                    throw error("expected ',' or ']'")
                }
            case "\"": return .string(try string())
            case "t": return try literal("true", .bool(true))
            case "f": return try literal("false", .bool(false))
            case "n": return try literal("null", .null)
            default:
                let start = i
                while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
                var text = ""
                text.unicodeScalars.append(contentsOf: s[start..<i])
                guard !text.isEmpty, Double(text) != nil else { throw error("unexpected character") }
                return .number(text)
            }
        }
        mutating func string() throws -> String {
            i += 1 // opening quote
            var out = String.UnicodeScalarView()
            while i < s.count {
                let c = s[i]
                i += 1
                if c == "\"" { return String(out) }
                if c != "\\" { out.append(c); continue }
                guard i < s.count else { break }
                let e = s[i]
                i += 1
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code), i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" {
                        i += 2
                        let low = try hex4()
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default: out.append(e)
                }
            }
            throw error("string is not closed")
        }
        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count else { throw error("bad \\u escape") }
            var text = ""
            text.unicodeScalars.append(contentsOf: s[i..<i + 4])
            guard let v = UInt32(text, radix: 16) else { throw error("bad \\u escape") }
            i += 4
            return v
        }
    }

    // MARK: Writing

    public func serialized(indent: Int = 4) -> String {
        var out = ""
        write(into: &out, indent: indent, depth: 0)
        return out
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }

    private func write(into out: inout String, indent: Int, depth: Int) {
        let pad = String(repeating: " ", count: indent * (depth + 1))
        let closePad = String(repeating: " ", count: indent * depth)
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): out += JSONValue.quote(s)
        case .array(let a):
            if a.isEmpty { out += "[]"; return }
            out += "[\n"
            for (n, v) in a.enumerated() {
                out += pad
                v.write(into: &out, indent: indent, depth: depth + 1)
                out += n == a.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "]"
        case .object(let m):
            if m.isEmpty { out += "{}"; return }
            out += "{\n"
            for (n, member) in m.enumerated() {
                out += pad + JSONValue.quote(member.key) + ": "
                member.value.write(into: &out, indent: indent, depth: depth + 1)
                out += n == m.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "}"
        }
    }
}

// MARK: - Paths through objects and arrays

public enum JSONPathPart: Hashable {
    case key(String)
    case index(Int)
}

extension JSONValue {
    public func value(at path: [JSONPathPart]) -> JSONValue? {
        var cur: JSONValue? = self
        for p in path {
            switch p {
            case .key(let k): cur = cur?[k]
            case .index(let i): cur = cur?[i]
            }
        }
        return cur
    }

    /// Writes a value at a path. Missing objects are created; array indexes must exist.
    public mutating func setValue(_ value: JSONValue?, at path: [JSONPathPart]) {
        guard let first = path.first else { if let value { self = value }; return }
        let rest = Array(path.dropFirst())
        switch first {
        case .key(let k):
            if rest.isEmpty { self[k] = value; return }
            var child = self[k] ?? (rest.first.map { if case .index = $0 { return JSONValue.array([]) } else { return .object([]) } } ?? .object([]))
            child.setValue(value, at: rest)
            self[k] = child
        case .index(let i):
            guard var a = arrayValue, a.indices.contains(i) else { return }
            if rest.isEmpty {
                if let value { a[i] = value } else { a.remove(at: i) }
            } else {
                a[i].setValue(value, at: rest)
            }
            self = .array(a)
        }
    }

    public mutating func append(_ value: JSONValue, toArrayAt path: [JSONPathPart]) {
        var a = self.value(at: path)?.arrayValue ?? []
        a.append(value)
        setValue(.array(a), at: path)
    }

    public mutating func moveElements(inArrayAt path: [JSONPathPart], from source: IndexSet, to destination: Int) {
        guard var a = self.value(at: path)?.arrayValue else { return }
        let moving = source.map { a[$0] }
        var dest = destination
        for i in source.reversed() { a.remove(at: i); if i < destination { dest -= 1 } }
        a.insert(contentsOf: moving, at: max(0, min(dest, a.count)))
        setValue(.array(a), at: path)
    }
}
