import Foundation

/// 安全性の判定(週あたりの減量率)。計画を立てるときの基準に使う。
public enum SafetyJudgment: Sendable, Equatable {
    /// 無理がない(weeklySafeLimit 以下)。
    case comfortable
    /// 頑張りすぎ注意(weeklySafeLimit 超〜weeklyCautionLimit 以下)。
    case caution
    /// 危険(weeklyCautionLimit 超)。
    case danger

    public static func judge(weeklyRate: Double, settings: PlanSettings) -> SafetyJudgment {
        let r = Ratio.rounded(weeklyRate)
        if r <= settings.weeklySafeLimit { return .comfortable }
        if r <= settings.weeklyCautionLimit { return .caution }
        return .danger
    }

    /// 現在の体重から目標まで `days` 日で減らすのに必要な、週あたりの減量率。
    public static func requiredWeeklyRate(from current: Double, to target: Double, days: Int) -> Double {
        1 - pow(target / current, 7 / Double(days))
    }
}
