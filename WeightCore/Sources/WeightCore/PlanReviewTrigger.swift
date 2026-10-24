/// 計画見直しの発動判定。減量中だけ。
public enum PlanReviewTrigger {
    /// `day` までの `reviewWindowDays`(14日)すべてで、7日平均が計画値から `reviewDeviation`(2%)以上
    /// ずれていれば true。上下どちらのずれも対象。分母は計画値。
    /// 窓に、7日平均が出ない日、ステージの起点より前の日、またはステージ1の最初の1か月に入る日があれば false。
    public static func shouldPropose(phase: PlanPhase, through day: CalendarDay, weights: [DailyWeight], settings: PlanSettings) -> Bool {
        guard case .losing(let stage, let origin) = phase else { return false }
        let earliest = stage == 1 ? settings.initialPeriodDays : 0
        for offset in 0..<settings.reviewWindowDays {
            let d = day.adding(days: -offset)
            guard origin.day.days(until: d) >= earliest,
                  let avg = SevenDayAverage(endingOn: d, in: weights) else { return false }
            let guideline = Guideline.expectedWeight(phase: phase, on: d, settings: settings)
            guard abs(Ratio.rounded((avg.kilograms - guideline) / guideline)) >= settings.reviewDeviation else { return false }
        }
        return true
    }
}
