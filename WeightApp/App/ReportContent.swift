import Foundation
import WeightCore

/// レポート1件の表示用モデル(06-reports/01-design.md 5.)。文言は持たず、種類と値だけ。
/// 月半ばのレポートは体組成の数値を型の段階で持たない(`CompositionSection.directions`)。
struct ReportContent: Equatable, Identifiable {
    var period: ReportPeriod
    var continuity: RecordContinuity
    var weight: WeightFlow
    /// 期間の最終日の計画の位置。履歴にその日のフェーズがなければ nil。
    var standing: PlanStanding?
    /// 期間の中でフェーズが変わったこと(到達・卒業・見直し)。
    var changes: [PhaseTimeline.Change]
    var composition: CompositionSection
    /// 月末だけ。
    var paceNote: PaceNote?
    /// 期間の最終日のステージ(月末の表示用)。
    var stage: ReportStage?
    /// 公開済みの中で最新。
    var isLatest: Bool

    var id: String { period.id }
}

/// 体組成の表示。
enum CompositionSection: Equatable {
    /// 期間か基準の体脂肪率がなく、比べられない。
    case unavailable
    /// 月半ば: 方向だけ(数値は持たない)。除脂肪量は体重と体脂肪率の両方がある日がなければ nil。
    case directions(bodyFat: CompositionDirection, leanMass: CompositionDirection?)
    /// 月末: 数値と方向。
    case values(CompositionValues)
}

struct CompositionValues: Equatable {
    enum BaselineLabel: Equatable {
        /// 前の月(列の見出しは「{n}月」)。
        case month(Int)
        /// 最初の月(列の見出しは「開始時」)。
        case planStart
    }

    /// 表示の単位に丸めた値(体脂肪率は %、除脂肪量は kg)。
    struct Pair: Equatable {
        var baseline: Double
        var current: Double
        var direction: CompositionDirection
    }

    var baselineLabel: BaselineLabel
    var bodyFatPercent: Pair
    var leanMass: Pair?
    /// 「体重が減ると、除脂肪量も少し減るのは自然なことです。」を出す。
    var showsLeanMassNote: Bool
    /// 「減った体重の半分以上は脂肪でした。」を出す。
    var showsFatShareNote: Bool
}

/// レポートに出すステージ。
struct ReportStage: Equatable {
    /// 期間の最終日のフェーズ。
    var phase: PlanPhase
    /// めざしている体重(最初の区切り、または次の区切り)。減量中でなければ nil。
    var target: Double?
    var aimingFirstMilestone: Bool
    /// 今の計画の到達予定。最新のレポートで、期間の最終日のフェーズが今のフェーズと同じときだけ(過去の予定は保存していない)。
    var estimatedArrival: CalendarDay?
}

/// 取得済みの記録と保存した計画から、公開済みのレポートを作る(純粋)。
enum ReportBuilder {
    static func reports(record: PlanRecord, weights: [DailyWeight], bodyFats: [DailyBodyFat], today: CalendarDay,
                        settings: ReportSettings = .default) -> [ReportContent] {
        let periods = ReportPeriod.released(planStart: record.roadmap.startDay, through: today, settings: settings)
        let timeline = record.timeline
        return periods.enumerated().map { index, period in
            content(period: period, record: record, timeline: timeline, weights: weights, bodyFats: bodyFats,
                    isLatest: index == periods.count - 1, settings: settings)
        }
    }

    static func nextPeriod(record: PlanRecord, today: CalendarDay, settings: ReportSettings = .default) -> ReportPeriod {
        ReportPeriod.next(planStart: record.roadmap.startDay, after: today, settings: settings)
    }

    static func content(period: ReportPeriod, record: PlanRecord, timeline: PhaseTimeline, weights: [DailyWeight], bodyFats: [DailyBodyFat],
                        isLatest: Bool, settings: ReportSettings) -> ReportContent {
        let roadmap = record.roadmap
        let inPeriod = weights.filter { $0.day >= period.firstDay && $0.day <= period.lastDay }
        let comparison = WeightReport.composition(period: period, roadmap: roadmap, weights: weights, bodyFats: bodyFats, settings: settings)
        return ReportContent(
            period: period,
            continuity: RecordContinuity(period: period, weights: inPeriod),
            weight: WeightReport.flow(period: period, roadmap: roadmap, weights: weights),
            standing: WeightReport.standing(period: period, timeline: timeline, roadmap: roadmap, weights: weights),
            changes: timeline.changes(from: period.firstDay, through: period.lastDay),
            composition: composition(period: period, comparison: comparison),
            paceNote: WeightReport.paceNote(period: period, timeline: timeline, roadmap: roadmap, weights: weights),
            stage: stage(period: period, record: record, timeline: timeline, isLatest: isLatest),
            isLatest: isLatest
        )
    }

    static func composition(period: ReportPeriod, comparison c: CompositionComparison) -> CompositionSection {
        guard let fatDirection = c.bodyFatDirection, let fat0 = c.baseline.bodyFat, let fat1 = c.current.bodyFat else { return .unavailable }
        switch period.kind {
        case .midMonth:
            return .directions(bodyFat: fatDirection, leanMass: c.leanMassDirection)
        case .monthEnd:
            var lean: CompositionValues.Pair?
            if let direction = c.leanMassDirection, let l0 = c.baseline.leanMass, let l1 = c.current.leanMass {
                lean = .init(baseline: Weight.rounded(l0), current: Weight.rounded(l1), direction: direction)
            }
            return .values(CompositionValues(
                baselineLabel: c.baselineIsPlanStart ? .planStart : .month(period.previousMonthEnd.month),
                bodyFatPercent: .init(baseline: Weight.rounded(fat0 * 100), current: Weight.rounded(fat1 * 100), direction: fatDirection),
                leanMass: lean,
                showsLeanMassNote: lean?.direction == .down,
                showsFatShareNote: c.mostlyFatLost
            ))
        }
    }

    static func stage(period: ReportPeriod, record: PlanRecord, timeline: PhaseTimeline, isLatest: Bool) -> ReportStage? {
        guard let phase = timeline.phase(on: period.lastDay) else { return nil }
        let roadmap = record.roadmap
        var result = ReportStage(phase: phase, target: nil, aimingFirstMilestone: false, estimatedArrival: nil)
        guard case .losing(let stage, _) = phase else { return result }
        // 期間の最終日の時点で、最初の区切りにまだ届いていなかったか
        let firstMilestoneReached = record.firstMilestoneReachedOn.map { $0 <= period.lastDay } ?? false
        result.aimingFirstMilestone = stage == 1 && !firstMilestoneReached
        let stageInfo = roadmap.stages.indices.contains(stage - 1) ? roadmap.stages[stage - 1] : nil
        result.target = result.aimingFirstMilestone ? roadmap.firstMilestoneWeight : stageInfo?.boundaryWeight
        if isLatest, phase == record.phase {
            result.estimatedArrival = result.aimingFirstMilestone ? roadmap.firstMilestoneEstimatedArrival(from: phase) : stageInfo?.estimatedArrival
        }
        return result
    }
}

/// 「届きました」のための既読(06-reports/03-decisions.md #8)。最後に開いたレポートの ID を UserDefaults に置く。
@MainActor
final class ReportReadStore {
    static let key = "lastOpenedReportID"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastOpenedID: String? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
