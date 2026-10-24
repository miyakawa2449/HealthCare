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
}

/// 進み具合の目安(開始体重から標準ペースで日割り)。
public enum Guideline {
    /// 開始体重 × (1 − monthlyRate)^(経過日数 ÷ daysPerMonth)。開始日より前は開始体重。
    public static func expectedWeight(startWeight: Double, daysElapsed: Int, settings: PlanSettings) -> Double {
        startWeight * Pace.factor(monthlyRate: settings.monthlyRate, overDays: max(daysElapsed, 0), settings: settings)
    }
}
