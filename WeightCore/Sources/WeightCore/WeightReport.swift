/// 体重の流れ(比較の基準 → 期間の最終日の7日平均)。値はすべて 0.1kg に丸める。
public struct WeightFlow: Sendable, Equatable {
    public enum Baseline: Sendable, Equatable {
        /// 前の月の末日に終わる7日平均。
        case previousMonthEnd(day: CalendarDay, weight: Double)
        /// 前の月の末日が計画の開始日より前なので、計画の開始体重。
        case planStart(weight: Double)

        public var weight: Double {
            switch self {
            case .previousMonthEnd(_, let w), .planStart(let w): return w
            }
        }
    }

    /// 7日平均が出なければ nil。
    public var baseline: Baseline?
    /// 期間の最終日に終わる7日平均。出なければ nil。
    public var endAverage: Double?
    /// 値 − 基準。どちらかがなければ nil。
    public var change: Double?

    public init(baseline: Baseline?, endAverage: Double?, change: Double?) {
        self.baseline = baseline
        self.endAverage = endAverage
        self.change = change
    }
}

/// 維持中の7日平均の位置(到達時体重 ±maintenanceBand)。
public enum MaintenancePosition: Sendable, Equatable {
    case within, above, below
}

/// 期間の最終日に、計画のどこにいたか。
public enum PlanStanding: Sendable, Equatable {
    /// 減量中。目安は丸めない値、進み具合は7日平均が出なければ nil。
    case losing(stage: Int, guideline: Double, progress: ProgressJudgment?)
    /// 維持期間(`stage` あり)または維持モード(`stage` が nil)。範囲は 0.1kg に丸めた値。位置は7日平均が出なければ nil。
    case maintaining(stage: Int?, arrivalWeight: Double, lower: Double, upper: Double, position: MaintenancePosition?)
}

/// 月末レポートのペースの一言(06-reports/03-decisions.md #6)。割合の数値は持たない。
public enum PaceNote: Sendable, Equatable {
    /// 実績ペースが月3%超。
    case tooFast
    /// 月3%以内で、進み具合が予定より早いペース。前倒しとして見守る。
    case aheadWithinLimit
}

/// 体組成の比較(期間の代表値と基準の代表値)。
public struct CompositionComparison: Sendable, Equatable {
    public var baseline: CompositionSnapshot
    public var current: CompositionSnapshot
    /// 基準が計画の開始日に終わる7日間(最初の期間)。
    public var baselineIsPlanStart: Bool
    /// どちらかの代表値がなければ nil。
    public var bodyFatDirection: CompositionDirection?
    public var leanMassDirection: CompositionDirection?
    /// 減った体重の半分以上が脂肪だった。
    public var mostlyFatLost: Bool
}

/// レポートの集計。判定は既存の規則(`Guideline`、`ProgressJudgment`、`ActualPace`)を、期間の最終日のフェーズで呼ぶ。
public enum WeightReport {
    public static func flow(period: ReportPeriod, roadmap: Roadmap, weights: [DailyWeight]) -> WeightFlow {
        let baseline: WeightFlow.Baseline?
        if period.previousMonthEnd < roadmap.startDay {
            baseline = .planStart(weight: Weight.rounded(roadmap.startWeight))
        } else if let avg = SevenDayAverage(endingOn: period.previousMonthEnd, in: weights) {
            baseline = .previousMonthEnd(day: period.previousMonthEnd, weight: Weight.rounded(avg.kilograms))
        } else {
            baseline = nil
        }
        let end = SevenDayAverage(endingOn: period.lastDay, in: weights).map { Weight.rounded($0.kilograms) }
        let change: Double? = if let end, let baseline { Weight.rounded(end - baseline.weight) } else { nil }
        return WeightFlow(baseline: baseline, endAverage: end, change: change)
    }

    /// 期間の最終日のフェーズでの位置。履歴にその日のフェーズがなければ nil。
    public static func standing(period: ReportPeriod, timeline: PhaseTimeline, roadmap: Roadmap, weights: [DailyWeight]) -> PlanStanding? {
        let day = period.lastDay
        guard let phase = timeline.phase(on: day) else { return nil }
        let settings = roadmap.settings
        let average = SevenDayAverage(endingOn: day, in: weights)?.kilograms
        switch phase {
        case .losing(let stage, _):
            let guideline = Guideline.expectedWeight(phase: phase, on: day, settings: settings)
            let progress = average.flatMap { ProgressJudgment.judge(phase: phase, sevenDayAverage: $0, on: day, roadmap: roadmap) }
            return .losing(stage: stage, guideline: guideline, progress: progress)
        case .maintaining(let stage, let arrival):
            return maintaining(stage: stage, arrival: arrival, average: average, settings: settings)
        case .maintenanceMode(let arrival):
            return maintaining(stage: nil, arrival: arrival, average: average, settings: settings)
        }
    }

    private static func maintaining(stage: Int?, arrival: StageOrigin, average: Double?, settings: PlanSettings) -> PlanStanding {
        let band = settings.maintenanceBand
        let position: MaintenancePosition? = average.map { avg in
            // MaintenanceNoticeJudgment と同じ比べ方(7日平均を丸め、割合を丸める)
            let ratio = Ratio.rounded((Weight.rounded(avg) - arrival.weight) / arrival.weight)
            if ratio > band { return .above }
            if ratio < -band { return .below }
            return .within
        }
        return .maintaining(stage: stage, arrivalWeight: arrival.weight,
                            lower: Weight.rounded(arrival.weight * (1 - band)), upper: Weight.rounded(arrival.weight * (1 + band)),
                            position: position)
    }

    /// 月末レポートのペースの一言。月半ば・維持中・判定できないときは nil。
    public static func paceNote(period: ReportPeriod, timeline: PhaseTimeline, roadmap: Roadmap, weights: [DailyWeight]) -> PaceNote? {
        guard period.kind == .monthEnd, let phase = timeline.phase(on: period.lastDay), phase.losingStage != nil else { return nil }
        guard let pace = ActualPace(endingOn: period.lastDay, phase: phase, weights: weights, roadmap: roadmap) else { return nil }
        if pace.isTooFast(settings: roadmap.settings) { return .tooFast }
        if case .losing(_, _, .aheadOfSchedule)? = standing(period: period, timeline: timeline, roadmap: roadmap, weights: weights) {
            return .aheadWithinLimit
        }
        return nil
    }

    /// 体組成の比較。基準は前の月の末日に終わる7日間(前の月の末日が開始日より前なら、開始日に終わる7日間)。
    public static func composition(period: ReportPeriod, roadmap: Roadmap, weights: [DailyWeight], bodyFats: [DailyBodyFat],
                                   settings: ReportSettings) -> CompositionComparison {
        let isPlanStart = period.previousMonthEnd < roadmap.startDay
        let baseDay = isPlanStart ? roadmap.startDay : period.previousMonthEnd
        let base = BodyComposition.snapshot(endingOn: baseDay, weights: weights, bodyFats: bodyFats)
        let current = BodyComposition.snapshot(endingOn: period.lastDay, weights: weights, bodyFats: bodyFats)
        let fat: CompositionDirection? = if let a = base.bodyFat, let b = current.bodyFat { .bodyFat(from: a, to: b, settings: settings) } else { nil }
        let lean: CompositionDirection? = if let a = base.leanMass, let b = current.leanMass { .leanMass(from: a, to: b, settings: settings) } else { nil }
        return CompositionComparison(baseline: base, current: current, baselineIsPlanStart: isPlanStart,
                                     bodyFatDirection: fat, leanMassDirection: lean,
                                     mostlyFatLost: BodyComposition.mostlyFatLost(from: base, to: current, settings: settings))
    }
}
