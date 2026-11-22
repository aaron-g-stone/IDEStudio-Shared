import XCTest
import IDEStudioShared

final class ConfTests: XCTestCase {
    let sample = """
    # Inputs of the app
    [monitor:///var/log/app.log]
    index = main
    sourcetype = app:log

    [script://./bin/collect.py]
    interval = 60
    command = one \\
    two

    """

    func testRoundTripKeepsEveryLine() {
        XCTAssertEqual(ConfDocument(text: sample).text, sample)
    }

    func testReadsValuesAndJoinsContinuations() {
        let doc = ConfDocument(text: sample)
        XCTAssertEqual(doc.value("monitor:///var/log/app.log", "index"), "main")
        XCTAssertEqual(doc.value("script://./bin/collect.py", "command"), "one \ntwo")
        XCTAssertEqual(doc.preamble, [.comment("# Inputs of the app")])
    }

    func testSettingAValueChangesOneLine() {
        var doc = ConfDocument(text: sample)
        doc.set("monitor:///var/log/app.log", "index", "app")
        XCTAssertEqual(doc.text, sample.replacingOccurrences(of: "index = main", with: "index = app"))
    }

    func testNewStanzaAndDuplicates() {
        var doc = ConfDocument(text: "[a]\nx = 1\n[a]\ny = 2\n")
        XCTAssertEqual(doc.duplicateStanzas, ["a"])
        doc.set("b", "z", "3")
        XCTAssertEqual(doc.value("b", "z"), "3")
        XCTAssertTrue(doc.text.hasSuffix("\n\n[b]\nz = 3\n"))
    }
}

final class JSONTests: XCTestCase {
    func testKeepsKeyOrderAndNumbers() throws {
        let text = "{\n    \"zeta\": 1.0,\n    \"alpha\": [\n        true,\n        null\n    ],\n    \"name\": \"a\\nb\"\n}"
        let value = try JSONValue.parse(text)
        XCTAssertEqual(value.keys, ["zeta", "alpha", "name"])
        XCTAssertEqual(value.serialized(), text)
        XCTAssertEqual(value["name"]?.stringValue, "a\nb")
    }

    func testPathsCreateObjects() {
        var value = JSONValue.object([])
        value.set(.int(5), at: ["a", "b"])
        value.setValue(.string("x"), at: [.key("list")])
        XCTAssertEqual(value.at("a", "b")?.intValue, 5)
        XCTAssertEqual(value.value(at: [.key("list")])?.stringValue, "x")
    }

    func testErrorsNameTheLine() {
        XCTAssertThrowsError(try JSONValue.parse("{\n  \"a\": \n}")) { error in
            XCTAssertEqual((error as? JSONValue.ParseError)?.line, 3)
        }
    }
}

final class DashboardTests: XCTestCase {
    func testSimpleXMLRoundTrip() throws {
        let text = """
        <form version="1.1" theme="dark">
          <label>Overview</label>
          <fieldset submitButton="false">
            <input type="time" token="time" searchWhenChanged="true">
              <label>Time</label>
              <default><earliest>-24h@h</earliest><latest>now</latest></default>
            </input>
          </fieldset>
          <row><panel><title>Count</title>
            <single><search><query>index=_internal | stats count</query><earliest>$time.earliest$</earliest></search>
              <option name="drilldown">none</option></single>
          </panel></row>
        </form>
        """
        let dashboard = try SimpleXMLDashboard(text: text)
        XCTAssertTrue(dashboard.isForm)
        XCTAssertEqual(dashboard.inputs.first?.token, "time")
        XCTAssertEqual(dashboard.rows.first?.panels.first?.elements.first?.option("drilldown"), "none")
        XCTAssertEqual(try SimpleXMLDashboard(text: dashboard.text), dashboard)
    }

    func testStudioDashboardEditing() throws {
        var dashboard = StudioDashboard(label: "Ops")
        let id = dashboard.addVisualization(type: "splunk.table", at: .init(x: 10, y: 20, w: 300, h: 200))
        XCTAssertEqual(dashboard.items.map(\.id), [id])
        XCTAssertNotNil(dashboard.query(for: id))
        XCTAssertTrue(dashboard.problems.isEmpty)
        let reread = try StudioDashboard(text: dashboard.text)
        XCTAssertTrue(StudioDashboard.looksLikeStudio(dashboard.text))
        XCTAssertEqual(reread.items.first?.rect, .init(x: 10, y: 20, w: 300, h: 200))
        dashboard.remove(id)
        XCTAssertTrue(dashboard.items.isEmpty)
        XCTAssertNil(dashboard.definition["dataSources"]?.members?.first)
    }

    func testNavigation() throws {
        let nav = try NavDocument(text: "<nav search_view=\"search\"><view name=\"overview\" default=\"true\"/><collection label=\"More\"><view name=\"errors\"/></collection></nav>")
        XCTAssertEqual(nav.viewNames, ["overview", "errors"])
        XCTAssertEqual(try NavDocument(text: nav.text), nav)
    }
}
