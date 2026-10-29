/// 計画の自動遷移(ステージ到達、維持期間の卒業)。
public enum PhaseTransition: Sendable, Equatable {
    /// 減量中にステージの区切りに届いた(次は維持期間、最終ステージなら維持モード)。到達時体重は丸めた7日平均。
    case arrived(stage: Int, on: CalendarDay, sevenDayAverage: Double)
    /// 維持期間を卒業して次のステージの減量中へ。起点の体重は丸めた7日平均。
    case graduated(fromStage: Int, on: CalendarDay, sevenDayAverage: Double)
}

public enum PhaseProgression {
    public struct Step: Sendable, Equatable {
        public var transition: PhaseTransition
        /// この遷移のあとのフェーズ。
        public var phaseAfter: PlanPhase
    }

    public struct Result: Sendable, Equatable {
        public var phase: PlanPhase
        /// 遷移ごとに `rescheduled(from:)` を適用したロードマップ。境界は変わらない。
        public var roadmap: Roadmap
        public var steps: [Step]
        public var transitions: [PhaseTransition] { steps.map(\.transition) }
    }

    /// `phase` から `day` までに起きる遷移を順に適用する。遷移がなければ入力のまま。
    ///
    /// - 到達(減量中): 起点の日から `day` まで1日ずつ見て、7日平均(丸め)が境界以下になった最初の日。
    ///   アプリを開いていなかった日でも記録からさかのぼって決める。
    /// - 卒業(維持期間): `MaintenanceJudgment` が `graduated(on:)` を返した日。その日の7日平均と日付が次の起点。
    /// - 維持モード: 遷移なし。
    /// - 遷移のあとは新しいフェーズで同じ判定を `day` まで続ける(連鎖)。上限はステージ数 × 2。
    public static func advance(phase: PlanPhase, roadmap: Roadmap, weights: [DailyWeight], through day: CalendarDay, settings: PlanSettings) -> Result {
        var result = Result(phase: phase, roadmap: roadmap, steps: [])
        let limit = max(roadmap.stages.count * 2, 1)
        while result.steps.count < limit, let (transition, next) = step(result.phase, roadmap: result.roadmap, weights: weights, through: day, settings: settings) {
            result.phase = next
            result.roadmap = result.roadmap.rescheduled(from: next)
            result.steps.append(Step(transition: transition, phaseAfter: next))
        }
        return result
    }

    private static func step(_ phase: PlanPhase, roadmap: Roadmap, weights: [DailyWeight], through day: CalendarDay, settings: PlanSettings) -> (PhaseTransition, PlanPhase)? {
        switch phase {
        case .losing(let stage, let origin):
            guard roadmap.stages.indices.contains(stage - 1) else { return nil }
            let boundary = roadmap.stages[stage - 1].boundaryWeight
            guard let (arrivalDay, average) = firstDay(from: origin.day, through: day, weights: weights, where: { $0 <= boundary }),
                  let next = roadmap.phaseOnArrival(stage: stage, sevenDayAverage: average, on: arrivalDay) else { return nil }
            return (.arrived(stage: stage, on: arrivalDay, sevenDayAverage: average), next)
        case .maintaining(let stage, let arrival):
            guard case .graduated(let on) = MaintenanceJudgment.evaluate(arrivalDay: arrival.day, arrivalWeight: arrival.weight, through: day, weights: weights, settings: settings),
                  let average = SevenDayAverage(endingOn: on, in: weights),
                  let next = roadmap.phaseOnAdvance(from: phase, sevenDayAverage: average.kilograms, on: on) else { return nil }
            return (.graduated(fromStage: stage, on: on, sevenDayAverage: Weight.rounded(average.kilograms)), next)
        case .maintenanceMode:
            return nil
        }
    }

    /// `from`〜`through` で、7日平均(丸め)が条件を満たす最初の日とその値。
    static func firstDay(from: CalendarDay, through: CalendarDay, weights: [DailyWeight], where condition: (Double) -> Bool) -> (CalendarDay, Double)? {
        var cursor = from
        while cursor <= through {
            if let avg = SevenDayAverage(endingOn: cursor, in: weights) {
                let rounded = Weight.rounded(avg.kilograms)
                if condition(rounded) { return (cursor, rounded) }
            }
            cursor = cursor.adding(days: 1)
        }
        return nil
    }
}

extension Roadmap {
    /// 最初の区切り(5%)に届いた日: ステージ1の減量中に、起点の日から `day` まで1日ずつ見て、
    /// 7日平均(丸め)が区切り以下になった最初の日。ステージ1の減量中でなければ、まだ届いていなければ nil。
    public func firstMilestoneReachedDay(phase: PlanPhase, weights: [DailyWeight], through day: CalendarDay) -> CalendarDay? {
        guard case .losing(let stage, let origin) = phase, stage == 1 else { return nil }
        return PhaseProgression.firstDay(from: origin.day, through: day, weights: weights, where: { $0 <= firstMilestoneWeight })?.0
    }
}
