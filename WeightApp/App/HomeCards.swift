import Foundation
import WeightCore

/// ホームに差し込むカード。
enum HomeCard: Equatable, Identifiable {
    /// 出来事(閉じるまで残る)。
    case event(PlanEvent)
    /// 維持期間が12週間を超えた。`canAdvance` は当日の7日平均があるとき。
    case maintenanceMaximum(canAdvance: Bool)
    /// 維持期間中に次の区切りまで減った。
    case earlyArrival(nextStage: Int, boundary: Double)
    /// 計画の見直し。今のステージの到達予定の変更前と変更後。
    case planReview(stage: Int, before: CalendarDay, after: CalendarDay)
    /// 速すぎるペース。
    case tooFast
    /// 維持の範囲から外れて14日。
    case maintenanceNotice(MaintenanceNotice)

    var id: String {
        switch self {
        case .event(let e): "event-\(e.id.uuidString)"
        case .maintenanceMaximum: "maintenanceMaximum"
        case .earlyArrival: "earlyArrival"
        case .planReview: "planReview"
        case .tooFast: "tooFast"
        case .maintenanceNotice: "maintenanceNotice"
        }
    }
}

/// カードの選別と順序(05-cards/01-design.md 4.)。
/// 1. 出来事(古い順) 2. 提案は1枚だけ(85日目 > 早期到達 > 計画見直し) 3. 一言(速すぎるペース、維持の一言。85日目のカードがあれば維持の一言は出さない)
enum HomeCards {
    static func cards(for plan: PlanStatus, sevenDayAverage: Double?, on day: CalendarDay, settings: PlanSettings) -> [HomeCard] {
        var cards: [HomeCard] = plan.record.unreadEvents.map { .event($0) }
        let proposal = self.proposal(for: plan, sevenDayAverage: sevenDayAverage, on: day, settings: settings)
        if let proposal { cards.append(proposal) }
        if plan.actualPace?.isTooFast(settings: settings) == true { cards.append(.tooFast) }
        if let notice = plan.maintenanceNotice {
            if case .maintenanceMaximum = proposal {} else { cards.append(.maintenanceNotice(notice)) }
        }
        return cards
    }

    private static func proposal(for plan: PlanStatus, sevenDayAverage: Double?, on day: CalendarDay, settings: PlanSettings) -> HomeCard? {
        let record = plan.record
        if case .exceededMaximum = plan.maintenance, retryElapsed(since: record.continuedMaintenanceOn, on: day, settings: settings) {
            return .maintenanceMaximum(canAdvance: sevenDayAverage != nil)
        }
        if plan.shouldProposeEarlyArrival, let next = plan.earlyArrivalStage, plan.roadmap.stages.indices.contains(next - 1) {
            return .earlyArrival(nextStage: next, boundary: plan.roadmap.stages[next - 1].boundaryWeight)
        }
        if plan.shouldProposePlanReview, retryElapsed(since: record.declinedPlanReviewOn, on: day, settings: settings),
           let stage = plan.phase.losingStage, let average = sevenDayAverage,
           let rebased = plan.phase.rebased(sevenDayAverage: average, on: day),
           plan.roadmap.stages.indices.contains(stage - 1) {
            let before = plan.roadmap.stages[stage - 1].estimatedArrival
            let after = plan.roadmap.rescheduled(from: rebased).stages[stage - 1].estimatedArrival
            return .planReview(stage: stage, before: before, after: after)
        }
        return nil
    }

    /// 断った日(選んだ日)がないか、再提案までの日数がたっていれば true。
    private static func retryElapsed(since declined: CalendarDay?, on day: CalendarDay, settings: PlanSettings) -> Bool {
        guard let declined else { return true }
        return declined.days(until: day) >= settings.earlyArrivalRetryDays
    }
}
