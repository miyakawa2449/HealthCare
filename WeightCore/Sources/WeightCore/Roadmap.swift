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
    /// 最終目標も 0.1kg に丸めて保存する(BMI から計算した 67.375 のような値も境界と同じ単位にする)。
    public init(startWeight: Double, startDay: CalendarDay, targetWeight: Double, settings: PlanSettings) {
        let targetWeight = Weight.rounded(targetWeight)
        self.startWeight = startWeight
        self.startDay = startDay
        self.targetWeight = targetWeight
        self.settings = settings
        self.firstMilestoneWeight = Weight.rounded(startWeight * (1 - settings.firstMilestoneRatio))
        self.stages = Self.makeStages(startWeight: startWeight, targetWeight: targetWeight, settings: settings)
        self.stages = Self.scheduled(stages, from: Weight.rounded(startWeight), on: startDay, settings: settings)
    }

    // MARK: フェーズの遷移

    /// 最初のフェーズ: ステージ1の減量中。起点は計画の開始体重と開始日。ステージがなければ nil。
    public var initialPhase: PlanPhase? {
        guard !stages.isEmpty else { return nil }
        return .losing(stage: 1, origin: StageOrigin(weight: startWeight, day: startDay))
    }

    /// ステージに到達した日のフェーズ。最終ステージなら維持モード、それ以外は維持期間。
    /// `stage` が 1...ステージ数 の外なら nil。
    public func phaseOnArrival(stage: Int, sevenDayAverage: Double, on day: CalendarDay) -> PlanPhase? {
        guard isValid(stage: stage) else { return nil }
        let arrival = StageOrigin(weight: sevenDayAverage, day: day)
        return stage == stages.count ? .maintenanceMode(arrival: arrival) : .maintaining(stage: stage, arrival: arrival)
    }

    /// 維持期間から次のステージへ進んだ日のフェーズ。その日の7日平均(丸め)と日付が次のステージの起点になる。
    /// 維持期間中でない、またはステージ番号が範囲外なら nil。
    public func phaseOnAdvance(from phase: PlanPhase, sevenDayAverage: Double, on day: CalendarDay) -> PlanPhase? {
        guard case .maintaining(let stage, let arrival) = phase, isValid(stage: stage) else { return nil }
        guard stage < stages.count else { return .maintenanceMode(arrival: arrival) }
        return .losing(stage: stage + 1, origin: StageOrigin(weight: sevenDayAverage, day: day))
    }

    /// 維持期間中に、7日平均(丸め)が次のステージの境界以下なら次のステージ番号。維持モードと減量中は nil。
    public func earlyArrival(phase: PlanPhase, sevenDayAverage: Double) -> Int? {
        guard case .maintaining(let stage, _) = phase, isValid(stage: stage), stage < stages.count else { return nil }
        return Weight.rounded(sevenDayAverage) <= stages[stage].boundaryWeight ? stage + 1 : nil
    }

    /// 早期到達を採用した日のフェーズ。次のステージの到達として扱い、その維持期間へ(次が最終なら維持モード)。
    /// 早期到達が成立していなければ nil。予定日の更新は `rescheduled(from:)` で行う。
    public func phaseOnEarlyArrival(from phase: PlanPhase, sevenDayAverage: Double, on day: CalendarDay) -> PlanPhase? {
        guard let next = earlyArrival(phase: phase, sevenDayAverage: sevenDayAverage) else { return nil }
        return phaseOnArrival(stage: next, sevenDayAverage: sevenDayAverage, on: day)
    }

    private func isValid(stage: Int) -> Bool {
        (1...max(stages.count, 1)).contains(stage) && !stages.isEmpty
    }

    /// 到達予定日をフェーズから計算し直す。境界は変えない。
    /// 減量中: そのステージの到達予定日を起点から計算し、以降は維持期間(仮定)を挟んで続ける。
    /// 維持中: そのステージの到達予定日は実際の到達日にし、次のステージは到達日 + 維持期間(仮定)から。
    /// 維持モード: 最終ステージの到達予定日を実際の到達日にする。
    /// 手前のステージの予定日は触らない。
    public func rescheduled(from phase: PlanPhase) -> Roadmap {
        var result = self
        switch phase {
        case .losing(let stage, let origin):
            guard isValid(stage: stage) else { return result }
            let remaining = Self.scheduled(Array(stages[(stage - 1)...]), from: origin.weight, on: origin.day, settings: settings)
            result.stages.replaceSubrange((stage - 1)..., with: remaining)
        case .maintaining(let stage, let arrival):
            guard isValid(stage: stage) else { return result }
            result.stages[stage - 1].estimatedArrival = arrival.day
            if stage < stages.count {
                let next = Self.scheduled(Array(stages[stage...]), from: arrival.weight, on: arrival.day.adding(days: settings.assumedMaintenanceDays), settings: settings, maintenanceBeforeFirst: false)
                result.stages.replaceSubrange(stage..., with: next)
            }
        case .maintenanceMode(let arrival):
            // 最終ステージの到達予定日を実際の到達日にする
            if !result.stages.isEmpty { result.stages[result.stages.count - 1].estimatedArrival = arrival.day }
        }
        return result
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
    private static func scheduled(_ stages: [Stage], from weight: Double, on day: CalendarDay, settings: PlanSettings, maintenanceBeforeFirst: Bool = false) -> [Stage] {
        var result = stages
        var cursorWeight = weight
        var cursorDay = day
        for i in result.indices {
            if i > 0 || maintenanceBeforeFirst { cursorDay = cursorDay.adding(days: settings.assumedMaintenanceDays) }
            let days = Pace.days(toReach: result[i].boundaryWeight / cursorWeight, monthlyRate: settings.monthlyRate, settings: settings)
            cursorDay = cursorDay.adding(days: days)
            result[i].estimatedArrival = cursorDay
            cursorWeight = result[i].boundaryWeight
        }
        return result
    }
}

// MARK: 最初の区切り(5%)

extension Roadmap {
    /// 7日平均(丸め)が最初の区切り以下なら到達。境界は下の区分に含める。
    public func hasReachedFirstMilestone(sevenDayAverage: Double) -> Bool {
        Weight.rounded(sevenDayAverage) <= firstMilestoneWeight
    }

    /// ステージ1の減量中だけ、起点から標準ペースで最初の区切りに届く予定日。起点の体重が区切り以下なら起点の日。
    /// それ以外のフェーズは nil。
    public func firstMilestoneEstimatedArrival(from phase: PlanPhase) -> CalendarDay? {
        guard case .losing(let stage, let origin) = phase, stage == 1 else { return nil }
        let days = Pace.days(toReach: firstMilestoneWeight / origin.weight, monthlyRate: settings.monthlyRate, settings: settings)
        return origin.day.adding(days: days)
    }
}
