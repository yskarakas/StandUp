import Foundation

enum Sex: String, Codable, CaseIterable, Identifiable {
    case female, male
    var id: String { rawValue }
    var label: String { self == .female ? "Female" : "Male" }
}

enum Activity: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sedentary: return "Mostly sitting"
        case .light:     return "Light (walks, < 30 min exercise)"
        case .moderate:  return "Moderate (30–60 min exercise)"
        case .high:      return "High (> 1 h exercise or physical job)"
        }
    }
    /// Extra drinking water for sweat losses (ACSM: roughly 0.4–0.8 L per hour of exercise).
    var extraMl: Double {
        switch self {
        case .sedentary: return 0
        case .light:     return 250
        case .moderate:  return 500
        case .high:      return 1000
        }
    }
}

enum Climate: String, Codable, CaseIterable, Identifiable {
    case temperate, warm, hot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .temperate: return "Temperate / air-conditioned"
        case .warm:      return "Warm"
        case .hot:       return "Hot or humid"
        }
    }
    var extraMl: Double {
        switch self {
        case .temperate: return 0
        case .warm:      return 250
        case .hot:       return 500
        }
    }
}

enum LifeStage: String, Codable, CaseIterable, Identifiable {
    case none, pregnant, breastfeeding
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:          return "Not pregnant or breastfeeding"
        case .pregnant:      return "Pregnant"
        case .breastfeeding: return "Breastfeeding"
        }
    }
    /// EFSA (2010): +300 ml/day in pregnancy, +700 ml/day while breastfeeding.
    var extraMl: Double {
        switch self {
        case .none:          return 0
        case .pregnant:      return 300
        case .breastfeeding: return 700
        }
    }
}

struct Profile: Codable, Equatable {
    var sex: Sex = .male
    var age: Int = 30
    var weightKg: Double = 70
    var heightCm: Double = 175
    var activity: Activity = .sedentary
    var climate: Climate = .temperate
    var stage: LifeStage = .none
    var customGoalMl: Int? = nil
    var isSet = false
}

/// A transparent, step-by-step estimate of how much a healthy adult should drink per day.
struct HydrationPlan {
    var perKg: Double
    var weightMethodMl: Double
    var bsa: Double
    var bsaMethodMl: Double
    var totalNeedMl: Double
    var fromFoodMl: Double
    var fromDrinksMl: Double
    var referenceMl: Double
    var baseMl: Double
    var activityMl: Double
    var climateMl: Double
    var stageMl: Double
    var bmi: Double
    var goalMl: Int

    init(_ p: Profile) {
        let w = min(max(p.weightKg, 30), 250)
        let h = min(max(p.heightCm, 120), 230)

        // 1) Weight-based clinical rule: 35 ml/kg (≤ 55 y), 30 ml/kg (56–75 y), 25 ml/kg (> 75 y).
        perKg = p.age <= 55 ? 35 : (p.age <= 75 ? 30 : 25)
        weightMethodMl = w * perKg

        // 2) Body-surface-area rule: 1,500 ml per m², BSA by the Mosteller formula.
        bsa = (h * w / 3600).squareRoot()
        bsaMethodMl = 1500 * bsa

        // Average of the two = total daily water need (food + drinks).
        totalNeedMl = (weightMethodMl + bsaMethodMl) / 2

        // About 20 % of daily water comes from food (EFSA 2010), the rest from drinks.
        fromFoodMl = totalNeedMl * 0.2
        fromDrinksMl = totalNeedMl - fromFoodMl

        // EFSA adequate intake for total water: 2.0 L (women) / 2.5 L (men) → 80 % from drinks.
        referenceMl = p.sex == .male ? 2000 : 1600
        baseMl = max(fromDrinksMl, referenceMl)

        activityMl = p.activity.extraMl
        climateMl = p.climate.extraMl
        stageMl = p.sex == .female ? p.stage.extraMl : 0

        bmi = w / pow(h / 100, 2)
        let raw = baseMl + activityMl + climateMl + stageMl
        goalMl = Int((raw / 50).rounded()) * 50
    }
}
