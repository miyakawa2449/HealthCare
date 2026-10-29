import Foundation
import WeightCore

/// ロードマップ画面に出す行(05-cards/01-design.md 6.)。保存した記録から作る純粋な値。
struct RoadmapRows: Equatable {
    enum StageStatus: Equatable {
        /// 到達した日。
        case arrived(CalendarDay)
        /// 今このステージの減量中。到達予定日つき。
        case current(estimatedArrival: CalendarDay)
        /// 到達予定。
        case estimated(CalendarDay)
    }

    enum MaintenanceStatus: Equatable {
        /// 終了した。日付は次のステージの起点の日。次のステージが今の減量中のときだけ分かる(それより前のステージの起点は保存していない)。
        case ended(CalendarDay?)
        /// 今この維持期間(到達から何日目か。到達日を1日目とする)。
        case current(dayNumber: Int)
        /// これから(約2か月と仮定)。
        case upcoming
    }

    struct FirstMilestone: Equatable {
        var weight: Double
        var reachedOn: CalendarDay?
        /// 届く前(ステージ1の減量中)だけ。起点から標準ペースで計算し、計画見直しを採用すれば起点とともに変わる。
        var estimatedArrival: CalendarDay?
    }

    struct StageRow: Equatable, Identifiable {
        var number: Int
        var startWeight: Double
        var boundaryWeight: Double
        var status: StageStatus
        /// ステージ1にだけ入る。
        var firstMilestone: FirstMilestone?
        /// 最終ステージは nil(維持期間ではなく維持モードへ)。
        var maintenance: MaintenanceStatus?
        var id: Int { number }
        var isCurrent: Bool { if case .current = status { return true } else { return false } }
    }

    struct Target: Equatable {
        var weight: Double
        var status: StageStatus
    }

    struct Revert: Equatable {
        var stage: Int
        /// 今の計画の、このステージの到達予定。
        var current: CalendarDay
        /// 元の計画の、このステージの到達予定。
        var original: CalendarDay
    }

    var paceText: String
    var stages: [StageRow]
    var target: Target
    /// 維持モードに入った日。維持モードでなければ nil。
    var maintenanceMode: CalendarDay?
    /// 「元の計画に戻す」を出せるときだけ。
    var revert: Revert?

    static func make(record: PlanRecord, on day: CalendarDay) -> RoadmapRows {
        let roadmap = record.roadmap
        let phase = record.phase
        let count = roadmap.stages.count

        // 到達済みのステージ番号の上限(この番号までは到達している)
        let arrivedUpTo: Int
        let currentLosing: Int?
        let currentMaintaining: Int?
        switch phase {
        case .losing(let stage, _):
            arrivedUpTo = stage - 1
            currentLosing = stage
            currentMaintaining = nil
        case .maintaining(let stage, _):
            arrivedUpTo = stage
            currentLosing = nil
            currentMaintaining = stage
        case .maintenanceMode:
            arrivedUpTo = count
            currentLosing = nil
            currentMaintaining = nil
        }

        let stages = roadmap.stages.map { stage -> StageRow in
            let n = stage.number
            let status: StageStatus
            if n <= arrivedUpTo { status = .arrived(stage.estimatedArrival) }
            else if n == currentLosing { status = .current(estimatedArrival: stage.estimatedArrival) }
            else { status = .estimated(stage.estimatedArrival) }

            var maintenance: MaintenanceStatus?
            if n < count {
                if n == currentMaintaining {
                    maintenance = .current(dayNumber: phase.origin.day.days(until: day) + 1)
                } else if n < arrivedUpTo || (n == arrivedUpTo && currentLosing != nil) {
                    maintenance = .ended(Self.maintenanceEnd(stage: n, phase: phase))
                } else {
                    maintenance = .upcoming
                }
            }
            var milestone: FirstMilestone?
            if n == 1 {
                let reached = record.firstMilestoneReachedOn
                milestone = FirstMilestone(weight: roadmap.firstMilestoneWeight, reachedOn: reached,
                                           estimatedArrival: reached == nil ? roadmap.firstMilestoneEstimatedArrival(from: phase) : nil)
            }
            return StageRow(number: n, startWeight: stage.startWeight, boundaryWeight: stage.boundaryWeight,
                            status: status, firstMilestone: milestone, maintenance: maintenance)
        }

        let targetStatus: StageStatus
        if case .maintenanceMode(let arrival) = phase { targetStatus = .arrived(arrival.day) }
        else if let last = roadmap.stages.last { targetStatus = .estimated(last.estimatedArrival) }
        else { targetStatus = .arrived(roadmap.startDay) }   // ステージなし(開始が目標以下)。初回設定で弾くので通常は来ない

        var revert: Revert?
        if record.canRevertToOriginalPlan, let original = record.originalRoadmap, let stage = phase.losingStage,
           roadmap.stages.indices.contains(stage - 1), original.stages.indices.contains(stage - 1) {
            revert = Revert(stage: stage, current: roadmap.stages[stage - 1].estimatedArrival, original: original.stages[stage - 1].estimatedArrival)
        }

        var mode: CalendarDay?
        if case .maintenanceMode(let arrival) = phase { mode = arrival.day }

        return RoadmapRows(paceText: paceText(settings: roadmap.settings), stages: stages,
                           target: Target(weight: roadmap.targetWeight, status: targetStatus),
                           maintenanceMode: mode, revert: revert)
    }

    /// 終了した維持期間の終了日。次のステージの減量中ならその起点の日。それより前のステージの起点は保存していないので nil。
    private static func maintenanceEnd(stage: Int, phase: PlanPhase) -> CalendarDay? {
        if case .losing(let losingStage, let origin) = phase, losingStage == stage + 1 { return origin.day }
        return nil
    }

    static func paceJudgment(settings: PlanSettings) -> SafetyJudgment {
        // 月の率を週に換算: 1 − (1 − 月率)^(7/30)
        let weekly = 1 - pow(1 - settings.monthlyRate, 7 / Double(settings.daysPerMonth))
        return SafetyJudgment.judge(weeklyRate: weekly, settings: settings)
    }

    static func paceText(settings: PlanSettings) -> String {
        let percent = Int((settings.monthlyRate * 100).rounded())
        let head = "標準のペースは月\(percent)%。1週間あたりでは"
        switch paceJudgment(settings: settings) {
        case .comfortable: return head + "無理のない範囲です。"
        case .caution: return head + "頑張りすぎに注意の範囲です。"
        case .danger: return head + "無理のある範囲です。"
        }
    }
}
