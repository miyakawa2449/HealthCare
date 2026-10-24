import Foundation
import Testing
@testable import WeightCore

struct GuidelineTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)

    @Test("日割りの式", arguments: [
        (0, 123.5), (30, 121.03), (60, 118.6094), (15, 122.2588), (-1, 123.5),
    ])
    func formula(days: Int, expected: Double) {
        #expect(abs(Guideline.expectedWeight(startWeight: 123.5, daysElapsed: days, settings: s) - expected) < 0.0001)
    }

    @Test("目安の日割りと実績ペースの月換算は同じ「月」の定義(互いに逆関数)")
    func monthDefinitionMatches() {
        let g28 = Guideline.expectedWeight(startWeight: 123.5, daysElapsed: 28, settings: s)
        #expect(abs(Pace.monthlyRate(ratio: g28 / 123.5, overDays: 28, settings: s) - s.monthlyRate) < 1e-9)
        let g17 = Guideline.expectedWeight(startWeight: 123.5, daysElapsed: 17, settings: s)
        #expect(abs(Pace.monthlyRate(ratio: g17 / 123.5, overDays: 17, settings: s) - s.monthlyRate) < 1e-9)
    }

    @Test("減量中の計画値は、そのステージの起点から月2%で日割り")
    func losingPhase() {
        let phase = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 111.2, day: day(2027, 5, 22)))
        #expect(Guideline.expectedWeight(phase: phase, on: day(2027, 5, 22), settings: s) == 111.2)
        #expect(abs(Guideline.expectedWeight(phase: phase, on: day(2027, 6, 21), settings: s) - 111.2 * 0.98) < 1e-9)
        #expect(Guideline.expectedWeight(phase: phase, on: day(2027, 5, 1), settings: s) == 111.2)   // 起点より前は起点の体重
    }

    @Test("維持中と維持モードの計画値は到達時の体重で一定")
    func maintainingPhase() {
        let arrival = StageOrigin(weight: 111.2, day: day(2027, 3, 23))
        #expect(Guideline.expectedWeight(phase: .maintaining(stage: 1, arrival: arrival), on: day(2027, 5, 1), settings: s) == 111.2)
        #expect(Guideline.expectedWeight(phase: .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: start)), on: day(2030, 1, 1), settings: s) == 67.4)
    }
}

struct ProgressJudgmentTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: day(2026, 10, 18), targetWeight: 67.4, settings: .default) }
    var stage1: PlanPhase { .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start)) }

    @Test("ステージ1の最初の1か月は判定しない(経過29日まで)")
    func settlingIn() {
        #expect(ProgressJudgment.judge(phase: stage1, sevenDayAverage: 110.0, on: start.adding(days: 29), roadmap: roadmap) == .settlingIn)
        #expect(ProgressJudgment.judge(phase: stage1, sevenDayAverage: 110.0, on: start, roadmap: roadmap) == .settlingIn)
    }

    @Test("31日目(経過30日)から判定する")
    func resumesOnDay31() {
        let d = start.adding(days: 30)
        let g = Guideline.expectedWeight(phase: stage1, on: d, settings: s)
        #expect(ProgressJudgment.judge(phase: stage1, sevenDayAverage: g, on: d, roadmap: roadmap) == .onTrack)
    }

    @Test("ステージ2以降は起点の日から判定する(最初の1か月の扱いはステージ1だけ)")
    func laterStagesJudgeImmediately() {
        let stage2 = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 110.9, day: day(2027, 5, 22)))
        #expect(ProgressJudgment.judge(phase: stage2, sevenDayAverage: 110.9, on: day(2027, 5, 22), roadmap: roadmap) == .onTrack)
        #expect(ProgressJudgment.judge(phase: stage2, sevenDayAverage: 112.0, on: day(2027, 5, 23), roadmap: roadmap) == .slowerPace)
    }

    @Test("ステージ1で計画見直しを採用しても、最初の1か月の除外は再発しない(除外は計画の開始日基準)")
    func rebaseInStage1DoesNotResetInitialPeriod() {
        let rebased = stage1.rebased(sevenDayAverage: 118.0, on: start.adding(days: 44))!
        let next = start.adding(days: 45)
        let g = Guideline.expectedWeight(phase: rebased, on: next, settings: s)
        #expect(ProgressJudgment.judge(phase: rebased, sevenDayAverage: g, on: next, roadmap: roadmap) == .onTrack)
    }

    @Test("維持中と維持モードでは判定しない(nil)")
    func notWhileMaintaining() {
        let arrival = StageOrigin(weight: 111.2, day: day(2027, 3, 23))
        #expect(ProgressJudgment.judge(phase: .maintaining(stage: 1, arrival: arrival), sevenDayAverage: 120.0, on: day(2027, 5, 1), roadmap: roadmap) == nil)
        #expect(ProgressJudgment.judge(phase: .maintenanceMode(arrival: arrival), sevenDayAverage: 120.0, on: day(2027, 5, 1), roadmap: roadmap) == nil)
    }

    @Test("目安との差で判定(分母は目安)", arguments: [
        (120.6, ProgressJudgment.onTrack),           // ちょうど +0.5%
        (120.62, ProgressJudgment.slowerPace),       // +0.517%
        (119.4, ProgressJudgment.onTrack),           // ちょうど −0.5%
        (119.38, ProgressJudgment.aheadOfSchedule),  // −0.517%
    ])
    func band(average: Double, expected: ProgressJudgment) {
        #expect(ProgressJudgment.judge(sevenDayAverage: average, guideline: 120.0, settings: s) == expected)
    }

    @Test("丸めてから比較する")
    func rounding() {
        #expect(ProgressJudgment.judge(sevenDayAverage: 100.5049, guideline: 100.0, settings: s) == .onTrack)
        #expect(ProgressJudgment.judge(sevenDayAverage: 100.505, guideline: 100.0, settings: s) == .slowerPace)
    }
}
