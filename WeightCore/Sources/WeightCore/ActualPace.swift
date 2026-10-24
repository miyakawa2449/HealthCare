/// 実績のペース。直近の7日平均の変化率を月あたりに換算する。減量中だけ計算する。
///
/// 窓は最長 `actualPaceWindowDays`(28日)。始まりは次より前にしない:
/// - ステージ1: `actualPaceWindowStartFloor`(14日目 = 経過13日)。初期の水分減少を含めないため。
///   さらに最初の1か月(`initialPeriodDays` 未満)は判定しない。
/// - ステージ2以降: ステージの起点の日。
/// 窓が28日に満たない間は 30/n 乗で月に換算する。
public struct ActualPace: Sendable, Equatable {
    /// 月あたりの減量率。増えていれば負。
    public var monthlyRate: Double
    /// 実際に使った窓の日数。
    public var windowDays: Int

    public init?(endingOn day: CalendarDay, phase: PlanPhase, weights: [DailyWeight], settings: PlanSettings) {
        guard case .losing(let stage, let origin) = phase else { return nil }
        let elapsed = origin.day.days(until: day)
        let floor: Int
        if stage == 1 {
            guard elapsed >= settings.initialPeriodDays else { return nil }
            floor = settings.actualPaceWindowStartFloor
        } else {
            floor = 0
        }
        let windowStart = max(elapsed - settings.actualPaceWindowDays, floor)
        let days = elapsed - windowStart
        guard days > 0,
              let now = SevenDayAverage(endingOn: day, in: weights),
              let then = SevenDayAverage(endingOn: origin.day.adding(days: windowStart), in: weights)
        else { return nil }
        monthlyRate = Pace.monthlyRate(ratio: now.kilograms / then.kilograms, overDays: days, settings: settings)
        windowDays = days
    }

    /// 月 `fastPaceMonthlyLimit`(3%)を超えていれば速すぎ。ちょうどは含めない。
    public func isTooFast(settings: PlanSettings) -> Bool {
        Ratio.rounded(monthlyRate) > settings.fastPaceMonthlyLimit
    }
}
