import Foundation

/// What Lifeboard's `GET /api/widgets` returns (lib/widget-feed-rules.js in the Lifeboard repo).
/// Every part may be null when Lifeboard could not read it; widgets then show "not available".
public struct Feed: Codable, Equatable {
    public var ok: Bool
    public var error: String?
    public var day: String?
    public var time: String?
    public var tasks: Tasks?
    public var meds: Meds?
    public var weather: Weather?

    public struct Tasks: Codable, Equatable {
        public var count: Int
        public var items: [TaskItem]
    }

    public struct TaskItem: Codable, Equatable, Identifiable {
        public var id: FlexibleID
        public var title: String
        public var doing: Bool
    }

    public struct Meds: Codable, Equatable {
        public var last: Last?
        public var next: Next?
        public struct Last: Codable, Equatable { public var name: String; public var at: String; public var agoMin: Int? }
        public struct Next: Codable, Equatable { public var name: String; public var at: String; public var late: Bool }
    }

    public struct Weather: Codable, Equatable {
        public var icon: String?
        public var label: String?
        public var min: Int?
        public var max: Int?
        public var rain: Double?
    }

    public static func decode(_ data: Data) throws -> Feed {
        try JSONDecoder().decode(Feed.self, from: data)
    }
}

/// Postgres bigint ids arrive as strings, small ones as numbers; either works.
public struct FlexibleID: Codable, Hashable {
    public let value: String

    public init(_ value: String) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else { value = String(try c.decode(Double.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// Plain-language lines the widgets show, kept here so they can be tested.
public enum FeedText {
    public static func tasksHeadline(_ tasks: Feed.Tasks?) -> String {
        guard let t = tasks else { return "Tasks not available" }
        switch t.count {
        case 0: return "Nothing due today"
        case 1: return "1 task due today"
        default: return "\(t.count) tasks due today"
        }
    }

    public static func medsLine(_ meds: Feed.Meds?) -> String {
        guard let m = meds else { return "Medication times not available" }
        var parts: [String] = []
        if let last = m.last { parts.append("Last: \(last.name) at \(last.at)") }
        if let next = m.next { parts.append("Next: \(next.name) at \(next.at)\(next.late ? " (late)" : "")") }
        return parts.isEmpty ? "No doses logged today" : parts.joined(separator: " · ")
    }

    public static func weatherLine(_ w: Feed.Weather?) -> String {
        guard let w = w else { return "No forecast right now" }
        var parts: [String] = []
        if let icon = w.icon, let label = w.label { parts.append("\(icon) \(label)") }
        switch (w.min, w.max) {
        case let (lo?, hi?): parts.append("\(lo)°–\(hi)°")
        case let (lo?, nil): parts.append("low \(lo)°")
        case let (nil, hi?): parts.append("high \(hi)°")
        default: break
        }
        if let rain = w.rain { parts.append("\(Int(rain.rounded()))% rain") }
        return parts.isEmpty ? "No forecast right now" : parts.joined(separator: " · ")
    }
}
