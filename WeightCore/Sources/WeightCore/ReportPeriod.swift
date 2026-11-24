import Foundation

/// レポートの閾値。`PlanSettings` と違って plan.json に保存しない(項目を足すと既存のファイルが読めなくなるため、別の型にした)。
public struct ReportSettings: Sendable, Equatable {
    /// 月半ばのレポートの最終日(1日〜この日)。
    public var midMonthLastDay: Int
    /// 体脂肪率の「横ばい」の幅(ポイント、表示の単位 0.1 に丸めた差と比べる)。ちょうどは横ばい。
    public var bodyFatFlatBandPoints: Double
    /// 除脂肪量の「横ばい」の幅(kg、0.1kg に丸めた差と比べる)。ちょうどは横ばい。
    public var leanMassFlatBandKilograms: Double
    /// 「減った体重の半分以上は脂肪でした」を出す、脂肪量の減少 ÷ 体重の減少の下限(ちょうどは含める)。
    public var fatShareNoteThreshold: Double

    public init(midMonthLastDay: Int, bodyFatFlatBandPoints: Double, leanMassFlatBandKilograms: Double, fatShareNoteThreshold: Double) {
        self.midMonthLastDay = midMonthLastDay
        self.bodyFatFlatBandPoints = bodyFatFlatBandPoints
        self.leanMassFlatBandKilograms = leanMassFlatBandKilograms
        self.fatShareNoteThreshold = fatShareNoteThreshold
    }

    /// 06-reports/03-decisions.md #3 の値。
    public static let `default` = ReportSettings(
        midMonthLastDay: 15,
        bodyFatFlatBandPoints: 0.5,
        leanMassFlatBandKilograms: 0.5,
        fatShareNoteThreshold: 0.5
    )
}

/// レポートの期間。月半ば(1日〜15日)と月末(1日〜月末)。計画の開始日より前は含めない。
public struct ReportPeriod: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case midMonth = "mid"
        case monthEnd = "end"
    }

    public var kind: Kind
    public var year: Int
    public var month: Int
    /// 期間の最初の日。計画の開始日を含む月では開始日。
    public var firstDay: CalendarDay
    /// 期間の最終日(公開日)。
    public var lastDay: CalendarDay

    /// 例 `2026-11-mid`。既読の保存に使う。
    public var id: String { String(format: "%04d-%02d-", year, month) + kind.rawValue }
    /// 公開日は期間の最終日(06-reports/03-decisions.md #1)。
    public var releaseDay: CalendarDay { lastDay }
    public var dayCount: Int { firstDay.days(until: lastDay) + 1 }
    public var days: [CalendarDay] { (0..<dayCount).map { firstDay.adding(days: $0) } }
    /// その月の1日。
    public var monthFirstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1) }
    /// 前の月の末日(体重と体組成の比較の基準)。
    public var previousMonthEnd: CalendarDay { monthFirstDay.adding(days: -1) }
    /// 計画の開始日で期間の始まりが切られている。
    public var isClippedByPlanStart: Bool { firstDay != monthFirstDay }

    /// その月の末日の日。
    public static func lastDayOfMonth(year: Int, month: Int) -> Int {
        let nextMonthFirst = month == 12 ? CalendarDay(year: year + 1, month: 1, day: 1) : CalendarDay(year: year, month: month + 1, day: 1)
        return nextMonthFirst.adding(days: -1).day
    }

    /// その月の期間(月半ば、月末の順)。開始日より前に終わる期間は含めない。
    public static func periods(year: Int, month: Int, planStart: CalendarDay, settings: ReportSettings) -> [ReportPeriod] {
        let first = CalendarDay(year: year, month: month, day: 1)
        let ends: [(Kind, CalendarDay)] = [
            (.midMonth, CalendarDay(year: year, month: month, day: settings.midMonthLastDay)),
            (.monthEnd, CalendarDay(year: year, month: month, day: lastDayOfMonth(year: year, month: month))),
        ]
        return ends.compactMap { kind, last in
            guard last >= planStart else { return nil }
            return ReportPeriod(kind: kind, year: year, month: month, firstDay: max(first, planStart), lastDay: last)
        }
    }

    /// 公開日が `today` 以下の期間(古い順)。
    public static func released(planStart: CalendarDay, through today: CalendarDay, settings: ReportSettings) -> [ReportPeriod] {
        var result: [ReportPeriod] = []
        var (y, m) = (planStart.year, planStart.month)
        while (y, m) <= (today.year, today.month) {
            result += periods(year: y, month: m, planStart: planStart, settings: settings).filter { $0.releaseDay <= today }
            (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
        }
        return result
    }

    /// 公開日が `today` より後の、最初の期間。
    public static func next(planStart: CalendarDay, after today: CalendarDay, settings: ReportSettings) -> ReportPeriod {
        let base = max(planStart, today)
        var (y, m) = (base.year, base.month)
        while true {
            if let found = periods(year: y, month: m, planStart: planStart, settings: settings).first(where: { $0.releaseDay > today }) {
                return found
            }
            (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
        }
    }
}

/// 記録できた日。期間内で体重の記録(1日の値)がある日を数える。
public struct RecordContinuity: Sendable, Equatable {
    public struct Mark: Sendable, Equatable {
        public var day: CalendarDay
        public var recorded: Bool
    }

    public var recordedDays: Int
    public var totalDays: Int
    /// 期間の日ごとの有無(日付順)。
    public var marks: [Mark]

    public var allRecorded: Bool { totalDays > 0 && recordedDays == totalDays }

    public init(period: ReportPeriod, weights: [DailyWeight]) {
        let recorded = Set(weights.map(\.day))
        marks = period.days.map { Mark(day: $0, recorded: recorded.contains($0)) }
        recordedDays = marks.filter(\.recorded).count
        totalDays = marks.count
    }
}
