/// ロードマップの1ステージ。
public struct Stage: Sendable, Equatable, Codable {
    /// 1 始まり。
    public var number: Int
    /// このステージの開始体重(丸め済み)。
    public var startWeight: Double
    /// このステージの到達体重(丸め済み)。7日平均(丸め済み)がこの値以下なら到達。
    public var boundaryWeight: Double
    /// 到達予定日。
    public var estimatedArrival: CalendarDay
}

/// 最終目標までのステージ構成。保存するので Codable。
public struct Roadmap: Sendable, Equatable, Codable {
    public var startWeight: Double
    public var startDay: CalendarDay
    public var targetWeight: Double
    /// ステージ1の中に置く最初のマイルストーン(開始体重 × (1 − firstMilestoneRatio)、丸め済み)。
    public var firstMilestoneWeight: Double
    public var stages: [Stage]
    public var settings: PlanSettings

    /// 境界は開始体重に (1 − stageRatio) を丸めずに掛けて連鎖させ、各境界だけを 0.1kg に丸める。
    /// 目標を下回る境界が出たら目標で打ち切る。開始が目標以下ならステージなし。
    public init(startWeight: Double, startDay: CalendarDay, targetWeight: Double, settings: PlanSettings) {
        self.startWeight = startWeight
        self.startDay = startDay
        self.targetWeight = targetWeight
        self.settings = settings
        self.firstMilestoneWeight = Weight.rounded(startWeight * (1 - settings.firstMilestoneRatio))
        self.stages = Self.makeStages(startWeight: startWeight, targetWeight: targetWeight, settings: settings)
        self.stages = Self.scheduled(stages, from: Weight.rounded(startWeight), on: startDay, settings: settings)
    }

    /// 計画の見直しを採用したときの起点の取り直し。境界とマイルストーンは変えず、
    /// まだ到達していないステージの到達予定日だけを新しい起点から計算し直す。
    public init(rebasing original: Roadmap, startWeight: Double, startDay: CalendarDay) {
        self = original
        self.startWeight = startWeight
        self.startDay = startDay
        let current = Weight.rounded(startWeight)
        let reached = original.stages.prefix { current <= $0.boundaryWeight }
        var remaining = Array(original.stages.dropFirst(reached.count))
        if !remaining.isEmpty {
            remaining[0].startWeight = current
            remaining = Self.scheduled(remaining, from: current, on: startDay, settings: settings)
        }
        self.stages = Array(reached) + remaining
    }

    /// 7日平均(丸めて比較)が今いるステージ。最終目標に到達していれば nil。
    public func stage(containing sevenDayAverage: Double) -> Stage? {
        let current = Weight.rounded(sevenDayAverage)
        return stages.first { current > $0.boundaryWeight }
    }

    public func hasReachedTarget(sevenDayAverage: Double) -> Bool {
        Weight.rounded(sevenDayAverage) <= targetWeight
    }

    private static func makeStages(startWeight: Double, targetWeight: Double, settings: PlanSettings) -> [Stage] {
        guard startWeight > targetWeight else { return [] }
        var stages: [Stage] = []
        var raw = startWeight
        var previous = Weight.rounded(startWeight)
        while true {
            raw *= (1 - settings.stageRatio)
            var boundary = Weight.rounded(raw)
            let isFinal = boundary <= targetWeight
            if isFinal { boundary = targetWeight }
            stages.append(Stage(number: stages.count + 1, startWeight: previous, boundaryWeight: boundary,
                                estimatedArrival: CalendarDay(year: 0, month: 1, day: 1)))
            if isFinal { break }
            previous = boundary
        }
        return stages
    }

    /// 到達予定日を順に埋める。2つ目以降は前のステージの維持期間(仮定)を足す。
    private static func scheduled(_ stages: [Stage], from weight: Double, on day: CalendarDay, settings: PlanSettings) -> [Stage] {
        var result = stages
        var cursorWeight = weight
        var cursorDay = day
        for i in result.indices {
            if i > 0 { cursorDay = cursorDay.adding(days: settings.assumedMaintenanceDays) }
            let days = Pace.days(toReach: result[i].boundaryWeight / cursorWeight, monthlyRate: settings.monthlyRate, settings: settings)
            cursorDay = cursorDay.adding(days: days)
            result[i].estimatedArrival = cursorDay
            cursorWeight = result[i].boundaryWeight
        }
        return result
    }
}
