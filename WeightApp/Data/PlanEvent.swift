import Foundation
import WeightCore

/// 計画で起きた出来事。カードで伝え、閉じたら消す(履歴は持たない)。
struct PlanEvent: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        /// 最初の区切り(5%)に届いた。
        case firstMilestoneReached(weight: Double, nextBoundary: Double)
        /// ステージの区切りに届いて維持期間に入った。
        case stageArrived(stage: Int, weight: Double)
        /// 維持期間を終えて次のステージの減量中に入った。
        case graduated(toStage: Int, keptWeight: Double, nextBoundary: Double)
        /// 最終目標に届いて維持モードに入った。
        case targetReached(weight: Double)
    }

    var id: UUID
    var kind: Kind
    var day: CalendarDay

    init(id: UUID = UUID(), kind: Kind, day: CalendarDay) {
        self.id = id
        self.kind = kind
        self.day = day
    }
}
