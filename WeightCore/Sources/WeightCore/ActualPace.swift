/// 実績のペース。直近の7日平均の変化率を月あたりに換算する。減量中だけ計算する。
///
/// 窓は最長 `actualPaceWindowDays`(28日)。始まりは次より前にしない:
/// - ステージ1: 計画の開始日 + `actualPaceWindowStartFloor`(14日目 = 経過13日)。初期の水分減少を含めないため。
///   さらに計画の開始日から最初の1か月(`initialPeriodDays` 未満)は判定しない。
///   どちらも計画の開始日が基準なので、ステージ1で計画見直しを採用して起点を取り直しても再発しない。
/// - ステージ2以降: ステージの起点の日。
/// 窓が28日に満たない間は 30/n 乗で月に換算する。ただし `actualPaceMinimumWindowDays`(14日)未満は判定しない
/// (1日の揺れが拡大されるため)。ステージ1は窓が常に17日以上あるので影響しない。
public struct ActualPace: Sendable, Equatable {
    /// 月あたりの減量率。増えていれば負。
    public var monthlyRate: Double
    /// 実際に使った窓の日数。
    public var windowDays: Int

    public init?(endingOn day: CalendarDay, phase: PlanPhase, weights: [DailyWeight], roadmap: Roadmap) {
        guard case .losing(let stage, let origin) = phase else { return nil }
        let settings = roadmap.settings
        let floorDay: CalendarDay
        if stage == 1 {
            guard roadmap.startDay.days(until: day) >= settings.initialPeriodDays else { return nil }
            floorDay = roadmap.startDay.adding(days: settings.actualPaceWindowStartFloor)
        } else {
            floorDay = origin.day
        }
        let windowStartDay = max(day.adding(days: -settings.actualPaceWindowDays), floorDay)
        let days = windowStartDay.days(until: day)
        guard days >= settings.actualPaceMinimumWindowDays,
              let now = SevenDayAverage(endingOn: day, in: weights),
              let then = SevenDayAverage(endingOn: windowStartDay, in: weights)
        else { return nil }
        monthlyRate = Pace.monthlyRate(ratio: now.kilograms / then.kilograms, overDays: days, settings: settings)
        windowDays = days
    }

    /// 月 `fastPaceMonthlyLimit`(3%)を超えていれば速すぎ。ちょうどは含めない。
    public func isTooFast(settings: PlanSettings) -> Bool {
        Ratio.rounded(monthlyRate) > settings.fastPaceMonthlyLimit
    }
}
