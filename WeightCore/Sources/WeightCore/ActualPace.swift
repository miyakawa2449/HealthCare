/// 実績のペース。直近の7日平均の変化率を月あたりに換算する。
///
/// 窓は最長 `actualPaceWindowDays`(28日)だが、始まりを `actualPaceWindowStartFloor`(14日目)より前にしない。
/// 最初の1か月(`initialPeriodDays` 未満)は判定しない。
public struct ActualPace: Sendable, Equatable {
    /// 月あたりの減量率。増えていれば負。
    public var monthlyRate: Double
    /// 実際に使った窓の日数(31日目で17、42日目以降で28)。
    public var windowDays: Int

    public init?(endingOn day: CalendarDay, startDay: CalendarDay, weights: [DailyWeight], settings: PlanSettings) {
        let elapsed = startDay.days(until: day)
        guard elapsed >= settings.initialPeriodDays else { return nil }
        let windowStart = max(elapsed - settings.actualPaceWindowDays, settings.actualPaceWindowStartFloor)
        let days = elapsed - windowStart
        guard days > 0,
              let now = SevenDayAverage(endingOn: day, in: weights),
              let then = SevenDayAverage(endingOn: startDay.adding(days: windowStart), in: weights)
        else { return nil }
        monthlyRate = Pace.monthlyRate(ratio: now.kilograms / then.kilograms, overDays: days, settings: settings)
        windowDays = days
    }

    /// 月 `fastPaceMonthlyLimit`(3%)を超えていれば速すぎ。ちょうどは含めない。
    public func isTooFast(settings: PlanSettings) -> Bool {
        Ratio.rounded(monthlyRate) > settings.fastPaceMonthlyLimit
    }
}
