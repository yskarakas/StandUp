import SwiftUI
import Charts
import UniformTypeIdentifiers

enum Span: String, CaseIterable, Identifiable {
    case today = "Today", week = "Week", month = "Month", sixMonths = "6 Months", year = "Year", all = "All time"
    var id: String { rawValue }
    var dayCount: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 182
        case .year: return 365
        case .all: return nil
        }
    }
}

struct DayEntry {
    let date: Date
    let stats: DayStats
}

private struct Bucket: Identifiable {
    let id: Date
    let water: Double   // ml per active day (or total for a single day)
    let focusHours: Double
    let breaks: Double
    let goal: Double
}

struct Summary {
    var work = 0.0, brk = 0.0
    var breaks = 0, snoozes = 0, water = 0, glasses = 0
    var activeDays = 0, goalDays = 0, goalMetDays = 0
    var calendarDays = 0

    init(_ entries: [DayEntry]) {
        calendarDays = entries.count
        for e in entries {
            let s = e.stats
            work += s.workSeconds; brk += s.breakSeconds
            breaks += s.breaks; snoozes += s.snoozes
            water += s.waterMl; glasses += s.glasses
            if !s.isEmpty { activeDays += 1 }
            if !s.isEmpty && s.goalMl > 0 { goalDays += 1 }
            if s.metGoal { goalMetDays += 1 }
        }
    }
    var perDay: Double { Double(max(activeDays, 1)) }
}

struct AnalysisView: View {
    let model: StandModel
    @State private var span: Span
    @State private var days: [String: DayStats]

    init(model: StandModel, span: Span = .week) {
        self.model = model
        model.flush()
        _span = State(initialValue: span)
        _days = State(initialValue: model.store.days)
    }

    var body: some View {
        let entries = makeEntries()
        let sum = Summary(entries)
        ScrollView {
            content(entries, sum)
        }
        .frame(width: 720, height: 720)
    }

    func content(_ entries: [DayEntry], _ sum: Summary) -> some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Picker("", selection: $span) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 480)
                    Spacer()
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                    Button { exportCSV() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                }

                Text(rangeLabel(entries))
                    .font(.system(size: 12)).foregroundStyle(.secondary)

                cards(sum)

                if span != .today {
                    let (buckets, unit, perDayNote) = makeBuckets(entries)
                    chartCard(title: "Water" + perDayNote, unitLabel: "ml") {
                        let goal = averageGoal(entries)
                        Chart {
                            ForEach(buckets) { b in
                                BarMark(x: .value("Date", b.id, unit: unit), y: .value("ml", b.water))
                                    .foregroundStyle(b.water >= b.goal ? waterTint : waterTint.opacity(0.45))
                            }
                            RuleMark(y: .value("Goal", goal))
                                .foregroundStyle(Color.orange)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("goal \(Fmt.ml(Int(goal)))").font(.system(size: 9)).foregroundStyle(.orange)
                                }
                        }
                    }
                    chartCard(title: "Focus time" + perDayNote, unitLabel: "hours") {
                        Chart(buckets) { b in
                            BarMark(x: .value("Date", b.id, unit: unit), y: .value("h", b.focusHours))
                                .foregroundStyle(Phase.sitting.tint)
                        }
                    }
                    chartCard(title: "Breaks" + perDayNote, unitLabel: "breaks") {
                        Chart(buckets) { b in
                            BarMark(x: .value("Date", b.id, unit: unit), y: .value("Breaks", b.breaks))
                                .foregroundStyle(Phase.moving.tint)
                        }
                    }
                } else {
                    todayWater
                }

                Text("Focus time counts minutes at your desk while the timer runs. A break counts when you move for at least a minute or your Mac is locked/asleep for a full break length.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
    }

    /// The scroll-free page (also used for snapshot tests).
    var page: some View {
        let entries = makeEntries()
        return content(entries, Summary(entries)).frame(width: 720)
    }

    // MARK: Pieces

    private func cards(_ s: Summary) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        let focusHours = s.work / 3600
        return LazyVGrid(columns: cols, spacing: 10) {
            card("Focus time", Fmt.duration(s.work), "chair.fill", Phase.sitting.tint)
            card("Break time", Fmt.duration(s.brk), "figure.walk", Phase.moving.tint)
            card("Breaks", "\(s.breaks)", "checkmark.circle.fill", Phase.moving.tint)
            card("Snoozes", "\(s.snoozes)", "moon.zzz.fill", Phase.due.tint)

            card("Water", Fmt.liters(s.water), "drop.fill", waterTint, sub: Fmt.ml(s.water))
            card("Glasses", "\(s.glasses)", "drop.fill", waterTint)
            card("Water / day", Fmt.ml(Int(Double(s.water) / s.perDay)), "drop.fill", waterTint,
                 sub: "goal \(Fmt.ml(model.goalMl))")
            card("Glasses / day", Fmt.decimal(Double(s.glasses) / s.perDay), "drop.fill", waterTint)

            card("Water goal met", "\(s.goalMetDays) / \(max(s.goalDays, 0)) days", "target", waterTint)
            card("Water streak", "\(streak()) days", "flame.fill", .orange, sub: "goal met in a row")
            card("Focus / day", Fmt.duration(s.work / s.perDay), "clock.fill", Phase.sitting.tint,
                 sub: "\(s.activeDays) active day\(s.activeDays == 1 ? "" : "s")")
            card("Breaks / focus hour", focusHours > 0.05 ? Fmt.decimal(Double(s.breaks) / focusHours) : "–",
                 "gauge.with.dots.needle.33percent", Phase.moving.tint, sub: "aim for ~2")
        }
    }

    private func card(_ title: String, _ value: String, _ symbol: String, _ tint: Color, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub ?? " ").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    private func chartCard<C: View>(title: String, unitLabel: String, @ViewBuilder _ chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(unitLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            chart().frame(height: 140)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.03)))
    }

    private var todayWater: some View {
        let t = days[DayKey.key(Date())] ?? DayStats()
        let goal = t.goalMl > 0 ? t.goalMl : model.goalMl
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Water today").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Fmt.ml(t.waterMl)) of \(Fmt.ml(goal))").font(.system(size: 12).monospacedDigit())
            }
            WaterBar(value: t.waterMl, goal: goal, height: 12)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.03)))
    }

    // MARK: Data

    private func reload() {
        model.flush()
        days = model.store.days
    }

    private func makeEntries() -> [DayEntry] {
        let cal = DayKey.calendar
        let today = cal.startOfDay(for: Date())
        let start: Date
        if let n = span.dayCount {
            start = cal.date(byAdding: .day, value: -(n - 1), to: today) ?? today
        } else {
            start = days.keys.compactMap(DayKey.date).min().map { cal.startOfDay(for: $0) } ?? today
        }
        var out: [DayEntry] = []
        var d = start
        while d <= today {
            out.append(DayEntry(date: d, stats: days[DayKey.key(d)] ?? DayStats()))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    private func makeBuckets(_ entries: [DayEntry]) -> ([Bucket], Calendar.Component, String) {
        let cal = DayKey.calendar
        let unit: Calendar.Component
        switch span {
        case .today, .week, .month: unit = .day
        case .sixMonths, .year: unit = .weekOfYear
        case .all: unit = entries.count > 400 ? .month : (entries.count > 60 ? .weekOfYear : .day)
        }
        if unit == .day {
            let b = entries.map { e in
                Bucket(id: e.date, water: Double(e.stats.waterMl), focusHours: e.stats.workSeconds / 3600,
                       breaks: Double(e.stats.breaks), goal: Double(e.stats.goalMl > 0 ? e.stats.goalMl : model.goalMl))
            }
            return (b, .day, "")
        }
        var groups: [Date: [DayEntry]] = [:]
        for e in entries {
            let key = cal.dateInterval(of: unit, for: e.date)?.start ?? e.date
            groups[key, default: []].append(e)
        }
        let buckets = groups.keys.sorted().map { key -> Bucket in
            let g = groups[key]!
            let active = g.filter { !$0.stats.isEmpty }
            let n = Double(max(active.count, 1))
            let goals = active.map { Double($0.stats.goalMl) }.filter { $0 > 0 }
            return Bucket(id: key,
                          water: active.reduce(0) { $0 + Double($1.stats.waterMl) } / n,
                          focusHours: active.reduce(0) { $0 + $1.stats.workSeconds } / 3600 / n,
                          breaks: active.reduce(0) { $0 + Double($1.stats.breaks) } / n,
                          goal: goals.isEmpty ? Double(model.goalMl) : goals.reduce(0, +) / Double(goals.count))
        }
        return (buckets, unit, unit == .month ? " · daily average per month" : " · daily average per week")
    }

    private func averageGoal(_ entries: [DayEntry]) -> Double {
        let goals = entries.filter { !$0.stats.isEmpty && $0.stats.goalMl > 0 }.map { Double($0.stats.goalMl) }
        return goals.isEmpty ? Double(model.goalMl) : goals.reduce(0, +) / Double(goals.count)
    }

    private func streak() -> Int {
        let cal = DayKey.calendar
        var d = cal.startOfDay(for: Date())
        if !(days[DayKey.key(d)]?.metGoal ?? false) {
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        var n = 0
        while days[DayKey.key(d)]?.metGoal == true {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return n
    }

    private func rangeLabel(_ entries: [DayEntry]) -> String {
        guard let first = entries.first?.date, let last = entries.last?.date else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "en_US")
        if first == last { return f.string(from: first) }
        return "\(f.string(from: first)) – \(f.string(from: last))  ·  \(entries.count) days"
    }

    private func exportCSV() {
        model.flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "StandUp-history-\(DayKey.key(Date())).csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? model.store.csv().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
