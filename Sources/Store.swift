import Foundation

/// Everything recorded for one calendar day.
struct DayStats: Codable, Equatable {
    var workSeconds: Double = 0   // time spent sitting at the desk (timer running or overdue)
    var breakSeconds: Double = 0  // time spent in move breaks
    var breaks: Int = 0
    var snoozes: Int = 0
    var waterMl: Int = 0
    var glasses: Int = 0
    var goalMl: Int = 0           // the water goal that was active on that day

    var isEmpty: Bool { workSeconds < 1 && breaks == 0 && waterMl == 0 && snoozes == 0 }
    var metGoal: Bool { goalMl > 0 && waterMl >= goalMl }
}

enum DayKey {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.date(from: key) }
}

/// Day-by-day history, stored as JSON in ~/Library/Application Support/StandUp/history.json
@MainActor
final class HistoryStore {
    private(set) var days: [String: DayStats] = [:]
    let fileURL: URL
    private var dirty = false

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = ProcessInfo.processInfo.environment["STANDUP_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? base.appendingPathComponent("StandUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) {
            days = decoded
        }
    }

    func stats(for key: String) -> DayStats { days[key] ?? DayStats() }

    func set(_ stats: DayStats, for key: String) {
        guard days[key] != stats else { return }
        days[key] = stats
        dirty = true
    }

    func hasEntry(_ key: String) -> Bool { days[key] != nil }

    func saveIfNeeded() {
        guard dirty else { return }
        dirty = false
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        try? enc.encode(days).write(to: fileURL, options: .atomic)
    }

    func csv() -> String {
        var lines = ["date,focus_minutes,break_minutes,breaks,snoozes,water_ml,glasses,goal_ml,goal_met"]
        for key in days.keys.sorted() {
            let d = days[key]!
            lines.append([key,
                          String(Int(d.workSeconds / 60)), String(Int(d.breakSeconds / 60)),
                          String(d.breaks), String(d.snoozes), String(d.waterMl), String(d.glasses),
                          String(d.goalMl), d.metGoal ? "yes" : "no"].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
