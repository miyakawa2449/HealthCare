import Testing
@testable import WeightCore

struct PlanReviewTriggerTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)
    var stage1: PlanPhase { .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start)) }

    /// 窓 11-17〜11-30(経過30〜43日)。
    let windowStart = day(2026, 11, 17)
    let windowEnd = day(2026, 11, 30)

    func guideline(_ phase: PlanPhase, _ d: CalendarDay) -> Double {
        Guideline.expectedWeight(phase: phase, on: d, settings: s)
    }

    /// 体重を一定にすると7日平均も一定になり、目安は日ごとに下がるので、窓の最初の日のずれが最小になる。
    func constant(_ kg: Double, from: CalendarDay? = nil) -> [DailyWeight] {
        constantWeights(from: (from ?? windowStart).adding(days: -6), days: 20, kg)
    }

    func propose(_ phase: PlanPhase, through: CalendarDay, _ w: [DailyWeight]) -> Bool {
        PlanReviewTrigger.shouldPropose(phase: phase, through: through, weights: w, settings: s)
    }

    @Test("14日連続で 2% 以上ずれていたら提案する")
    func proposes() {
        #expect(propose(stage1, through: windowEnd, constant(guideline(stage1, windowStart) * 1.025)))
    }

    @Test("窓の最初の日だけ 2% 未満なら提案しない")
    func firstDayShort() {
        #expect(!propose(stage1, through: windowEnd, constant(guideline(stage1, windowStart) * 1.019)))
    }

    @Test("ちょうど 2% は「2% 以上」に含める")
    func exactlyTwoPercent() {
        #expect(propose(stage1, through: windowEnd, constant(guideline(stage1, windowStart) * 1.02)))
    }

    @Test("下方向のずれも提案する")
    func downward() {
        #expect(propose(stage1, through: windowEnd, constant(guideline(stage1, windowEnd) * 0.975)))
    }

    @Test("7日平均が出ない日があれば提案しない")
    func missingDay() {
        var w = constant(guideline(stage1, windowStart) * 1.025)
        w.removeAll { $0.day >= day(2026, 11, 17) && $0.day <= day(2026, 11, 23) }
        #expect(!propose(stage1, through: windowEnd, w))
    }

    @Test("ステージ1の最初の1か月を含む窓では提案しない")
    func firstMonth() {
        let w = constantWeights(from: day(2026, 11, 10), days: 20, guideline(stage1, day(2026, 11, 16)) * 1.025)
        #expect(!propose(stage1, through: day(2026, 11, 29), w))
        #expect(propose(stage1, through: day(2026, 11, 30), w))
    }

    @Test("ステージ2以降は起点の日から14日で提案できる。起点より前の日を含む窓では提案しない")
    func laterStage() {
        let origin = day(2027, 5, 22)
        let stage2 = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 110.9, day: origin))
        let w = constant(guideline(stage2, origin) * 1.025, from: origin)
        #expect(propose(stage2, through: origin.adding(days: 13), w))
        #expect(!propose(stage2, through: origin.adding(days: 12), w))
    }

    @Test("維持中と維持モードでは提案しない")
    func notWhileMaintaining() {
        let arrival = StageOrigin(weight: 111.2, day: day(2027, 3, 23))
        let w = constantWeights(from: day(2027, 3, 17), days: 60, 120.0)
        #expect(!propose(.maintaining(stage: 1, arrival: arrival), through: day(2027, 5, 1), w))
        #expect(!propose(.maintenanceMode(arrival: arrival), through: day(2027, 5, 1), w))
    }
}
