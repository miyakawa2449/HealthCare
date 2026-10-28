import Foundation
import Testing
@testable import WeightCore

struct FirstMilestoneTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }

    @Test("到達判定は丸めた7日平均が区切り以下(境界は下の区分)")
    func reached() {
        #expect(roadmap.firstMilestoneWeight == 117.3)
        #expect(roadmap.hasReachedFirstMilestone(sevenDayAverage: 117.3))
        #expect(roadmap.hasReachedFirstMilestone(sevenDayAverage: 117.34))
        #expect(!roadmap.hasReachedFirstMilestone(sevenDayAverage: 117.35))
        #expect(roadmap.hasReachedFirstMilestone(sevenDayAverage: 110.0))
    }

    @Test("到達予定日: 開始の起点から月2%で区切りに届く日(123.5 → 117.3 は77日後)")
    func arrivalFromStart() {
        let phase = roadmap.initialPhase!
        let days = Pace.days(toReach: 117.3 / 123.5, monthlyRate: s.monthlyRate, settings: s)
        #expect(days == 77)
        #expect(roadmap.firstMilestoneEstimatedArrival(from: phase) == start.adding(days: days))
        #expect(roadmap.firstMilestoneEstimatedArrival(from: phase) == day(2027, 1, 3))
    }

    @Test("計画見直しで起点を取り直したら新しい起点から計算する")
    func arrivalFromRebasedOrigin() {
        let origin = day(2026, 12, 1)
        let phase = roadmap.initialPhase!.rebased(sevenDayAverage: 120.0, on: origin)!
        let days = Pace.days(toReach: 117.3 / 120.0, monthlyRate: s.monthlyRate, settings: s)
        #expect(roadmap.firstMilestoneEstimatedArrival(from: phase) == origin.adding(days: days))
    }

    @Test("起点の体重が区切り以下なら起点の日")
    func originAlreadyBelow() {
        let origin = day(2026, 12, 1)
        let phase = roadmap.initialPhase!.rebased(sevenDayAverage: 117.0, on: origin)!
        #expect(roadmap.firstMilestoneEstimatedArrival(from: phase) == origin)
    }

    @Test("ステージ1の減量中以外は nil")
    func otherPhases() {
        let arrivalDay = day(2027, 3, 23)
        let maintaining = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        #expect(roadmap.firstMilestoneEstimatedArrival(from: maintaining) == nil)
        let stage2 = roadmap.phaseOnAdvance(from: maintaining, sevenDayAverage: 111.0, on: arrivalDay.adding(days: 28))!
        #expect(roadmap.firstMilestoneEstimatedArrival(from: stage2) == nil)
        let mode = roadmap.phaseOnArrival(stage: 6, sevenDayAverage: 67.4, on: day(2029, 2, 3))!
        #expect(roadmap.firstMilestoneEstimatedArrival(from: mode) == nil)
    }
}
