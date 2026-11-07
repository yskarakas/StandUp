import SwiftUI

// MARK: - Small building blocks

struct Ring: View {
    var progress: Double
    var tint: Color
    var width: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: width)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct PillButton: ButtonStyle {
    var tint: Color
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(Capsule().fill(prominent ? tint : tint.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct ActionButtons: View {
    @ObservedObject var model: StandModel
    var body: some View {
        let tint = model.phase.tint
        HStack(spacing: 8) {
            switch model.phase {
            case .sitting:
                Button("Pause") { model.togglePause() }
                    .buttonStyle(PillButton(tint: tint))
                Button("I'm up now") { model.standUp() }
                    .buttonStyle(PillButton(tint: tint, prominent: true))
            case .paused:
                Button("Restart") { model.restart() }
                    .buttonStyle(PillButton(tint: Phase.sitting.tint))
                Button("Resume") { model.togglePause() }
                    .buttonStyle(PillButton(tint: Phase.sitting.tint, prominent: true))
            case .due:
                Button("Snooze \(model.snoozeMinutes) min") { model.snooze() }
                    .buttonStyle(PillButton(tint: tint))
                Button("I'm up!") { model.standUp() }
                    .buttonStyle(PillButton(tint: tint, prominent: true))
            case .moving:
                Button("I'm back at my desk") { model.backToDesk() }
                    .buttonStyle(PillButton(tint: tint))
            }
        }
    }
}

struct WaterBar: View {
    var value: Int
    var goal: Int
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(waterTint.opacity(0.15))
                Capsule().fill(waterTint)
                    .frame(width: max(height, g.size.width * min(1, Double(value) / Double(max(goal, 1)))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

struct TodayDots: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(count, 12), id: \.self) { _ in
                Circle().fill(Phase.moving.tint).frame(width: 7, height: 7)
            }
            if count > 12 {
                Text("+\(count - 12)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            if count == 0 {
                Text("No breaks yet").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var model: StandModel
    @State private var showSettings = false

    var body: some View {
        let tint = model.phase.tint
        VStack(spacing: 13) {
            HStack {
                Text("Stand Up").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.phase.title).font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
            }

            ZStack {
                Ring(progress: model.progress, tint: tint, width: 9)
                VStack(spacing: 2) {
                    Image(systemName: model.phase.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(model.clock)
                        .font(.system(size: 31, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(model.phase == .due ? "overdue" : model.phase == .moving ? "of moving left" : "until break")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 136, height: 136)

            Text(model.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ActionButtons(model: model)

            if model.phase == .moving || model.phase == .due {
                waterNudge
            }

            Divider()
            waterSection
            Divider()
            todaySection
            Divider()
            settings

            HStack(spacing: 14) {
                Button { model.openAnalysis() } label: { Label("Analysis", systemImage: "chart.bar.xaxis") }
                Button { model.openProfile() } label: { Label("Profile", systemImage: "person.crop.circle") }
                Spacer()
                Button { model.restart() } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Restart the sitting timer")
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var waterNudge: some View {
        HStack(spacing: 10) {
            Image(systemName: "drop.fill").foregroundStyle(waterTint).font(.system(size: 16))
            if model.drankThisBreak {
                Text("Nice — glass logged. Keep moving!")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("Drink a glass of water while you're up.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("+ \(model.glassMl) ml") { model.addGlass() }
                    .buttonStyle(PillButton(tint: waterTint, prominent: true))
                    .frame(width: 84)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(waterTint.opacity(0.10)))
    }

    private var waterSection: some View {
        let water = model.today.waterMl, goal = model.goalMl
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Water", systemImage: "drop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(waterTint)
                Spacer()
                Text("\(Fmt.int(water)) / \(Fmt.ml(goal))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            WaterBar(value: water, goal: goal)
            HStack(spacing: 8) {
                Text(water >= goal
                     ? "Goal reached — \(model.today.glasses) glasses 🎉"
                     : "\(model.today.glasses) of ~\(model.glassesGoal) glasses (\(model.glassMl) ml)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { model.removeGlass() } label: { Image(systemName: "minus") }
                    .buttonStyle(PillButton(tint: waterTint))
                    .frame(width: 34)
                    .disabled(model.today.glasses == 0)
                    .help("Undo last glass")
                Button("+ Glass") { model.addGlass() }
                    .buttonStyle(PillButton(tint: waterTint, prominent: true))
                    .frame(width: 70)
            }
            if !model.profile.isSet {
                Button { model.openProfile() } label: {
                    Text("Set up your profile for a personal water goal →")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(waterTint)
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Fmt.duration(model.today.workSeconds)) focus · \(model.today.breaks) breaks · \(model.today.snoozes) snoozes")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            TodayDots(count: model.today.breaks)
        }
    }

    private var settings: some View {
        DisclosureGroup(isExpanded: $showSettings) {
            VStack(alignment: .leading, spacing: 8) {
                Stepper("Sit for \(model.sitMinutes) min", value: $model.sitMinutes, in: 5...120, step: 5)
                Stepper("Move for \(model.breakMinutes) min", value: $model.breakMinutes, in: 1...30)
                Stepper("Snooze \(model.snoozeMinutes) min", value: $model.snoozeMinutes, in: 1...30)
                Stepper("Glass size \(model.glassMl) ml", value: $model.glassMl, in: 50...1000, step: 50)
                Toggle("Open this panel when it's time", isOn: $model.popUpWhenDue)
                Toggle("Sounds", isOn: $model.soundOn)
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                HStack {
                    Text("Menu bar")
                    Spacer()
                    Picker("", selection: $model.menuBarTime) {
                        Text("Icon").tag(0)
                        Text("12m").tag(1)
                        Text("12:34").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                Text("New durations apply from the next session. Right-click the menu bar icon for quick actions.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.top, 6)
        } label: {
            Text("Settings").font(.system(size: 11, weight: .semibold))
        }
    }
}
