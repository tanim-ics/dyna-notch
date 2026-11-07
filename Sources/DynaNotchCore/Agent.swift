import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A Claude Code permission request waiting in the notch (CONTRACTS §6.14).
public struct AgentRequest: Equatable, Identifiable {
    public var id: String
    public var session: String
    public var cwd: String
    public var tool: String
    public var detail: String
    public var createdAt: Date

    public init(id: String, session: String, cwd: String, tool: String, detail: String, createdAt: Date) {
        self.id = id
        self.session = session
        self.cwd = cwd
        self.tool = tool
        self.detail = detail
        self.createdAt = createdAt
    }

    public var project: String { AgentSummary.project(cwd: cwd) }

    /// The JSON the hook script writes to `requests/<id>.json`.
    public static func parse(_ data: Data) -> AgentRequest? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String, AgentRequest.isValidID(id) else { return nil }
        let tool = obj["tool"] as? String ?? ""
        let input = obj["input"] as? [String: Any] ?? [:]
        let created = (obj["createdAt"] as? NSNumber)?.doubleValue ?? 0
        return AgentRequest(id: id, session: obj["session"] as? String ?? "", cwd: obj["cwd"] as? String ?? "",
                            tool: tool, detail: AgentSummary.detail(tool: tool, input: input),
                            createdAt: Date(timeIntervalSince1970: created))
    }
}

public enum AgentDecision: String, Equatable, CaseIterable {
    case allow, deny, terminal

    /// What `agent-hook.pl` prints for this decision (nil: no output, Claude asks in the terminal).
    public var hookOutput: String? {
        switch self {
        case .allow:
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        case .deny:
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from DynaNotch"}}}"#
        case .terminal:
            return nil
        }
    }

    /// The card's buttons are equal thirds below its title row: Deny · Terminal · Allow. `point` is in the card's
    /// own (unscaled) coordinates; nil on the title row or outside the card.
    public static func button(at point: CGPoint, cardWidth: CGFloat, titleRowHeight: CGFloat) -> AgentDecision? {
        guard cardWidth > 0, point.y > titleRowHeight, point.x >= 0, point.x <= cardWidth else { return nil }
        let third = cardWidth / 3
        return point.x < third ? .deny : point.x < 2 * third ? .terminal : .allow
    }

    /// Status shown after answering.
    public var label: String {
        switch self {
        case .allow: return "Allowed"
        case .deny: return "Denied"
        case .terminal: return "Ask in Terminal"
        }
    }
}

/// One line of what a Claude Code session is doing, from the `status/<session>.json` files.
public struct AgentSessionStatus: Equatable {
    public var session: String
    public var project: String
    public var detail: String
    public var done: Bool
    public var at: Date

    public init(session: String, project: String, detail: String, done: Bool, at: Date) {
        self.session = session
        self.project = project
        self.detail = detail
        self.done = done
        self.at = at
    }

    public static func parse(_ data: Data) -> AgentSessionStatus? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = obj["session"] as? String else { return nil }
        let event = obj["event"] as? String ?? ""
        let detail = AgentSummary.statusDetail(event: event, tool: obj["tool"] as? String ?? "",
                                               input: obj["input"] as? [String: Any] ?? [:])
        return AgentSessionStatus(session: session, project: AgentSummary.project(cwd: obj["cwd"] as? String ?? ""),
                                  detail: detail, done: event == "Stop",
                                  at: Date(timeIntervalSince1970: (obj["at"] as? NSNumber)?.doubleValue ?? 0))
    }
}

public enum AgentSummary {
    /// Folder name of the session's working directory ("dyna-notch").
    public static func project(cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "Claude" : name
    }

    /// The most telling part of a tool call: the command, the file, the URL's host, the pattern.
    public static func detail(tool: String, input: [String: Any]) -> String {
        func string(_ key: String) -> String? {
            (input[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        let text: String
        if let command = string("command") {
            text = command
        } else if let path = string("file_path") ?? string("notebook_path") ?? string("path") {
            let parts = path.split(separator: "/")
            text = parts.suffix(2).joined(separator: "/")
        } else if let url = string("url") {
            text = URL(string: url)?.host ?? url
        } else if let pattern = string("pattern") ?? string("query") ?? string("prompt") ?? string("description") {
            text = pattern
        } else {
            text = input.values.compactMap { $0 as? String }.first ?? tool
        }
        let oneLine = text.replacingOccurrences(of: "\n", with: " ⏎ ")
        return oneLine.count > 160 ? String(oneLine.prefix(159)) + "…" : oneLine
    }

    /// Pill text for a status event.
    public static func statusDetail(event: String, tool: String, input: [String: Any]) -> String {
        switch event {
        case "Stop": return "Done"
        case "Notification": return "Waiting for you"
        case "UserPromptSubmit": return "Thinking…"
        case "PreToolUse":
            let d = detail(tool: tool, input: input)
            let short = d.count > 40 ? String(d.prefix(39)) + "…" : d
            switch tool {
            case "Bash": return "Running \(short)"
            case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing \((short as NSString).lastPathComponent)"
            case "Read": return "Reading \((short as NSString).lastPathComponent)"
            case "Grep", "Glob": return "Searching"
            case "WebFetch", "WebSearch": return "Browsing \(short)"
            case "Task", "Agent": return "Delegating"
            default: return tool.isEmpty ? "Working…" : tool
            }
        default: return "Working…"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
