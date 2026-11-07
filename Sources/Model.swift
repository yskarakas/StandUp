import AppKit
import SwiftUI
import ServiceManagement

enum Phase: Equatable {
    case sitting, paused, due, moving

    var tint: Color {
        switch self {
        case .sitting: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .paused:  return Color.gray
        case .due:     return Color(red: 0.98, green: 0.52, blue: 0.16)
        case .moving:  return Color(red: 0.18, green: 0.72, blue: 0.42)
        }
    }
    var symbol: String {
        switch self {
        case .sitting: return "chair.fill"
        case .paused:  return "pause.fill"
        case .due:     return "figure.wave"
        case .moving:  return "figure.walk"
        }
    }
    var title: String {
        switch self {
        case .sitting: return "Sitting"
        case .paused:  return "Paused"
        case .due:     return "Time to stand up"
        case .moving:  return "Move around"
        }
    }
}

let waterTint = Color(red: 0.13, green: 0.62, blue: 0.90)

private let moveTips = [
    "Walk to the window and look far away.",
    "Ten slow shoulder rolls.",
    "Fifteen calf raises.",
    "Climb a flight of stairs.",
    "Stretch your hip flexors, both sides.",
    "Walk around the room while you think.",
    "Reach for the ceiling, then touch your toes.",
    "Make a cup of tea — standing up.",
    "A few deep breaths by an open window.",
    "Roll your neck gently, five times each way.",
]

@MainActor
final class StandModel: ObservableObject {
    // Timer state
    @Published private(set) var phase: Phase = .sitting
    /// Remaining seconds (sitting / paused / moving) or overdue seconds (due).
    @Published private(set) var seconds = 0
    @Published private(set) var total = 1
    @Published private(set) var tip = moveTips[0]
    @Published private(set) var welcomeBack = false
    @Published private(set) var drankThisBreak = false

    // Today's numbers (focus / break time is flushed in about every 30 s)
    @Published private(set) var today = DayStats()

    // Settings
    @Published var sitMinutes: Int    { didSet { d.set(sitMinutes, forKey: "sitMinutes") } }
    @Published var breakMinutes: Int  { didSet { d.set(breakMinutes, forKey: "breakMinutes") } }
    @Published var snoozeMinutes: Int { didSet { d.set(snoozeMinutes, forKey: "snoozeMinutes") } }
    @Published var glassMl: Int       { didSet { d.set(glassMl, forKey: "glassMl") } }
    @Published var popUpWhenDue: Bool { didSet { d.set(popUpWhenDue, forKey: "popUpWhenDue") } }
    /// 0 = icon only, 1 = minutes, 2 = minutes:seconds
    @Published var menuBarTime: Int   { didSet { d.set(menuBarTime, forKey: "menuBarTime") } }
    @Published var soundOn: Bool      { didSet { d.set(soundOn, forKey: "soundOn") } }
    @Published var launchAtLogin: Bool { didSet { applyLoginItem() } }
    @Published var profile: Profile {
        didSet {
            if let data = try? JSONEncoder().encode(profile) { d.set(data, forKey: "profile") }
            edit { $0.goalMl = goalMl }
            store.saveIfNeeded()
        }
    }

    // Hooks set by the app delegate
    var openAnalysis: () -> Void = {}
    var openProfile: () -> Void = {}

    let store = HistoryStore()
    private let d = UserDefaults.standard
    private var todayKey = ""
    private var deadline = Date()
    private var phaseStart = Date()
    private var lastChime = Date()
    private var lastTick = Date()
    private var awaySince: Date?
    private var pendingWork: Double = 0
    private var pendingBreak: Double = 0
    private var ticksSinceFlush = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    var plan: HydrationPlan { HydrationPlan(profile) }
    var goalMl: Int { profile.customGoalMl ?? plan.goalMl }
    var glassesGoal: Int { Int((Double(goalMl) / Double(max(glassMl, 1))).rounded(.up)) }

    init() {
        d.register(defaults: [
            "sitMinutes": 25, "breakMinutes": 5, "snoozeMinutes": 5, "glassMl": 250,
            "popUpWhenDue": true, "menuBarTime": 1, "soundOn": true,
        ])
        sitMinutes = d.integer(forKey: "sitMinutes")
        breakMinutes = d.integer(forKey: "breakMinutes")
        snoozeMinutes = d.integer(forKey: "snoozeMinutes")
        glassMl = d.integer(forKey: "glassMl")
        popUpWhenDue = d.bool(forKey: "popUpWhenDue")
        menuBarTime = d.integer(forKey: "menuBarTime")
        soundOn = d.bool(forKey: "soundOn")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let data = d.data(forKey: "profile"), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = p
        } else {
            profile = Profile()
        }

        rolloverIfNeeded()
        migrateOldCounters()
        startSitting()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        observeAway()
    }

    // MARK: Derived

    var progress: Double {
        switch phase {
        case .due: return 1
        default: return max(0, min(1, 1 - Double(seconds) / Double(max(total, 1))))
        }
    }

    var clock: String {
        let s = max(seconds, 0)
        let str = String(format: "%d:%02d", s / 60, s % 60)
        return phase == .due ? "+" + str : str
    }

    var subtitle: String {
        switch phase {
        case .sitting: return welcomeBack ? "Welcome back — that counted as a break." : "Next stand-up break in"
        case .paused:  return "Timer paused"
        case .due:     return "You've been sitting a while. Grab some water on the way."
        case .moving:  return tip
        }
    }

    // MARK: Timer actions

    func startSitting(minutes: Int? = nil) {
        let m = max(1, minutes ?? sitMinutes)
        total = m * 60
        deadline = Date().addingTimeInterval(TimeInterval(total))
        phaseStart = Date()
        seconds = total
        phase = .sitting
    }

    func standUp() {
        welcomeBack = false
        if phase != .due { drankThisBreak = false }
        tip = moveTips.randomElement() ?? moveTips[0]
        total = max(1, breakMinutes) * 60
        deadline = Date().addingTimeInterval(TimeInterval(total))
        phaseStart = Date()
        seconds = total
        phase = .moving
    }

    func snooze() {
        welcomeBack = false
        edit { $0.snoozes += 1 }
        store.saveIfNeeded()
        startSitting(minutes: snoozeMinutes)
    }

    /// Ends the move break. Counts as a break if completed or at least a minute long.
    func backToDesk(completed: Bool = false) {
        guard phase == .moving else { return }
        if completed || Date().timeIntervalSince(phaseStart) >= 60 {
            edit { $0.breaks += 1 }
            flush()
        }
        if completed { chime("Tink") }
        startSitting()
    }

    func togglePause() {
        switch phase {
        case .sitting:
            phase = .paused
        case .paused:
            deadline = Date().addingTimeInterval(TimeInterval(seconds))
            phase = .sitting
        default: break
        }
    }

    func restart() {
        welcomeBack = false
        startSitting()
    }

    // MARK: Water

    func addGlass() {
        let before = today.waterMl
        edit {
            $0.waterMl += glassMl
            $0.glasses += 1
            if $0.goalMl == 0 { $0.goalMl = goalMl }
        }
        if phase == .moving || phase == .due { drankThisBreak = true }
        if before < goalMl && today.waterMl >= goalMl { chime("Hero") }
        store.saveIfNeeded()
    }

    func removeGlass() {
        guard today.glasses > 0 else { return }
        edit {
            $0.glasses -= 1
            $0.waterMl = max(0, $0.waterMl - glassMl)
        }
        store.saveIfNeeded()
    }

    // MARK: Clock

    private func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        rolloverIfNeeded()

        if awaySince == nil, delta > 0, delta < 5 {
            switch phase {
            case .sitting, .due: pendingWork += delta
            case .moving: pendingBreak += delta
            case .paused: break
            }
        }
        ticksSinceFlush += 1
        if ticksSinceFlush >= 30 { flush() }

        switch phase {
        case .sitting:
            let r = Int(deadline.timeIntervalSince(now).rounded(.up))
            if r <= 0 { becomeDue() } else { setSeconds(r) }
        case .moving:
            let r = Int(deadline.timeIntervalSince(now).rounded(.up))
            if r <= 0 { backToDesk(completed: true) } else { setSeconds(r) }
        case .due:
            setSeconds(Int(now.timeIntervalSince(phaseStart)))
            if awaySince == nil, now.timeIntervalSince(lastChime) >= Double(max(snoozeMinutes, 1) * 60) {
                chime("Glass")
                lastChime = now
            }
        case .paused:
            break
        }
    }

    private func becomeDue() {
        welcomeBack = false
        drankThisBreak = false
        phaseStart = Date()
        lastChime = Date()
        total = 1
        seconds = 0
        phase = .due
        if awaySince == nil { chime("Glass") }
    }

    private func setSeconds(_ s: Int) { if s != seconds { seconds = s } }

    private func chime(_ name: String) {
        guard soundOn else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: Day bookkeeping

    private func edit(_ change: (inout DayStats) -> Void) {
        var t = today
        change(&t)
        if t != today { today = t }
        store.set(today, for: todayKey)
    }

    /// Moves accumulated focus / break time into today's record and saves to disk if anything changed.
    func flush() {
        ticksSinceFlush = 0
        if pendingWork > 0 || pendingBreak > 0 {
            let w = pendingWork, b = pendingBreak
            pendingWork = 0
            pendingBreak = 0
            edit {
                $0.workSeconds += w
                $0.breakSeconds += b
            }
        }
        store.saveIfNeeded()
    }

    private func rolloverIfNeeded() {
        let key = DayKey.key(Date())
        guard key != todayKey else { return }
        if !todayKey.isEmpty { flush() }
        todayKey = key
        var t = store.stats(for: key)
        if t.goalMl == 0 { t.goalMl = goalMl }
        today = t
        store.set(t, for: key)
    }

    /// Version 1.0 kept today's counters in UserDefaults.
    private func migrateOldCounters() {
        guard let day = d.string(forKey: "statsDay") else { return }
        if day == todayKey, today.breaks == 0, today.snoozes == 0 {
            let b = d.integer(forKey: "standsToday"), s = d.integer(forKey: "snoozesToday")
            edit { $0.breaks += b; $0.snoozes += s }
            store.saveIfNeeded()
        }
        ["statsDay", "standsToday", "snoozesToday", "showWidget", "widgetTopRight"].forEach(d.removeObject)
    }

    // MARK: Away detection (lock / sleep counts as a break if long enough)

    private func observeAway() {
        let dnc = DistributedNotificationCenter.default()
        let wnc = NSWorkspace.shared.notificationCenter
        let leave: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.awaySince == nil else { return }
                self.flush()
                self.awaySince = Date()
            }
        }
        let back: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.returned() }
        }
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: leave))
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: back))
        observers.append(wnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: leave))
        observers.append(wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: back))
    }

    private func returned() {
        guard let since = awaySince else { return }
        awaySince = nil
        lastTick = Date()
        rolloverIfNeeded()
        guard phase != .paused else { return }
        if Date().timeIntervalSince(since) >= Double(max(breakMinutes, 1) * 60) {
            edit { $0.breaks += 1 }
            store.saveIfNeeded()
            startSitting()
            welcomeBack = true
        }
    }

    private func applyLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("StandUp: login item change failed: \(error.localizedDescription)")
        }
    }
}

enum Fmt {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()
    static func int(_ v: Int) -> String { grouped.string(from: NSNumber(value: v)) ?? "\(v)" }
    static func ml(_ v: Int) -> String { "\(int(v)) ml" }
    static func liters(_ v: Int) -> String { String(format: "%.1f L", Double(v) / 1000) }
    static func duration(_ s: Double) -> String {
        let m = Int(s / 60)
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
    static func decimal(_ v: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", v) }
}
