import Foundation

/// One entry of an app's navigation bar (default/data/ui/nav/default.xml).
public struct NavItem: Identifiable, Equatable {
    public enum Kind: String, CaseIterable { case view, saved, collection, link = "a", divider }

    public var id = UUID()
    public var kind: Kind
    /// view/saved: `name`. collection: `label`. link: `href`.
    public var attributes: [String: String]
    public var text: String            // link text
    public var children: [NavItem]     // collections only

    public init(kind: Kind, attributes: [String: String] = [:], text: String = "", children: [NavItem] = []) {
        self.kind = kind; self.attributes = attributes; self.text = text; self.children = children
    }

    public static func == (a: NavItem, b: NavItem) -> Bool {
        a.kind == b.kind && a.attributes == b.attributes && a.text == b.text && a.children == b.children
    }

    public var title: String {
        switch kind {
        case .view: return attributes["name"] ?? attributes["source"].map { "Views: \($0)" } ?? "view"
        case .saved: return attributes["name"] ?? attributes["source"].map { "Reports: \($0)" } ?? "report"
        case .collection: return attributes["label"] ?? "Collection"
        case .link: return text.isEmpty ? (attributes["href"] ?? "link") : text
        case .divider: return "Divider"
        }
    }
}

public struct NavDocument: Equatable {
    public var color: String = ""
    public var searchView: String = ""
    public var items: [NavItem] = []

    public static let linkIcons = ["bookmark", "chartgauge", "chartline", "chartpanels", "cog", "circlesfour", "cylinderindex",
                                   "filechart", "filemagnifier", "forwarderuniversal", "layoutoverview", "layerstriple", "magnifier",
                                   "monitor", "filenode", "organizernotebook", "pulse", "star", "tag"]

    public init() {}

    public init(text: String) throws {
        let doc = try XMLDocument(xmlString: text)
        guard let root = doc.rootElement(), root.name == "nav" else {
            throw NSError(domain: "SplunkAppKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "The root element must be <nav>."])
        }
        color = root.attribute(forName: "color")?.stringValue ?? ""
        searchView = root.attribute(forName: "search_view")?.stringValue ?? ""
        items = NavDocument.items(in: root)
    }

    private static func items(in parent: XMLElement) -> [NavItem] {
        (parent.children ?? []).compactMap { node -> NavItem? in
            guard let e = node as? XMLElement, let kind = NavItem.Kind(rawValue: e.name ?? "") else { return nil }
            var attrs: [String: String] = [:]
            for a in e.attributes ?? [] { if let n = a.name { attrs[n] = a.stringValue ?? "" } }
            return NavItem(kind: kind, attributes: attrs,
                           text: kind == .link ? (e.stringValue ?? "") : "",
                           children: kind == .collection ? items(in: e) : [])
        }
    }

    private static let attributeOrder = ["label", "name", "source", "match", "default", "view", "href", "target", "icon"]

    public var text: String {
        let root = XMLElement(name: "nav")
        if !searchView.isEmpty { root.addAttribute(XMLNode.attribute(withName: "search_view", stringValue: searchView) as! XMLNode) }
        if !color.isEmpty { root.addAttribute(XMLNode.attribute(withName: "color", stringValue: color) as! XMLNode) }
        func build(_ item: NavItem) -> XMLElement {
            let e = XMLElement(name: item.kind.rawValue)
            let keys = NavDocument.attributeOrder.filter { item.attributes[$0] != nil }
                + item.attributes.keys.filter { !NavDocument.attributeOrder.contains($0) }.sorted()
            for k in keys where !(item.attributes[k] ?? "").isEmpty {
                e.addAttribute(XMLNode.attribute(withName: k, stringValue: item.attributes[k]!) as! XMLNode)
            }
            if item.kind == .link { e.stringValue = item.text }
            for c in item.children { e.addChild(build(c)) }
            return e
        }
        for i in items { root.addChild(build(i)) }
        return root.xmlString(options: [.nodePrettyPrint, .nodeCompactEmptyElement]) + "\n"
    }

    /// The names of every view the navigation refers to directly.
    public var viewNames: [String] {
        func walk(_ items: [NavItem]) -> [String] {
            items.flatMap { i -> [String] in
                (i.kind == .view ? [i.attributes["name"]].compactMap { $0 } : []) + walk(i.children)
            }
        }
        return walk(items)
    }
}
