import Foundation

/// 「月」の定義(30日固定・日ごとの複利)を1か所にまとめる。
/// `Guideline` の日割りと `ActualPace` の月換算は、この型を通して互いに逆関数になる。
public enum Pace {
    /// 月あたりの減量率を日数ぶん複利で進めたときの倍率。
    public static func factor(monthlyRate: Double, overDays days: Int, settings: PlanSettings) -> Double {
        pow(1 - monthlyRate, Double(days) / Double(settings.daysPerMonth))
    }

    /// `days` 日間で体重が `ratio` 倍(後 ÷ 前)になったときの、月あたりの減量率。
    public static func monthlyRate(ratio: Double, overDays days: Int, settings: PlanSettings) -> Double {
        1 - pow(ratio, Double(settings.daysPerMonth) / Double(days))
    }

    /// 体重が `ratio` 倍(後 ÷ 前、1 未満)になるまでに、月あたり `monthlyRate` のペースで必要な日数(切り上げ)。
    public static func days(toReach ratio: Double, monthlyRate: Double, settings: PlanSettings) -> Int {
        guard ratio < 1 else { return 0 }
        return Int((log(ratio) / log(1 - monthlyRate) * Double(settings.daysPerMonth)).rounded(.up))
    }
}

/// 進み具合の目安(計画値)。
public enum Guideline {
    /// フェーズに従った計画値。減量中はステージの起点から月2%で日割り(起点より前は起点の体重)、
    /// 維持中と維持モードは到達時の体重で一定。
    public static func expectedWeight(phase: PlanPhase, on day: CalendarDay, settings: PlanSettings) -> Double {
        switch phase {
        case .losing(_, let origin):
            return expectedWeight(startWeight: origin.weight, daysElapsed: origin.day.days(until: day), settings: settings)
        case .maintaining(_, let arrival), .maintenanceMode(let arrival):
            return arrival.weight
        }
    }

    /// 日割りの式: 開始体重 × (1 − monthlyRate)^(経過日数 ÷ daysPerMonth)。開始日より前は開始体重。
    public static func expectedWeight(startWeight: Double, daysElapsed: Int, settings: PlanSettings) -> Double {
        startWeight * Pace.factor(monthlyRate: settings.monthlyRate, overDays: max(daysElapsed, 0), settings: settings)
    }
}
