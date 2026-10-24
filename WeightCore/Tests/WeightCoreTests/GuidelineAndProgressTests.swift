import Foundation
import Testing
@testable import WeightCore

struct GuidelineTests {
    let s = PlanSettings.default

    @Test("日割りの目安", arguments: [
        (0, 123.5), (30, 121.03), (60, 118.6094), (15, 122.2588), (-1, 123.5),
    ])
    func expected(days: Int, expected: Double) {
        #expect(abs(Guideline.expectedWeight(startWeight: 123.5, daysElapsed: days, settings: s) - expected) < 0.0001)
    }

    @Test("目安の日割りと実績ペースの月換算は同じ「月」の定義(互いに逆関数)")
    func monthDefinitionMatches() {
        let g28 = Guideline.expectedWeight(startWeight: 123.5, daysElapsed: 28, settings: s)
        let monthly = Pace.monthlyRate(ratio: g28 / 123.5, overDays: 28, settings: s)
        #expect(abs(monthly - s.monthlyRate) < 1e-9)
        let g17 = Guideline.expectedWeight(startWeight: 123.5, daysElapsed: 17, settings: s)
        #expect(abs(Pace.monthlyRate(ratio: g17 / 123.5, overDays: 17, settings: s) - s.monthlyRate) < 1e-9)
    }
}

struct ProgressJudgmentTests {
    let s = PlanSettings.default
    let afterFirstMonth = 30

    @Test("最初の1か月は判定しない")
    func settlingIn() {
        #expect(ProgressJudgment.judge(sevenDayAverage: 110.0, guideline: 120.0, daysElapsed: 29, settings: s) == .settlingIn)
        #expect(ProgressJudgment.judge(sevenDayAverage: 110.0, guideline: 120.0, daysElapsed: 0, settings: s) == .settlingIn)
    }

    @Test("31日目(経過30日)から判定する")
    func resumesOnDay31() {
        #expect(ProgressJudgment.judge(sevenDayAverage: 120.0, guideline: 120.0, daysElapsed: 30, settings: s) == .onTrack)
    }

    @Test("目安との差で判定(分母は目安)", arguments: [
        (120.6, ProgressJudgment.onTrack),           // ちょうど +0.5%
        (120.62, ProgressJudgment.slowerPace),       // +0.517%
        (119.4, ProgressJudgment.onTrack),           // ちょうど −0.5%
        (119.38, ProgressJudgment.aheadOfSchedule),  // −0.517%
    ])
    func band(average: Double, expected: ProgressJudgment) {
        #expect(ProgressJudgment.judge(sevenDayAverage: average, guideline: 120.0, daysElapsed: afterFirstMonth, settings: s) == expected)
    }

    @Test("丸めてから比較する")
    func rounding() {
        #expect(ProgressJudgment.judge(sevenDayAverage: 100.5049, guideline: 100.0, daysElapsed: afterFirstMonth, settings: s) == .onTrack)
        #expect(ProgressJudgment.judge(sevenDayAverage: 100.505, guideline: 100.0, daysElapsed: afterFirstMonth, settings: s) == .slowerPace)
    }
}
