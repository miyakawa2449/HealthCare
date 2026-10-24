/// 計画見直しの発動判定。
public enum PlanReviewTrigger {
    /// `day` までの `reviewWindowDays`(14日)すべてで、7日平均が目安から `reviewDeviation`(2%)以上
    /// ずれていれば true。上下どちらのずれも対象。分母は目安(計画値)。
    /// 7日平均が出ない日、または最初の1か月に入る日が窓にあれば false。
    public static func shouldPropose(roadmap: Roadmap, through day: CalendarDay, weights: [DailyWeight]) -> Bool {
        let settings = roadmap.settings
        for offset in 0..<settings.reviewWindowDays {
            let d = day.adding(days: -offset)
            let elapsed = roadmap.startDay.days(until: d)
            guard elapsed >= settings.initialPeriodDays,
                  let avg = SevenDayAverage(endingOn: d, in: weights) else { return false }
            let guideline = Guideline.expectedWeight(startWeight: roadmap.startWeight, daysElapsed: elapsed, settings: settings)
            let ratio = Ratio.rounded((avg.kilograms - guideline) / guideline)
            guard abs(ratio) >= settings.reviewDeviation else { return false }
        }
        return true
    }
}
