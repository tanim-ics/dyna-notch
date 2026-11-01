import XCTest
@testable import DynaNotchCore

final class AgentTests: XCTestCase {
    func testDetail() {
        XCTAssertEqual(AgentSummary.detail(tool: "Bash", input: ["command": "npm test", "description": "Run"]), "npm test")
        XCTAssertEqual(AgentSummary.detail(tool: "Edit", input: ["file_path": "/Users/me/app/Sources/App.swift"]),
                       "Sources/App.swift")
        XCTAssertEqual(AgentSummary.detail(tool: "WebFetch", input: ["url": "https://github.com/x/y", "prompt": "p"]),
                       "github.com")
        XCTAssertEqual(AgentSummary.detail(tool: "Grep", input: ["pattern": "TODO"]), "TODO")
        XCTAssertEqual(AgentSummary.detail(tool: "Bash", input: ["command": "a\nb"]), "a ⏎ b")
        XCTAssertEqual(AgentSummary.detail(tool: "Bash", input: ["command": String(repeating: "x", count: 300)]).count, 160)
        XCTAssertEqual(AgentSummary.detail(tool: "Mystery", input: [:]), "Mystery")
    }

    func testProject() {
        XCTAssertEqual(AgentSummary.project(cwd: "/Users/me/Desktop/dyna-notch"), "dyna-notch")
        XCTAssertEqual(AgentSummary.project(cwd: ""), "Claude")
    }

    func testStatusDetail() {
        XCTAssertEqual(AgentSummary.statusDetail(event: "PreToolUse", tool: "Bash", input: ["command": "swift test"]),
                       "Running swift test")
        XCTAssertEqual(AgentSummary.statusDetail(event: "PreToolUse", tool: "Edit", input: ["file_path": "/a/b/App.swift"]),
                       "Editing App.swift")
        XCTAssertEqual(AgentSummary.statusDetail(event: "Stop", tool: "", input: [:]), "Done")
        XCTAssertEqual(AgentSummary.statusDetail(event: "UserPromptSubmit", tool: "", input: [:]), "Thinking…")
        XCTAssertEqual(AgentSummary.statusDetail(event: "Notification", tool: "", input: [:]), "Waiting for you")
    }

    func testRequestParse() {
        let json = #"{"id":"17-42","session":"s1","cwd":"/x/proj","tool":"Bash","input":{"command":"rm -rf build"},"createdAt":1793527200.5}"#
        let r = AgentRequest.parse(Data(json.utf8))
        XCTAssertEqual(r?.id, "17-42")
        XCTAssertEqual(r?.project, "proj")
        XCTAssertEqual(r?.detail, "rm -rf build")
        XCTAssertEqual(r?.createdAt.timeIntervalSince1970 ?? 0, 1_793_527_200.5, accuracy: 0.001)
        XCTAssertNil(AgentRequest.parse(Data(#"{"tool":"Bash"}"#.utf8)))
    }

    func testStatusParse() {
        let json = #"{"session":"s1","cwd":"/x/proj","event":"Stop","tool":"","input":{},"at":10}"#
        let s = AgentSessionStatus.parse(Data(json.utf8))
        XCTAssertEqual(s?.done, true)
        XCTAssertEqual(s?.detail, "Done")
        XCTAssertEqual(s?.project, "proj")
    }

    func testDecisionOutput() throws {
        let allow = try XCTUnwrap(AgentDecision.allow.hookOutput)
        let obj = try JSONSerialization.jsonObject(with: Data(allow.utf8)) as? [String: Any]
        let out = obj?["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(out?["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((out?["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        XCTAssertTrue(AgentDecision.deny.hookOutput?.contains(#""behavior":"deny""#) == true)
        XCTAssertNil(AgentDecision.terminal.hookOutput)
    }

    func testButtonThirds() {
        XCTAssertEqual(AgentDecision.button(at: CGPoint(x: 20, y: 80), cardWidth: 480, titleRowHeight: 32), .deny)
        XCTAssertEqual(AgentDecision.button(at: CGPoint(x: 240, y: 80), cardWidth: 480, titleRowHeight: 32), .terminal)
        XCTAssertEqual(AgentDecision.button(at: CGPoint(x: 470, y: 80), cardWidth: 480, titleRowHeight: 32), .allow)
        XCTAssertNil(AgentDecision.button(at: CGPoint(x: 470, y: 20), cardWidth: 480, titleRowHeight: 32))   // title row
        XCTAssertNil(AgentDecision.button(at: CGPoint(x: 600, y: 80), cardWidth: 480, titleRowHeight: 32))
    }

    func testAgentActivityKinds() {
        let r = ActivityKind.agentRequest(id: "1", project: "p", tool: "Bash", detail: "ls")
        let s = ActivityKind.agentStatus(project: "p", detail: "Done", done: true)
        XCTAssertEqual(r.category, s.category)
        XCTAssertGreaterThan(r.priority, ActivityKind.notification(title: "", body: "", symbol: "").priority)
        XCTAssertFalse(r.isQuietedDuringFocus)
        let notch = NotchMetrics(width: 185, height: 32, hasPhysicalNotch: true)
        let size = IslandLayout.size(for: .activity(LiveActivity(kind: r, postedAt: Date(), expiresAt: Date())),
                                     notch: notch, hudStyle: .compact)
        XCTAssertEqual(size.height, 32 + 66)
    }
}
