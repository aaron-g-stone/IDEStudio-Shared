import Foundation

/// One line of a Splunk .conf file.
public enum ConfLine: Equatable {
    case blank
    case comment(String)                       // the whole line, including '#'
    case setting(key: String, value: String)   // continuation lines are joined with "\n"
    case raw(String)                           // a line the parser did not understand; kept as is
}

public struct ConfStanza: Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var lines: [ConfLine]

    public init(name: String, lines: [ConfLine] = []) { self.name = name; self.lines = lines }

    public static func == (a: ConfStanza, b: ConfStanza) -> Bool { a.name == b.name && a.lines == b.lines }

    public var settings: [(key: String, value: String)] {
        lines.compactMap { if case .setting(let k, let v) = $0 { return (k, v) }; return nil }
    }

    public subscript(key: String) -> String? {
        get { settings.last { $0.key == key }?.value }
        set {
            let idx = lines.lastIndex { if case .setting(let k, _) = $0 { return k == key }; return false }
            if let v = newValue {
                if let i = idx { lines[i] = .setting(key: key, value: v) } else { append(key: key, value: v) }
            } else if let i = idx {
                lines.remove(at: i)
            }
        }
    }

    /// Adds a setting after the last setting, ahead of the blank lines that end the stanza.
    public mutating func append(key: String, value: String) {
        var at = lines.count
        while at > 0, lines[at - 1] == .blank { at -= 1 }
        lines.insert(.setting(key: key, value: value), at: at)
    }
}

/// A Splunk .conf file that keeps comments, blank lines and order, so editing one setting in the
/// IDE changes one line on disk.
public struct ConfDocument: Equatable {
    /// Lines ahead of the first stanza (file comments and global settings).
    public var preamble: [ConfLine] = []
    public var stanzas: [ConfStanza] = []

    public init() {}

    public init(text: String) {
        var current: ConfStanza?
        var rows = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if rows.last == "" { rows.removeLast() }
        var i = 0
        func add(_ line: ConfLine, _ doc: inout ConfDocument) {
            if current != nil { current!.lines.append(line) } else { doc.preamble.append(line) }
        }
        while i < rows.count {
            let row = rows[i]
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            i += 1
            if trimmed.isEmpty { add(.blank, &self); continue }
            if trimmed.hasPrefix("#") { add(.comment(row), &self); continue }
            if trimmed.hasPrefix("["), let close = trimmed.lastIndex(of: "]") {
                if let c = current { stanzas.append(c) }
                current = ConfStanza(name: String(trimmed[trimmed.index(after: trimmed.startIndex)..<close]))
                continue
            }
            guard let eq = row.firstIndex(of: "=") else { add(.raw(row), &self); continue }
            let key = row[..<eq].trimmingCharacters(in: .whitespaces)
            var value = String(row[row.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            while value.hasSuffix("\\"), i < rows.count {
                value = String(value.dropLast()) + "\n" + rows[i]
                i += 1
            }
            add(.setting(key: key, value: value), &self)
        }
        if let c = current { stanzas.append(c) }
    }

    public var text: String {
        func render(_ line: ConfLine) -> String {
            switch line {
            case .blank: return ""
            case .comment(let c): return c
            case .raw(let r): return r
            case .setting(let k, let v): return "\(k) = \(v.replacingOccurrences(of: "\n", with: "\\\n"))"
            }
        }
        var out = preamble.map(render)
        for s in stanzas {
            out.append("[\(s.name)]")
            out.append(contentsOf: s.lines.map(render))
        }
        return out.joined(separator: "\n") + "\n"
    }

    public func stanza(_ name: String) -> ConfStanza? { stanzas.first { $0.name == name } }

    public func value(_ stanza: String, _ key: String) -> String? { self.stanza(stanza)?[key] }

    /// Sets a value, creating the stanza when it is missing. `nil` removes the setting.
    public mutating func set(_ stanza: String, _ key: String, _ value: String?) {
        if let i = stanzas.firstIndex(where: { $0.name == stanza }) {
            stanzas[i][key] = value
        } else if let value {
            addStanza(stanza, settings: [(key, value)])
        }
    }

    @discardableResult
    public mutating func addStanza(_ name: String, settings: [(String, String)] = []) -> Int {
        if !stanzas.isEmpty, stanzas[stanzas.count - 1].lines.last != .blank {
            stanzas[stanzas.count - 1].lines.append(.blank)
        } else if stanzas.isEmpty, !preamble.isEmpty, preamble.last != .blank {
            preamble.append(.blank)
        }
        stanzas.append(ConfStanza(name: name, lines: settings.map { .setting(key: $0.0, value: $0.1) }))
        return stanzas.count - 1
    }

    /// Adds the stanzas of `other` that this document does not have yet. Used when a component is
    /// added to an app that already has the conf file.
    public mutating func merge(_ other: ConfDocument) {
        for s in other.stanzas where stanza(s.name) == nil {
            addStanza(s.name, settings: s.settings.map { ($0.key, $0.value) })
        }
    }

    /// Stanza names that appear more than once; Splunk merges them, which is rarely intended.
    public var duplicateStanzas: [String] {
        var seen = Set<String>(), dup: [String] = []
        for s in stanzas where !seen.insert(s.name).inserted && !dup.contains(s.name) { dup.append(s.name) }
        return dup
    }
}
