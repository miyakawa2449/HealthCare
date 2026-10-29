import Foundation
import WeightCore

enum PlanActionError: Error, Equatable {
    /// いまのフェーズではできない操作(古いカードが押された場合など)。
    case notApplicable
    /// 保存先がない。
    case unavailable
}

/// 計画の記録に対する、自動遷移の反映とユーザーの選択。純粋な操作で、保存は呼び出し側が行う。
extension PlanRecord {
    // MARK: 自動遷移

    /// `PhaseProgression` の結果を反映し、遷移ごとに出来事を足す。
    mutating func apply(_ progression: PhaseProgression.Result) {
        var current = phase
        for step in progression.steps {
            switch step.transition {
            case .arrived(let stage, let on, let average):
                if case .maintenanceMode = step.phaseAfter {
                    appendEvent(.targetReached(weight: average), on: on)
                } else {
                    appendEvent(.stageArrived(stage: stage, weight: average), on: on)
                }
            case .graduated(let fromStage, let on, _):
                let kept: Double
                if case .maintaining(_, let arrival) = current { kept = arrival.weight } else { kept = current.origin.weight }
                let next = fromStage + 1
                let boundary = roadmap.stages.indices.contains(next - 1) ? roadmap.stages[next - 1].boundaryWeight : roadmap.targetWeight
                appendEvent(.graduated(toStage: next, keptWeight: kept, nextBoundary: boundary), on: on)
            }
            current = step.phaseAfter
        }
        phase = progression.phase
        roadmap = progression.roadmap
    }

    /// 最初の区切りに届いた日を記録し、出来事を足す。
    mutating func recordFirstMilestone(on day: CalendarDay) {
        firstMilestoneReachedOn = day
        let nextBoundary = roadmap.stages.first?.boundaryWeight ?? roadmap.targetWeight
        appendEvent(.firstMilestoneReached(weight: roadmap.firstMilestoneWeight, nextBoundary: nextBoundary), on: day)
    }

    mutating func appendEvent(_ kind: PlanEvent.Kind, on day: CalendarDay) {
        events = unreadEvents + [PlanEvent(kind: kind, day: day)]
    }

    mutating func dismissEvent(id: PlanEvent.ID) {
        events = unreadEvents.filter { $0.id != id }
    }

    // MARK: 85日目の提案

    /// 「次のステージへ進む」。維持期間でなければ投げる。その日の7日平均が次の起点になる。
    mutating func advanceAfterMaximum(sevenDayAverage: Double, on day: CalendarDay) throws {
        guard case .maintaining(let stage, let arrival) = phase,
              let next = roadmap.phaseOnAdvance(from: phase, sevenDayAverage: sevenDayAverage, on: day) else { throw PlanActionError.notApplicable }
        phase = next
        roadmap = roadmap.rescheduled(from: next)
        continuedMaintenanceOn = nil
        if case .losing(let toStage, _) = next {
            appendEvent(.graduated(toStage: toStage, keptWeight: arrival.weight, nextBoundary: roadmap.stages[toStage - 1].boundaryWeight), on: day)
        } else {
            _ = stage
        }
    }

    /// 「維持を続ける」。
    mutating func continueMaintenance(on day: CalendarDay) throws {
        guard case .maintaining = phase else { throw PlanActionError.notApplicable }
        continuedMaintenanceOn = day
    }

    // MARK: 早期到達

    /// 「次のステージの到達として扱う」。早期到達が成立していなければ投げる。
    mutating func adoptEarlyArrival(sevenDayAverage: Double, on day: CalendarDay) throws {
        guard let nextStage = roadmap.earlyArrival(phase: phase, sevenDayAverage: sevenDayAverage),
              let next = roadmap.phaseOnEarlyArrival(from: phase, sevenDayAverage: sevenDayAverage, on: day) else { throw PlanActionError.notApplicable }
        phase = next
        roadmap = roadmap.rescheduled(from: next)
        declinedEarlyArrivalOn = nil
        let weight = Weight.rounded(sevenDayAverage)
        if case .maintenanceMode = next {
            appendEvent(.targetReached(weight: weight), on: day)
        } else {
            appendEvent(.stageArrived(stage: nextStage, weight: weight), on: day)
        }
    }

    mutating func declineEarlyArrival(on day: CalendarDay) throws {
        guard case .maintaining = phase else { throw PlanActionError.notApplicable }
        declinedEarlyArrivalOn = day
    }

    // MARK: 計画の見直し

    /// 「この計画で進める」。その日の7日平均と日付を新しい起点にし、到達予定日を計算し直す。境界は変えない。
    /// 元の計画は最初の採用時のものを保持する(2回目以降の採用で上書きしない)。
    mutating func adoptPlanReview(sevenDayAverage: Double, on day: CalendarDay) throws {
        guard let rebased = phase.rebased(sevenDayAverage: sevenDayAverage, on: day) else { throw PlanActionError.notApplicable }
        if originalRoadmap == nil {
            originalRoadmap = roadmap
            originalPhase = phase
        }
        phase = rebased
        roadmap = roadmap.rescheduled(from: rebased)
        declinedPlanReviewOn = nil
    }

    /// 「元の計画のままにする」。
    mutating func declinePlanReview(on day: CalendarDay) throws {
        guard case .losing = phase else { throw PlanActionError.notApplicable }
        declinedPlanReviewOn = day
    }

    /// 「元の計画に戻す」ができるか: 見直しを採用していて、いまも採用時と同じステージの減量中。
    var canRevertToOriginalPlan: Bool {
        guard let originalPhase, originalRoadmap != nil, let current = phase.losingStage, let original = originalPhase.losingStage else { return false }
        return current == original
    }

    /// 「元の計画に戻す」。戻した直後に見直しの提案がまた出ないよう、断った日も当日にする(03-decisions.md #4)。
    mutating func revertToOriginalPlan(on day: CalendarDay) throws {
        guard canRevertToOriginalPlan, let originalRoadmap, let originalPhase else { throw PlanActionError.notApplicable }
        roadmap = originalRoadmap
        phase = originalPhase
        self.originalRoadmap = nil
        self.originalPhase = nil
        declinedPlanReviewOn = day
    }
}
