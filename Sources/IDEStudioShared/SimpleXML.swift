import Foundation

/// A Simple XML dashboard (`<dashboard version="1.1">` or `<form>`), modelled far enough for the
/// visual designer. XML the designer does not model is kept as raw text and written back.
public struct SimpleXMLDashboard: Equatable {
    public var isForm = false
    public var rootAttributes: [String: String] = ["version": "1.1"]
    public var label = ""
    public var description = ""
    public var fieldsetAttributes: [String: String] = [:]
    public var inputs: [SXInput] = []
    public var rows: [SXRow] = []
    /// Top-level elements the designer leaves alone (base searches, <init>, ...).
    public var extras: [String] = []

    public init() {}

    public static let elementKinds = ["chart", "table", "single", "event", "map", "html", "viz"]
    public static let inputTypes = ["time", "text", "dropdown", "multiselect", "radio", "checkbox", "link"]
    public static let chartTypes = ["line", "area", "column", "bar", "pie", "scatter", "bubble", "radialGauge", "fillerGauge", "markerGauge"]

    public struct SXRow: Identifiable, Equatable {
        public var id = UUID()
        public var attributes: [String: String] = [:]
        public var panels: [SXPanel] = []
        public init(panels: [SXPanel] = []) { self.panels = panels }
        public static func == (a: SXRow, b: SXRow) -> Bool { a.attributes == b.attributes && a.panels == b.panels }
    }

    public struct SXPanel: Identifiable, Equatable {
        public var id = UUID()
        public var attributes: [String: String] = [:]
        public var title = ""
        public var inputs: [SXInput] = []
        public var elements: [SXElement] = []
        public var extras: [String] = []
        public init(title: String = "", elements: [SXElement] = []) { self.title = title; self.elements = elements }
        public static func == (a: SXPanel, b: SXPanel) -> Bool {
            a.attributes == b.attributes && a.title == b.title && a.inputs == b.inputs && a.elements == b.elements && a.extras == b.extras
        }
    }

    public struct SXElement: Identifiable, Equatable {
        public var id = UUID()
        public var kind: String
        public var attributes: [String: String] = [:]
        public var title = ""
        public var hasSearch = true
        public var searchAttributes: [String: String] = [:]
        public var query = ""
        public var earliest = ""
        public var latest = ""
        public var searchExtras: [String] = []
        public var options: [SXOption] = []
        public var htmlContent = ""            // inner XML of <html>
        public var extras: [String] = []       // drilldown, fields, format, ...

        public init(kind: String, title: String = "", query: String = "", earliest: String = "-24h@h", latest: String = "now") {
            self.kind = kind; self.title = title; self.query = query; self.earliest = earliest; self.latest = latest
            hasSearch = kind != "html"
        }
        public static func == (a: SXElement, b: SXElement) -> Bool {
            a.kind == b.kind && a.attributes == b.attributes && a.title == b.title && a.hasSearch == b.hasSearch
                && a.searchAttributes == b.searchAttributes && a.query == b.query && a.earliest == b.earliest && a.latest == b.latest
                && a.searchExtras == b.searchExtras && a.options == b.options && a.htmlContent == b.htmlContent && a.extras == b.extras
        }

        public func option(_ name: String) -> String? { options.first { $0.name == name }?.value }
        public mutating func setOption(_ name: String, _ value: String?) {
            if let i = options.firstIndex(where: { $0.name == name }) {
                if let value, !value.isEmpty { options[i].value = value } else { options.remove(at: i) }
            } else if let value, !value.isEmpty {
                options.append(SXOption(name: name, value: value))
            }
        }
    }

    public struct SXOption: Equatable {
        public var name: String
        public var value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    public struct SXInput: Identifiable, Equatable {
        public var id = UUID()
        public var type: String
        public var attributes: [String: String] = [:]   // token, searchWhenChanged, ...
        public var label = ""
        public var defaultValue = ""
        public var defaultEarliest = ""                  // time inputs
        public var defaultLatest = ""
        public var choices: [SXOption] = []              // name = value, value = label
        public var extras: [String] = []

        public init(type: String, token: String, label: String = "") {
            self.type = type; self.label = label
            attributes = ["token": token, "searchWhenChanged": "true"]
            if type == "time" { defaultEarliest = "-24h@h"; defaultLatest = "now" }
        }
        public var token: String {
            get { attributes["token"] ?? "" }
            set { attributes["token"] = newValue }
        }
        public static func == (a: SXInput, b: SXInput) -> Bool {
            a.type == b.type && a.attributes == b.attributes && a.label == b.label && a.defaultValue == b.defaultValue
                && a.defaultEarliest == b.defaultEarliest && a.defaultLatest == b.defaultLatest && a.choices == b.choices && a.extras == b.extras
        }
    }

    // MARK: Parsing

    private static func attrs(_ e: XMLElement) -> [String: String] {
        var out: [String: String] = [:]
        for a in e.attributes ?? [] { if let n = a.name { out[n] = a.stringValue ?? "" } }
        return out
    }
    private static func elements(_ e: XMLElement) -> [XMLElement] { (e.children ?? []).compactMap { $0 as? XMLElement } }
    private static func raw(_ e: XMLElement) -> String { e.xmlString(options: [.nodePreserveCDATA]) }

    public init(text: String) throws {
        let doc = try XMLDocument(xmlString: text, options: [.nodePreserveCDATA])
        guard let root = doc.rootElement(), root.name == "dashboard" || root.name == "form" else {
            throw NSError(domain: "SplunkAppKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "The root element must be <dashboard> or <form>."])
        }
        isForm = root.name == "form"
        rootAttributes = SimpleXMLDashboard.attrs(root)
        for e in SimpleXMLDashboard.elements(root) {
            switch e.name {
            case "label": label = e.stringValue ?? ""
            case "description": description = e.stringValue ?? ""
            case "fieldset":
                fieldsetAttributes = SimpleXMLDashboard.attrs(e)
                inputs = SimpleXMLDashboard.elements(e).filter { $0.name == "input" }.map(SimpleXMLDashboard.input)
            case "row":
                var row = SXRow()
                row.attributes = SimpleXMLDashboard.attrs(e)
                row.panels = SimpleXMLDashboard.elements(e).filter { $0.name == "panel" }.map(SimpleXMLDashboard.panel)
                rows.append(row)
            default: extras.append(SimpleXMLDashboard.raw(e))
            }
        }
    }

    private static func panel(_ e: XMLElement) -> SXPanel {
        var p = SXPanel()
        p.attributes = attrs(e)
        for c in elements(e) {
            switch c.name {
            case "title": p.title = c.stringValue ?? ""
            case "input": p.inputs.append(input(c))
            case let n? where elementKinds.contains(n): p.elements.append(element(c))
            default: p.extras.append(raw(c))
            }
        }
        return p
    }

    private static func element(_ e: XMLElement) -> SXElement {
        var el = SXElement(kind: e.name ?? "table", earliest: "", latest: "")
        el.attributes = attrs(e)
        if el.kind == "html" {
            el.hasSearch = false
            el.htmlContent = (e.children ?? []).map { $0.xmlString(options: [.nodePreserveCDATA]) }.joined()
            return el
        }
        el.hasSearch = false
        for c in elements(e) {
            switch c.name {
            case "title": el.title = c.stringValue ?? ""
            case "search":
                el.hasSearch = true
                el.searchAttributes = attrs(c)
                for s in elements(c) {
                    switch s.name {
                    case "query": el.query = s.stringValue ?? ""
                    case "earliest": el.earliest = s.stringValue ?? ""
                    case "latest": el.latest = s.stringValue ?? ""
                    default: el.searchExtras.append(raw(s))
                    }
                }
            case "option":
                el.options.append(SXOption(name: c.attribute(forName: "name")?.stringValue ?? "", value: c.stringValue ?? ""))
            default: el.extras.append(raw(c))
            }
        }
        return el
    }

    private static func input(_ e: XMLElement) -> SXInput {
        var i = SXInput(type: e.attribute(forName: "type")?.stringValue ?? "text", token: "")
        i.attributes = attrs(e)
        i.attributes["type"] = nil
        i.defaultEarliest = ""
        i.defaultLatest = ""
        for c in elements(e) {
            switch c.name {
            case "label": i.label = c.stringValue ?? ""
            case "default":
                let kids = elements(c)
                if kids.isEmpty { i.defaultValue = c.stringValue ?? "" } else {
                    i.defaultEarliest = kids.first { $0.name == "earliest" }?.stringValue ?? ""
                    i.defaultLatest = kids.first { $0.name == "latest" }?.stringValue ?? ""
                }
            case "choice":
                i.choices.append(SXOption(name: c.attribute(forName: "value")?.stringValue ?? "", value: c.stringValue ?? ""))
            default: i.extras.append(raw(c))
            }
        }
        return i
    }

    // MARK: Writing

    private static func make(_ name: String, _ attributes: [String: String] = [:], order: [String] = [], text: String? = nil) -> XMLElement {
        let e = XMLElement(name: name)
        let keys = order.filter { attributes[$0] != nil } + attributes.keys.filter { !order.contains($0) }.sorted()
        for k in keys { e.addAttribute(XMLNode.attribute(withName: k, stringValue: attributes[k]!) as! XMLNode) }
        if let text { e.stringValue = text }
        return e
    }
    private static func addRaw(_ list: [String], to parent: XMLElement) {
        for r in list { if let e = try? XMLElement(xmlString: r) { parent.addChild(e) } }
    }

    public var text: String {
        typealias S = SimpleXMLDashboard
        let root = S.make(isForm || !inputs.isEmpty ? "form" : "dashboard", rootAttributes, order: ["version", "theme", "script", "stylesheet"])
        root.addChild(S.make("label", text: label))
        if !description.isEmpty { root.addChild(S.make("description", text: description)) }
        S.addRaw(extras, to: root)
        if !inputs.isEmpty {
            var fa = fieldsetAttributes
            if fa.isEmpty { fa = ["submitButton": "false"] }
            let fs = S.make("fieldset", fa)
            for i in inputs { fs.addChild(S.build(i)) }
            root.addChild(fs)
        }
        for r in rows {
            let row = S.make("row", r.attributes)
            for p in r.panels {
                let panel = S.make("panel", p.attributes)
                if !p.title.isEmpty { panel.addChild(S.make("title", text: p.title)) }
                for i in p.inputs { panel.addChild(S.build(i)) }
                for el in p.elements { panel.addChild(S.build(el)) }
                S.addRaw(p.extras, to: panel)
                row.addChild(panel)
            }
            root.addChild(row)
        }
        return root.xmlString(options: [.nodePrettyPrint, .nodePreserveCDATA]) + "\n"
    }

    private static func build(_ i: SXInput) -> XMLElement {
        var a = i.attributes
        a["type"] = i.type
        let e = make("input", a, order: ["type", "token", "searchWhenChanged"])
        e.addChild(make("label", text: i.label))
        for c in i.choices { e.addChild(make("choice", ["value": c.name], text: c.value)) }
        if i.type == "time", !(i.defaultEarliest.isEmpty && i.defaultLatest.isEmpty) {
            let d = make("default")
            d.addChild(make("earliest", text: i.defaultEarliest))
            d.addChild(make("latest", text: i.defaultLatest))
            e.addChild(d)
        } else if !i.defaultValue.isEmpty {
            e.addChild(make("default", text: i.defaultValue))
        }
        addRaw(i.extras, to: e)
        return e
    }

    private static func build(_ el: SXElement) -> XMLElement {
        let e = make(el.kind, el.attributes, order: ["id", "type", "depends", "rejects"])
        if el.kind == "html" {
            if let wrapped = try? XMLElement(xmlString: "<html>\(el.htmlContent)</html>") {
                for c in wrapped.children ?? [] { c.detach(); e.addChild(c) }
            } else {
                e.stringValue = el.htmlContent
            }
            return e
        }
        if !el.title.isEmpty { e.addChild(make("title", text: el.title)) }
        if el.hasSearch {
            let s = make("search", el.searchAttributes, order: ["id", "base", "ref"])
            if !el.query.isEmpty || el.searchAttributes["ref"] == nil { s.addChild(make("query", text: el.query)) }
            if !el.earliest.isEmpty { s.addChild(make("earliest", text: el.earliest)) }
            if !el.latest.isEmpty { s.addChild(make("latest", text: el.latest)) }
            addRaw(el.searchExtras, to: s)
            e.addChild(s)
        }
        for o in el.options { e.addChild(make("option", ["name": o.name], text: o.value)) }
        addRaw(el.extras, to: e)
        return e
    }

    // MARK: Editing helpers

    /// A new element of a kind, with a search that returns something on any Splunk instance.
    public static func newElement(kind: String) -> SXElement {
        switch kind {
        case "chart":
            var e = SXElement(kind: "chart", title: "Events over time", query: "index=_internal | timechart count by sourcetype")
            e.options = [SXOption(name: "charting.chart", value: "line"), SXOption(name: "charting.legend.placement", value: "bottom")]
            return e
        case "single":
            var e = SXElement(kind: "single", title: "Event count", query: "index=_internal | stats count")
            e.options = [SXOption(name: "drilldown", value: "none")]
            return e
        case "event": return SXElement(kind: "event", title: "Recent events", query: "index=_internal | head 20")
        case "map": return SXElement(kind: "map", title: "Events by location", query: "index=_internal | iplocation clientip | geostats count")
        case "html":
            var e = SXElement(kind: "html")
            e.htmlContent = "<p>Describe this dashboard here.</p>"
            return e
        case "viz":
            var e = SXElement(kind: "viz", title: "Custom visualization", query: "index=_internal | stats count by sourcetype")
            e.attributes["type"] = "app_name.visualization_name"
            return e
        default:
            var e = SXElement(kind: "table", title: "Events by sourcetype", query: "index=_internal | stats count by sourcetype | sort - count")
            e.options = [SXOption(name: "count", value: "10"), SXOption(name: "drilldown", value: "none")]
            return e
        }
    }

    public func uniqueToken(_ base: String) -> String {
        let used = Set(inputs.map(\.token) + rows.flatMap { $0.panels.flatMap { $0.inputs.map(\.token) } })
        if !used.contains(base) { return base }
        var n = 2
        while used.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }
}
