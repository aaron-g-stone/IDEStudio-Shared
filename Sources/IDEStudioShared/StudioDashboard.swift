import Foundation

/// A Dashboard Studio dashboard: an XML wrapper (`<dashboard version="2">`) around a JSON
/// definition. The definition stays a JSONValue so nothing the designer does not model is lost.
public struct StudioDashboard: Equatable {
    public var label = ""
    public var description = ""
    public var theme = "light"
    public var rootAttributes: [String: String] = [:]
    public var definition: JSONValue = .object([])

    public struct Rect: Equatable {
        public var x, y, w, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    }

    /// A block on the canvas.
    public struct Item: Identifiable, Equatable {
        public var id: String          // key in "visualizations"
        public var type: String        // splunk.line, ...
        public var title: String
        public var rect: Rect
        public init(id: String, type: String, title: String, rect: Rect) { self.id = id; self.type = type; self.title = title; self.rect = rect }
    }

    public struct Input: Identifiable, Equatable {
        public var id: String
        public var type: String
        public var title: String
        public var token: String
        public init(id: String, type: String, title: String, token: String) { self.id = id; self.type = type; self.title = title; self.token = token }
    }

    public static let visualizationTypes: [(type: String, name: String, symbol: String)] = [
        ("splunk.line", "Line", "chart.xyaxis.line"), ("splunk.area", "Area", "chart.line.uptrend.xyaxis"),
        ("splunk.column", "Column", "chart.bar"), ("splunk.bar", "Bar", "chart.bar.xaxis"),
        ("splunk.pie", "Pie", "chart.pie"), ("splunk.singlevalue", "Single Value", "number.square"),
        ("splunk.table", "Table", "tablecells"), ("splunk.events", "Events", "list.bullet.rectangle"),
        ("splunk.scatter", "Scatter", "chart.dots.scatter"), ("splunk.bubble", "Bubble", "circle.grid.cross"),
        ("splunk.fillergauge", "Filler Gauge", "gauge.with.dots.needle.bottom.50percent"),
        ("splunk.map", "Map", "map"), ("splunk.timeline", "Timeline", "calendar.day.timeline.left"),
        ("splunk.treemap", "Treemap", "square.grid.3x3.square"), ("splunk.sankey", "Sankey", "arrow.triangle.branch"),
        ("splunk.punchcard", "Punchcard", "circle.grid.3x3"), ("splunk.linkgraph", "Link Graph", "point.3.connected.trianglepath.dotted"),
        ("splunk.parallelcoordinates", "Parallel Coordinates", "line.3.crossed.swirl.circle"),
        ("splunk.markdown", "Markdown", "text.alignleft"), ("splunk.rectangle", "Rectangle", "rectangle"),
    ]
    public static let inputTypes: [(type: String, name: String)] = [
        ("input.timerange", "Time Range"), ("input.dropdown", "Dropdown"), ("input.multiselect", "Multiselect"),
        ("input.text", "Text"), ("input.number", "Number"),
    ]

    public static func looksLikeStudio(_ text: String) -> Bool {
        guard let open = text.range(of: "<dashboard"), let close = text.range(of: ">", range: open.upperBound..<text.endIndex) else { return false }
        let tag = text[open.upperBound..<close.lowerBound]
        return tag.contains("version=\"2\"") || tag.contains("version='2'")
    }

    public init() {}

    /// A new, empty dashboard with a global time range input.
    public init(label: String, description: String = "", layout: String = "absolute") {
        self.label = label
        self.description = description
        definition = .obj([
            "title": .string(label),
            "description": .string(description),
            "visualizations": .object([]),
            "dataSources": .object([]),
            "defaults": .obj(["dataSources": .obj(["ds.search": .obj(["options": .obj(["queryParameters": .obj([
                "earliest": .string("$global_time.earliest$"), "latest": .string("$global_time.latest$")])])])])]),
            "inputs": .obj(["input_global_trp": .obj([
                "type": .string("input.timerange"), "title": .string("Global Time Range"),
                "options": .obj(["token": .string("global_time"), "defaultValue": .string("-24h@h,now")])])]),
            "layout": .obj([
                "type": .string(layout),
                "options": layout == "absolute" ? .obj(["width": .int(1440), "height": .int(960)]) : .obj(["width": .int(1440)]),
                "structure": .array([]),
                "globalInputs": .array([.string("input_global_trp")])]),
        ])
    }

    public init(text: String) throws {
        let doc = try XMLDocument(xmlString: text, options: [.nodePreserveCDATA])
        guard let root = doc.rootElement(), root.name == "dashboard" else {
            throw NSError(domain: "SplunkAppKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "The root element must be <dashboard version=\"2\">."])
        }
        for a in root.attributes ?? [] { if let n = a.name { rootAttributes[n] = a.stringValue ?? "" } }
        theme = rootAttributes["theme"] ?? "light"
        rootAttributes["theme"] = nil
        rootAttributes["version"] = nil
        label = root.elements(forName: "label").first?.stringValue ?? ""
        description = root.elements(forName: "description").first?.stringValue ?? ""
        let json = root.elements(forName: "definition").first?.stringValue ?? "{}"
        definition = try JSONValue.parse(json)
    }

    public var text: String {
        var d = definition
        if d["title"] != nil || !label.isEmpty { d["title"] = .string(label) }
        if d["description"] != nil || !description.isEmpty { d["description"] = .string(description) }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let extra = rootAttributes.keys.sorted().map { " \($0)=\"\(esc(rootAttributes[$0]!))\"" }.joined()
        let json = d.serialized(indent: 2).replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
        return """
        <dashboard version="2" theme="\(esc(theme))"\(extra)>
          <label>\(esc(label))</label>
          <description>\(esc(description))</description>
          <definition><![CDATA[
        \(json)
          ]]></definition>
        </dashboard>

        """
    }

    // MARK: Layout access

    /// Path to the structure array: tabbed dashboards keep it in layoutDefinitions.
    private var structurePath: [String] {
        if let defs = definition.at("layout", "layoutDefinitions"), let first = defs.keys.first {
            return ["layout", "layoutDefinitions", first, "structure"]
        }
        return ["layout", "structure"]
    }
    private var layoutPath: [String] { Array(structurePath.dropLast()) }

    private func value(at path: [String]) -> JSONValue? {
        var cur: JSONValue? = definition
        for p in path { cur = cur?[p] }
        return cur
    }

    public var layoutType: String { value(at: layoutPath + ["type"])?.stringValue ?? "absolute" }

    public var canvasSize: (width: Double, height: Double) {
        let o = value(at: layoutPath + ["options"])
        let w = o?["width"]?.doubleValue ?? 1440
        var h = o?["height"]?.doubleValue ?? 960
        if layoutType == "grid" { h = max(600, items.map { $0.rect.y + $0.rect.h }.max() ?? 0) }
        return (w, h)
    }

    public mutating func setCanvasSize(width: Double, height: Double) {
        definition.set(.double(width), at: layoutPath + ["options", "width"])
        if layoutType == "absolute" { definition.set(.double(height), at: layoutPath + ["options", "height"]) }
    }

    private var structure: [JSONValue] { value(at: structurePath)?.arrayValue ?? [] }

    public var items: [Item] {
        structure.compactMap { block in
            guard let id = block["item"]?.stringValue, (block["type"]?.stringValue ?? "block") == "block" else { return nil }
            let viz = definition.at("visualizations", id)
            let p = block["position"]
            return Item(id: id, type: viz?["type"]?.stringValue ?? "unknown", title: viz?["title"]?.stringValue ?? "",
                        rect: Rect(x: p?["x"]?.doubleValue ?? 0, y: p?["y"]?.doubleValue ?? 0,
                                   w: p?["w"]?.doubleValue ?? 300, h: p?["h"]?.doubleValue ?? 300))
        }
    }

    public var inputs: [Input] {
        (definition["inputs"]?.members ?? []).map {
            Input(id: $0.key, type: $0.value["type"]?.stringValue ?? "", title: $0.value["title"]?.stringValue ?? "",
                  token: $0.value.at("options", "token")?.stringValue ?? "")
        }
    }

    private func unusedID(_ prefix: String, in section: String) -> String {
        let used = Set(definition[section]?.keys ?? [])
        var n = used.count + 1
        while used.contains("\(prefix)_\(n)") { n += 1 }
        return "\(prefix)_\(n)"
    }

    // MARK: Editing

    @discardableResult
    public mutating func addVisualization(type: String, at rect: Rect, title: String? = nil) -> String {
        let id = unusedID("viz", in: "visualizations")
        var viz: JSONValue = .obj(["type": .string(type)])
        let name = StudioDashboard.visualizationTypes.first { $0.type == type }?.name ?? "Visualization"
        switch type {
        case "splunk.markdown":
            viz["options"] = .obj(["markdown": .string("## Heading\nDescribe this dashboard here.")])
        case "splunk.rectangle":
            break
        default:
            viz["title"] = .string(title ?? name)
            let ds = unusedID("ds_search", in: "dataSources")
            let query: String
            switch type {
            case "splunk.singlevalue", "splunk.fillergauge": query = "index=_internal | stats count"
            case "splunk.table", "splunk.pie", "splunk.bar", "splunk.column", "splunk.treemap": query = "index=_internal | stats count by sourcetype"
            case "splunk.events": query = "index=_internal | head 20"
            default: query = "index=_internal | timechart count by sourcetype"
            }
            definition.set(.obj(["type": .string("ds.search"), "name": .string("\(name) search"),
                                 "options": .obj(["query": .string(query)])]), at: ["dataSources", ds])
            viz["dataSources"] = .obj(["primary": .string(ds)])
        }
        definition.set(viz, at: ["visualizations", id])
        var s = structure
        s.append(.obj(["item": .string(id), "type": .string("block"), "position": StudioDashboard.position(rect)]))
        definition.set(.array(s), at: structurePath)
        return id
    }

    private static func position(_ r: Rect) -> JSONValue {
        .obj(["x": .double(r.x.rounded()), "y": .double(r.y.rounded()), "w": .double(r.w.rounded()), "h": .double(r.h.rounded())])
    }

    public mutating func setRect(_ id: String, _ rect: Rect) {
        var s = structure
        guard let i = s.firstIndex(where: { $0["item"]?.stringValue == id }) else { return }
        s[i]["position"] = StudioDashboard.position(rect)
        definition.set(.array(s), at: structurePath)
    }

    public mutating func remove(_ id: String) {
        let ds = definition.at("visualizations", id, "dataSources", "primary")?.stringValue
        definition.set(nil, at: ["visualizations", id])
        definition.set(.array(structure.filter { $0["item"]?.stringValue != id }), at: structurePath)
        // Drop the data source when nothing else uses it.
        if let ds {
            let stillUsed = (definition["visualizations"]?.members ?? []).contains { $0.value.at("dataSources", "primary")?.stringValue == ds }
            if !stillUsed { definition.set(nil, at: ["dataSources", ds]) }
        }
    }

    /// Moves a block to the front (end of the structure) so it draws above the others.
    public mutating func bringToFront(_ id: String) {
        var s = structure
        guard let i = s.firstIndex(where: { $0["item"]?.stringValue == id }) else { return }
        s.append(s.remove(at: i))
        definition.set(.array(s), at: structurePath)
    }

    public func visualization(_ id: String) -> JSONValue? { definition.at("visualizations", id) }

    public mutating func setVisualization(_ id: String, key: String, _ value: JSONValue?) {
        definition.set(value, at: ["visualizations", id, key])
    }

    public func query(for id: String) -> String? {
        guard let ds = definition.at("visualizations", id, "dataSources", "primary")?.stringValue else { return nil }
        return definition.at("dataSources", ds, "options", "query")?.stringValue
    }

    public mutating func setQuery(_ query: String, for id: String) {
        guard let ds = definition.at("visualizations", id, "dataSources", "primary")?.stringValue else { return }
        definition.set(.string(query), at: ["dataSources", ds, "options", "query"])
    }

    @discardableResult
    public mutating func addInput(type: String) -> String {
        let id = unusedID("input", in: "inputs")
        let name = StudioDashboard.inputTypes.first { $0.type == type }?.name ?? "Input"
        var options: JSONValue = .obj(["token": .string(id.replacingOccurrences(of: "input_", with: "tok_"))])
        switch type {
        case "input.timerange": options["defaultValue"] = .string("-24h@h,now")
        case "input.dropdown", "input.multiselect":
            options["items"] = .array([.obj(["label": .string("All"), "value": .string("*")])])
            options["defaultValue"] = type == "input.dropdown" ? .string("*") : .array([.string("*")])
        default: options["defaultValue"] = .string("")
        }
        definition.set(.obj(["type": .string(type), "title": .string(name), "options": options]), at: ["inputs", id])
        var g = value(at: layoutPath + ["globalInputs"])?.arrayValue ?? []
        g.append(.string(id))
        definition.set(.array(g), at: layoutPath + ["globalInputs"])
        return id
    }

    public mutating func removeInput(_ id: String) {
        definition.set(nil, at: ["inputs", id])
        let g = (value(at: layoutPath + ["globalInputs"])?.arrayValue ?? []).filter { $0.stringValue != id }
        definition.set(.array(g), at: layoutPath + ["globalInputs"])
    }

    /// Problems that would stop Splunk from rendering the dashboard.
    public var problems: [String] {
        var out: [String] = []
        let viz = Set(definition["visualizations"]?.keys ?? [])
        let ds = Set(definition["dataSources"]?.keys ?? [])
        for block in structure {
            if let id = block["item"]?.stringValue, (block["type"]?.stringValue ?? "block") == "block", !viz.contains(id) {
                out.append("The layout places \"\(id)\", which is not in visualizations.")
            }
        }
        for m in definition["visualizations"]?.members ?? [] {
            if m.value["type"]?.stringValue == nil { out.append("Visualization \"\(m.key)\" has no type.") }
            for d in m.value["dataSources"]?.members ?? [] {
                if let name = d.value.stringValue, !ds.contains(name) {
                    out.append("Visualization \"\(m.key)\" uses data source \"\(name)\", which is not defined.")
                }
            }
        }
        return out
    }
}
