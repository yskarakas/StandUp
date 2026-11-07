import SwiftUI

/// Asks for body data and shows a step-by-step daily water goal.
struct ProfileView: View {
    let model: StandModel
    var onDone: () -> Void

    @State private var p: Profile
    @State private var useCustom: Bool
    @State private var customMl: Int
    @State private var glassMl: Int

    init(model: StandModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _p = State(initialValue: model.profile)
        _useCustom = State(initialValue: model.profile.customGoalMl != nil)
        _customMl = State(initialValue: model.profile.customGoalMl ?? HydrationPlan(model.profile).goalMl)
        _glassMl = State(initialValue: model.glassMl)
    }

    var body: some View {
        let plan = HydrationPlan(p)
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section {
                    Picker("Sex", selection: $p.sex) {
                        ForEach(Sex.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    NumberRow(title: "Age", value: Binding(get: { Double(p.age) }, set: { p.age = Int($0) }),
                              range: 14...100, step: 1, unit: "years")
                    NumberRow(title: "Weight", value: $p.weightKg, range: 30...250, step: 0.5, unit: "kg")
                    NumberRow(title: "Height", value: $p.heightCm, range: 120...230, step: 1, unit: "cm")
                } header: { Text("About you") }

                Section {
                    Picker("Activity", selection: $p.activity) {
                        ForEach(Activity.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Climate", selection: $p.climate) {
                        ForEach(Climate.allCases) { Text($0.label).tag($0) }
                    }
                    if p.sex == .female {
                        Picker("Status", selection: $p.stage) {
                            ForEach(LifeStage.allCases) { Text($0.label).tag($0) }
                        }
                    }
                } header: { Text("Lifestyle") }

                Section {
                    Toggle("Use my own goal instead", isOn: $useCustom)
                    if useCustom {
                        Stepper("\(Fmt.ml(customMl)) per day", value: $customMl, in: 500...6000, step: 50)
                    }
                    Stepper("Glass size: \(glassMl) ml", value: $glassMl, in: 50...1000, step: 50)
                } header: { Text("Goal") }
            }
            .formStyle(.grouped)
            .frame(width: 380)

            result(plan)
                .frame(width: 380)
        }
        .frame(height: 560)
    }

    @ViewBuilder
    private func result(_ plan: HydrationPlan) -> some View {
        let goal = useCustom ? customMl : plan.goalMl
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your daily drinking goal").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "drop.fill").foregroundStyle(waterTint)
                    Text(Fmt.ml(goal)).font(.system(size: 34, weight: .bold, design: .rounded))
                }
                Text("≈ \(Fmt.decimal(Double(goal) / Double(max(glassMl, 1)))) glasses of \(glassMl) ml · BMI \(Fmt.decimal(plan.bmi))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if useCustom {
                    Text("Custom goal — the estimate below is \(Fmt.ml(plan.goalMl)).")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }

            VStack(spacing: 6) {
                row("Weight rule · \(Int(plan.perKg)) ml × \(Fmt.decimal(p.weightKg)) kg", plan.weightMethodMl)
                row("Body-surface rule · 1,500 ml × \(Fmt.decimal(plan.bsa, 2)) m²", plan.bsaMethodMl)
                row("Total water need (average)", plan.totalNeedMl, bold: true)
                row("≈ 20 % comes from food", -plan.fromFoodMl)
                row("From drinks", plan.fromDrinksMl)
                row("EFSA minimum from drinks (\(p.sex.label.lowercased()))", plan.referenceMl,
                    note: plan.referenceMl > plan.fromDrinksMl ? "used" : nil)
                if plan.activityMl > 0 { row("Activity", plan.activityMl, plus: true) }
                if plan.climateMl > 0 { row("Climate", plan.climateMl, plus: true) }
                if plan.stageMl > 0 { row(p.stage.label, plan.stageMl, plus: true) }
                Divider()
                row("Estimated goal (rounded)", Double(plan.goalMl), bold: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))

            Text("""
            Sources: EFSA Panel on Dietetic Products (2010), Dietary Reference Values for water — \
            adequate total water intake 2.0 L/day (women) and 2.5 L/day (men), 20–30 % from food, \
            +300 ml in pregnancy, +700 ml while breastfeeding. Weight rule 35/30/25 ml per kg by age \
            (≤55 / 56–75 / >75 y) and body-surface rule 1,500 ml/m² (Mosteller) are common clinical \
            estimates. Exercise: ACSM advises replacing sweat losses (≈0.4–0.8 L per hour).
            This is an estimate for healthy adults, not medical advice. With kidney, heart or liver \
            conditions, follow your doctor's fluid advice.
            """)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var np = p
                    np.customGoalMl = useCustom ? customMl : nil
                    np.isSet = true
                    model.glassMl = glassMl
                    model.profile = np
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func row(_ title: String, _ ml: Double, bold: Bool = false, plus: Bool = false, note: String? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: bold ? .semibold : .regular))
            if let note {
                Text(note).font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(waterTint.opacity(0.15)))
                    .foregroundStyle(waterTint)
            }
            Spacer()
            Text((plus ? "+" : ml < 0 ? "−" : "") + Fmt.ml(Int(abs(ml).rounded())))
                .font(.system(size: 11, weight: bold ? .semibold : .regular).monospacedDigit())
        }
    }
}

struct NumberRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.precision(.fractionLength(0...1)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            Text(unit).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
            Stepper("", value: $value, in: range, step: step).labelsHidden()
        }
    }
}
