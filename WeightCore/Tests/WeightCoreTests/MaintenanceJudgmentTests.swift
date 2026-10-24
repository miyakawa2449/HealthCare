import Testing
@testable import WeightCore

struct MaintenanceJudgmentTests {
    let s = PlanSettings.default
    let arrival = day(2026, 11, 1)
    let arrivalWeight = 111.2

    func evaluate(through: CalendarDay, _ weights: [DailyWeight]) -> MaintenanceState {
        MaintenanceJudgment.evaluate(arrivalDay: arrival, arrivalWeight: arrivalWeight, through: through, weights: weights, settings: s)
    }

    @Test("28日連続で範囲内なら 28日目に卒業")
    func graduates() {
        let w = constantWeights(from: arrival.adding(days: -6), days: 60, 111.0)
        #expect(evaluate(through: day(2026, 11, 28), w) == .graduated(on: day(2026, 11, 28)))
        #expect(evaluate(through: day(2026, 12, 20), w) == .graduated(on: day(2026, 11, 28)))
    }

    @Test("27日では未卒業")
    func day27() {
        let w = constantWeights(from: arrival.adding(days: -6), days: 60, 111.0)
        #expect(evaluate(through: day(2026, 11, 27), w) == .inProgress(consecutiveDaysInBand: 27))
    }

    @Test("途中で範囲を外れたら数え直し")
    func resets() {
        var values = Array(repeating: 111.0, count: 60)
        for i in 9...15 { values[i] = 113.5 }   // 11-04〜11-10 の7日間 → 11-10 の7日平均だけが範囲外
        let w = dailyWeights(from: arrival.adding(days: -6), values)
        #expect(evaluate(through: day(2026, 11, 10), w) == .inProgress(consecutiveDaysInBand: 0))
        #expect(evaluate(through: day(2026, 12, 7), w) == .inProgress(consecutiveDaysInBand: 27))
        #expect(evaluate(through: day(2026, 12, 8), w) == .graduated(on: day(2026, 12, 8)))
    }

    @Test("ちょうど ±2% は範囲内、わずかに超えたら範囲外")
    func bandEdges() {
        let inside = constantWeights(from: arrival.adding(days: -6), days: 10, 113.4)
        #expect(evaluate(through: day(2026, 11, 3), inside) == .inProgress(consecutiveDaysInBand: 3))
        let lower = constantWeights(from: arrival.adding(days: -6), days: 10, 109.0)
        #expect(evaluate(through: day(2026, 11, 3), lower) == .inProgress(consecutiveDaysInBand: 3))
        let outside = constantWeights(from: arrival.adding(days: -6), days: 10, 113.5)
        #expect(evaluate(through: day(2026, 11, 3), outside) == .inProgress(consecutiveDaysInBand: 0))
    }

    @Test("7日平均が出ない日はカウントを 0 に戻す")
    func missingData() {
        var entries: [CalendarDay: Double] = [:]
        for i in -6..<60 { entries[arrival.adding(days: i)] = 111.0 }
        for i in 4...10 { entries[arrival.adding(days: i)] = nil }   // 11-05〜11-11 にデータなし → 11-11 の7日平均が nil
        let w = dailyWeights(entries)
        #expect(evaluate(through: day(2026, 11, 11), w) == .inProgress(consecutiveDaysInBand: 0))
        #expect(evaluate(through: day(2026, 12, 9), w) == .graduated(on: day(2026, 12, 9)))
    }

    @Test("84日を超えても卒業していなければ提案(exceededMaximum)")
    func exceeded() {
        // 範囲内が20日続くたびに外れる → 28日連続にならない
        var values = Array(repeating: 111.0, count: 100)
        for i in stride(from: 20, to: 100, by: 21) { for j in i..<(i + 7) where j < 100 { values[j] = 114.0 } }
        let w = dailyWeights(from: arrival.adding(days: -6), values)
        if case .inProgress = evaluate(through: day(2027, 1, 24), w) {} else { Issue.record("経過84日はまだ inProgress") }
        if case .exceededMaximum = evaluate(through: day(2027, 1, 25), w) {} else { Issue.record("経過85日で exceededMaximum") }
    }

    @Test("84日以内に卒業していればそちら")
    func graduatesBeforeMax() {
        var values = Array(repeating: 114.0, count: 100)
        for i in 36..<100 { values[i] = 111.0 }   // 12-01 から範囲内(12-01 の7日平均は混ざるので 12-02 以降)
        let w = dailyWeights(from: arrival.adding(days: -6), values)
        if case .graduated(let d) = evaluate(through: day(2027, 1, 25), w) {
            #expect(d < day(2027, 1, 24))
        } else {
            Issue.record("卒業しているはず")
        }
    }
}
