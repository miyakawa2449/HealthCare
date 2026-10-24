import Testing
@testable import WeightCore

struct PlanReviewTriggerTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }

    /// 窓 11-17〜11-30(経過30〜43日)。
    let windowStart = day(2026, 11, 17)
    let windowEnd = day(2026, 11, 30)

    func guideline(_ d: CalendarDay) -> Double {
        Guideline.expectedWeight(startWeight: 123.5, daysElapsed: start.days(until: d), settings: s)
    }

    /// 体重を一定にすると7日平均も一定になり、目安は日ごとに下がるので、窓の最初の日のずれが最小になる。
    func constant(_ kg: Double) -> [DailyWeight] {
        constantWeights(from: windowStart.adding(days: -6), days: 20, kg)
    }

    @Test("14日連続で 2% 以上ずれていたら提案する")
    func proposes() {
        let w = constant(guideline(windowStart) * 1.025)
        #expect(PlanReviewTrigger.shouldPropose(roadmap: roadmap, through: windowEnd, weights: w))
    }

    @Test("窓の最初の日だけ 2% 未満なら提案しない")
    func firstDayShort() {
        let w = constant(guideline(windowStart) * 1.019)
        #expect(!PlanReviewTrigger.shouldPropose(roadmap: roadmap, through: windowEnd, weights: w))
    }

    @Test("ちょうど 2% は「2% 以上」に含める")
    func exactlyTwoPercent() {
        let w = constant(guideline(windowStart) * 1.02)
        #expect(PlanReviewTrigger.shouldPropose(roadmap: roadmap, through: windowEnd, weights: w))
    }

    @Test("下方向のずれも提案する")
    func downward() {
        // 目安は下がるので、窓の最後の日の目安を基準に −2.5% なら全日 −2.5% 以下
        let w = constant(guideline(windowEnd) * 0.975)
        #expect(PlanReviewTrigger.shouldPropose(roadmap: roadmap, through: windowEnd, weights: w))
    }

    @Test("7日平均が出ない日があれば提案しない")
    func missingDay() {
        var w = constant(guideline(windowStart) * 1.025)
        w.removeAll { $0.day >= day(2026, 11, 17) && $0.day <= day(2026, 11, 23) }   // 11-23 の窓に0件
        #expect(!PlanReviewTrigger.shouldPropose(roadmap: roadmap, through: windowEnd, weights: w))
    }

    @Test("最初の1か月を含む窓では提案しない")
    func firstMonth() {
        let w = constantWeights(from: day(2026, 11, 10), days: 20, guideline(day(2026, 11, 16)) * 1.025)
        #expect(!PlanReviewTrigger.shouldPropose(roadmap: roadmap, through: day(2026, 11, 29), weights: w))
        #expect(PlanReviewTrigger.shouldPropose(roadmap: roadmap, through: day(2026, 11, 30), weights: w))
    }
}
