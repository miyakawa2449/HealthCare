import Testing
@testable import WeightCore

struct SafetyJudgmentTests {
    let s = PlanSettings.default

    @Test("週あたりの減量率で判定(境界は下の区分)", arguments: [
        (0.0, SafetyJudgment.comfortable),
        (0.005, SafetyJudgment.comfortable),
        (0.0051, SafetyJudgment.caution),
        (0.01, SafetyJudgment.caution),
        (0.0101, SafetyJudgment.danger),
        (0.00504, SafetyJudgment.comfortable),  // 丸めで 0.50% になる
    ])
    func judge(rate: Double, expected: SafetyJudgment) {
        #expect(SafetyJudgment.judge(weeklyRate: rate, settings: s) == expected)
    }

    @Test("必要な週あたりのペースを逆算する")
    func requiredRate() {
        let r = SafetyJudgment.requiredWeeklyRate(from: 123.5, to: 111.2, days: 156)
        #expect(abs(r - 0.0047) < 0.0001)
    }
}
