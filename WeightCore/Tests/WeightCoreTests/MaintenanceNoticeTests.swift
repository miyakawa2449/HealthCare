import Testing
@testable import WeightCore

/// 到達 2026-11-01、111.2kg、範囲 ±2% = 丸め後 109.0〜113.4。
struct MaintenanceNoticeTests {
    let s = PlanSettings.default
    let arrival = StageOrigin(weight: 111.2, day: day(2026, 11, 1))
    var maintaining: PlanPhase { .maintaining(stage: 1, arrival: arrival) }

    /// 到達−6日から values を並べる。
    func weights(_ values: [Double]) -> [DailyWeight] { dailyWeights(from: arrival.day.adding(days: -6), values) }

    func notice(_ phase: PlanPhase, through: CalendarDay, _ w: [DailyWeight]) -> MaintenanceNotice? {
        MaintenanceNoticeJudgment.notice(phase: phase, through: through, weights: w, settings: s)
    }

    @Test("上に外れて14日続いたら aboveBand(14)。13日では出ない")
    func above() {
        // 到達+3 から 114.0。7日平均が範囲外(>113.4)になるのは 114 が6日以上入ってから(到達+8)
        var values = Array(repeating: 111.0, count: 60)
        for i in 9..<60 { values[i] = 114.0 }
        let w = weights(values)
        #expect(notice(maintaining, through: arrival.day.adding(days: 8 + 12), w) == nil)              // 13日
        #expect(notice(maintaining, through: arrival.day.adding(days: 8 + 13), w) == .aboveBand(consecutiveDays: 14))
        #expect(notice(maintaining, through: arrival.day.adding(days: 8 + 20), w) == .aboveBand(consecutiveDays: 21))
    }

    @Test("下に外れて14日続いたら belowBand(14)")
    func below() {
        var values = Array(repeating: 111.0, count: 60)
        for i in 9..<60 { values[i] = 108.0 }
        let w = weights(values)
        // 108.0 は 114.0 より早く範囲外になる(4日入れば 108.9 → 到達+7 から)
        #expect(notice(maintaining, through: arrival.day.adding(days: 7 + 12), w) == nil)
        #expect(notice(maintaining, through: arrival.day.adding(days: 7 + 13), w) == .belowBand(consecutiveDays: 14))
    }

    @Test("範囲内の日が挟まれば数え直し")
    func resetByInBandDay() {
        // 到達+3〜+12 を 115.0(7日平均は +9〜+18 で範囲外)、+13 以降は 111.0 に戻るので平均が徐々に戻る
        var values = Array(repeating: 111.0, count: 60)
        for i in 9..<19 { values[i] = 115.0 }
        let w = weights(values)
        #expect(notice(maintaining, through: arrival.day.adding(days: 30), w) == nil)
    }

    @Test("7日平均が出ない日で数え直し")
    func resetByMissingDay() {
        var entries: [CalendarDay: Double] = [:]
        for i in -6..<60 { entries[arrival.day.adding(days: i)] = i >= 3 ? 114.0 : 111.0 }
        for i in 20...26 { entries[arrival.day.adding(days: i)] = nil }   // 到達+26 の7日平均が nil
        let w = dailyWeights(entries)
        #expect(notice(maintaining, through: arrival.day.adding(days: 26), w) == nil)
        // 到達+27 からまた範囲外(窓に +27 の 114.0 だけ)。14日目は +40
        #expect(notice(maintaining, through: arrival.day.adding(days: 39), w) == nil)
        #expect(notice(maintaining, through: arrival.day.adding(days: 40), w) == .aboveBand(consecutiveDays: 14))
    }

    @Test("上と下が入れ替わったら数え直し")
    func directionChange() {
        var values = Array(repeating: 111.0, count: 60)
        for i in 9..<24 { values[i] = 115.0 }   // 上
        for i in 24..<60 { values[i] = 107.0 }  // 下
        let w = weights(values)
        // 上は到達+7〜+18(12日、14日に届かない)。下に抜けるのは 107 が6日入ってから(到達+23)
        #expect(notice(maintaining, through: arrival.day.adding(days: 35), w) == nil)
        #expect(notice(maintaining, through: arrival.day.adding(days: 36), w) == .belowBand(consecutiveDays: 14))
        #expect(notice(maintaining, through: arrival.day.adding(days: 50), w) == .belowBand(consecutiveDays: 28))
    }

    @Test("維持モードでも出る。減量中は出ない")
    func phases() {
        var values = Array(repeating: 111.0, count: 60)
        for i in 9..<60 { values[i] = 114.0 }
        let w = weights(values)
        let d = arrival.day.adding(days: 30)
        #expect(notice(.maintenanceMode(arrival: arrival), through: d, w) == .aboveBand(consecutiveDays: 23))   // 到達+8〜+30
        #expect(notice(.losing(stage: 1, arrival: arrival), through: d, w) == nil)
    }

    @Test("85日目の提案カードと同時に成立したら、両方返る(優先は表示側)")
    func coexistsWithExceededMaximum() {
        var values = Array(repeating: 111.0, count: 110)
        for i in 9..<110 { values[i] = 114.0 }
        let w = weights(values)
        let d = arrival.day.adding(days: 85)
        if case .exceededMaximum = MaintenanceJudgment.evaluate(arrivalDay: arrival.day, arrivalWeight: arrival.weight, through: d, weights: w, settings: s) {} else { Issue.record("85日目は exceededMaximum") }
        if case .aboveBand = notice(maintaining, through: d, w) {} else { Issue.record("一言も成立する") }
    }
}

private extension PlanPhase {
    static func losing(stage: Int, arrival: StageOrigin) -> PlanPhase { .losing(stage: stage, origin: arrival) }
}
