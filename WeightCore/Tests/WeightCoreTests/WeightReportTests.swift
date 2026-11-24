import Foundation
import Testing
@testable import WeightCore

struct PhaseTimelineTests {
    let start = day(2026, 10, 18)
    var stage1: PlanPhase { .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start)) }
    var maintaining1: PlanPhase { .maintaining(stage: 1, arrival: StageOrigin(weight: 111.2, day: day(2027, 3, 1))) }

    @Test("日付からその日のフェーズを引く")
    func phaseOn() {
        let t = PhaseTimeline(entries: [.init(from: start, phase: stage1), .init(from: day(2027, 3, 1), phase: maintaining1)])
        #expect(t.phase(on: day(2027, 2, 28)) == stage1)
        #expect(t.phase(on: day(2027, 3, 1)) == maintaining1)
        #expect(t.phase(on: day(2028, 1, 1)) == maintaining1)
        #expect(t.phase(on: day(2026, 10, 17)) == nil)
    }

    @Test("追記: 同じ日の項目は後のもので置き換える。同じフェーズは足さない")
    func appending() {
        var t = PhaseTimeline(entries: [.init(from: start, phase: stage1)])
        t.append(maintaining1, from: day(2027, 3, 1))
        let stage2 = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 111.0, day: day(2027, 3, 1)))
        t.append(stage2, from: day(2027, 3, 1))
        #expect(t.entries.count == 2)
        #expect(t.entries.last?.phase == stage2)
        t.append(stage2, from: day(2027, 3, 5))
        #expect(t.entries.count == 2)
    }

    @Test("過去の日付の追記は日付順に並べる(後の項目は消さない)")
    func appendingOutOfOrder() {
        var t = PhaseTimeline(entries: [.init(from: start, phase: stage1)])
        let stage2 = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 109, day: day(2027, 4, 1)))
        t.append(stage2, from: day(2027, 4, 1))
        t.append(maintaining1, from: day(2027, 3, 1))
        #expect(t.entries.map(\.from) == [start, day(2027, 3, 1), day(2027, 4, 1)])
    }

    @Test("履歴のない記録の補完: 開始時と今のフェーズ")
    func reconstructed() {
        let roadmap = Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: .default)
        #expect(PhaseTimeline.reconstructed(roadmap: roadmap, current: stage1).entries == [.init(from: start, phase: stage1)])
        let t = PhaseTimeline.reconstructed(roadmap: roadmap, current: maintaining1)
        #expect(t.entries == [.init(from: start, phase: stage1), .init(from: day(2027, 3, 1), phase: maintaining1)])
    }

    @Test("期間内の変化を種類に分ける")
    func changes() {
        let rebased = PlanPhase.losing(stage: 1, origin: StageOrigin(weight: 118, day: day(2026, 12, 10)))
        let stage2 = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 111.0, day: day(2027, 3, 29)))
        let mode = PlanPhase.maintenanceMode(arrival: StageOrigin(weight: 67.4, day: day(2029, 1, 1)))
        let t = PhaseTimeline(entries: [
            .init(from: start, phase: stage1),
            .init(from: day(2026, 12, 10), phase: rebased),
            .init(from: day(2026, 12, 20), phase: stage1),      // 元の計画に戻した
            .init(from: day(2027, 3, 1), phase: maintaining1),
            .init(from: day(2027, 3, 29), phase: stage2),
            .init(from: day(2029, 1, 1), phase: mode),
        ])
        #expect(t.changes(from: day(2026, 12, 1), through: day(2026, 12, 31)) == [
            .init(day: day(2026, 12, 10), kind: .planRebased(stage: 1)),
            .init(day: day(2026, 12, 20), kind: .planReverted(stage: 1)),
        ])
        #expect(t.changes(from: day(2027, 3, 1), through: day(2027, 3, 31)) == [
            .init(day: day(2027, 3, 1), kind: .arrived(stage: 1, weight: 111.2)),
            .init(day: day(2027, 3, 29), kind: .advanced(toStage: 2)),
        ])
        #expect(t.changes(from: day(2029, 1, 1), through: day(2029, 1, 15)) == [
            .init(day: day(2029, 1, 1), kind: .reachedTarget(weight: 67.4)),
        ])
        // 最初の項目(計画の開始)は変化として数えない
        #expect(t.changes(from: day(2026, 10, 1), through: day(2026, 10, 31)).isEmpty)
    }
}

struct WeightReportTests {
    let s = ReportSettings.default
    let start = day(2026, 10, 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: .default) }
    var stage1: PlanPhase { .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start)) }
    var timeline: PhaseTimeline { PhaseTimeline(entries: [.init(from: start, phase: stage1)]) }

    func period(_ year: Int, _ month: Int, _ kind: ReportPeriod.Kind, planStart: CalendarDay? = nil) throws -> ReportPeriod {
        try #require(ReportPeriod.periods(year: year, month: month, planStart: planStart ?? start, settings: s).first { $0.kind == kind })
    }

    // MARK: 体重の流れ

    @Test("基準は前の月の末日に終わる7日平均(月半ばも)")
    func baselinePreviousMonthEnd() throws {
        let w = constantWeights(from: day(2026, 10, 25), days: 7, 122.74) + constantWeights(from: day(2026, 11, 1), days: 15, 121.36)
        let flow = WeightReport.flow(period: try period(2026, 11, .midMonth), roadmap: roadmap, weights: w)
        #expect(flow.baseline == .previousMonthEnd(day: day(2026, 10, 31), weight: 122.7))
        #expect(flow.endAverage == 121.4)
        #expect(flow.change == -1.3)
    }

    @Test("前の月の末日が開始日より前なら開始体重と比べる")
    func baselinePlanStart() throws {
        let w = constantWeights(from: start, days: 14, 122.0)
        let flow = WeightReport.flow(period: try period(2026, 10, .monthEnd), roadmap: roadmap, weights: w)
        #expect(flow.baseline == .planStart(weight: 123.5))
        #expect(flow.endAverage == 122.0)
        #expect(flow.change == -1.5)
    }

    @Test("最終日の7日平均が出なければ値も差も出さない")
    func noEndAverage() throws {
        let w = constantWeights(from: day(2026, 10, 25), days: 7, 122.7) + constantWeights(from: day(2026, 11, 1), days: 3, 121.0)
        let flow = WeightReport.flow(period: try period(2026, 11, .midMonth), roadmap: roadmap, weights: w)
        #expect(flow.endAverage == nil)
        #expect(flow.change == nil)
        #expect(flow.baseline != nil)
    }

    @Test("前の月の末日の7日平均が出なければ基準を出さない")
    func noBaselineAverage() throws {
        let w = constantWeights(from: day(2026, 11, 9), days: 7, 121.0)
        let flow = WeightReport.flow(period: try period(2026, 11, .midMonth), roadmap: roadmap, weights: w)
        #expect(flow.baseline == nil)
        #expect(flow.endAverage == 121.0)
        #expect(flow.change == nil)
    }

    // MARK: 目安と進み具合

    @Test("減量中: 最終日の目安と進み具合(ちょうど0.5%は計画どおり)")
    func losingStanding() throws {
        let end = day(2026, 11, 30)
        let guideline = Guideline.expectedWeight(phase: stage1, on: end, settings: .default)
        // 目安 × 1.005 を 0.1kg に丸めずに7日並べる(判定は丸めた割合で行う)
        let avg = Weight.rounded(guideline * 1.005)
        let w = constantWeights(from: end.adding(days: -6), days: 7, avg)
        let standing = try #require(WeightReport.standing(period: try period(2026, 11, .monthEnd), timeline: timeline, roadmap: roadmap, weights: w))
        let expectedProgress = ProgressJudgment.judge(phase: stage1, sevenDayAverage: avg, on: end, roadmap: roadmap)
        #expect(standing == .losing(stage: 1, guideline: guideline, progress: expectedProgress))
    }

    @Test("ステージ1で開始から30日未満の最終日は最初の1か月")
    func settlingIn() throws {
        let w = constantWeights(from: day(2026, 10, 25), days: 7, 122.0)
        let standing = WeightReport.standing(period: try period(2026, 10, .monthEnd), timeline: timeline, roadmap: roadmap, weights: w)
        guard case .losing(_, _, let progress) = standing else { Issue.record("減量中でない"); return }
        #expect(progress == .settlingIn)
    }

    @Test("7日平均が出なければ進み具合を出さない(目安は出す)")
    func losingWithoutAverage() throws {
        let standing = WeightReport.standing(period: try period(2026, 11, .monthEnd), timeline: timeline, roadmap: roadmap, weights: [])
        guard case .losing(1, _, let progress) = standing else { Issue.record("減量中でない"); return }
        #expect(progress == nil)
    }

    @Test("最終日が維持期間なら維持の範囲と位置", arguments: [
        (111.2, MaintenancePosition.within),
        (113.4, MaintenancePosition.within),   // +1.98%
        (113.5, MaintenancePosition.above),
        (108.9, MaintenancePosition.below),
    ])
    func maintainingStanding(avg: Double, expected: MaintenancePosition) throws {
        let arrival = StageOrigin(weight: 111.2, day: day(2027, 3, 1))
        let t = PhaseTimeline(entries: [.init(from: start, phase: stage1), .init(from: arrival.day, phase: .maintaining(stage: 1, arrival: arrival))])
        let w = constantWeights(from: day(2027, 3, 9), days: 7, avg)
        let standing = WeightReport.standing(period: try period(2027, 3, .midMonth), timeline: t, roadmap: roadmap, weights: w)
        #expect(standing == .maintaining(stage: 1, arrivalWeight: 111.2, lower: 109.0, upper: 113.4, position: expected))
    }

    @Test("維持モードはステージ番号なし")
    func maintenanceModeStanding() throws {
        let arrival = StageOrigin(weight: 67.4, day: day(2029, 1, 1))
        let t = PhaseTimeline(entries: [.init(from: start, phase: stage1), .init(from: arrival.day, phase: .maintenanceMode(arrival: arrival))])
        let w = constantWeights(from: day(2029, 1, 9), days: 7, 67.4)
        let standing = WeightReport.standing(period: try period(2029, 1, .midMonth), timeline: t, roadmap: roadmap, weights: w)
        #expect(standing == .maintaining(stage: nil, arrivalWeight: 67.4, lower: 66.1, upper: 68.7, position: .within))
    }

    @Test("過去の期間は当時のフェーズで判定する")
    func pastPhase() throws {
        let arrival = StageOrigin(weight: 111.2, day: day(2027, 3, 1))
        let t = PhaseTimeline(entries: [.init(from: start, phase: stage1), .init(from: arrival.day, phase: .maintaining(stage: 1, arrival: arrival))])
        let standing = WeightReport.standing(period: try period(2027, 2, .monthEnd), timeline: t, roadmap: roadmap, weights: [])
        guard case .losing(1, let guideline, _) = standing else { Issue.record("減量中でない"); return }
        #expect(guideline == Guideline.expectedWeight(phase: stage1, on: day(2027, 2, 28), settings: .default))
    }

    // MARK: ペースの一言(月末だけ)

    /// 開始から `endOffset` 日目に終わる、実績ペースの窓の両端の7日を `before` / `after` にしたデータ。
    func paceWeights(endOffset: Int, before: Double, after: Double) -> [DailyWeight] {
        var entries: [CalendarDay: Double] = [:]
        let then = endOffset - 28
        for i in (then - 6)...then { entries[start.adding(days: i)] = before }
        for i in (endOffset - 6)...endOffset { entries[start.adding(days: i)] = after }
        return dailyWeights(entries)
    }

    @Test("月3%超は速すぎるペースの一言")
    func paceTooFast() throws {
        // 12/31 は開始から74日目
        let w = paceWeights(endOffset: 74, before: 100.0, after: 96.5)
        let note = WeightReport.paceNote(period: try period(2026, 12, .monthEnd), timeline: timeline, roadmap: roadmap, weights: w)
        #expect(note == .tooFast)
    }

    @Test("月3%以内で予定より早いペースなら前倒しの一言")
    func paceAhead() throws {
        let end = day(2026, 12, 31)
        let guideline = Guideline.expectedWeight(phase: stage1, on: end, settings: .default)
        // 予定より早い(目安より1%下)で、28日の変化は月2.5%程度
        let after = Weight.rounded(guideline * 0.99)
        let w = paceWeights(endOffset: 74, before: Weight.rounded(after / 0.975), after: after)
        let progress = ProgressJudgment.judge(phase: stage1, sevenDayAverage: after, on: end, roadmap: roadmap)
        #expect(progress == .aheadOfSchedule)
        let note = WeightReport.paceNote(period: try period(2026, 12, .monthEnd), timeline: timeline, roadmap: roadmap, weights: w)
        #expect(note == .aheadWithinLimit)
    }

    @Test("計画どおりなら一言なし、月半ばは常になし")
    func paceNone() throws {
        let end = day(2026, 12, 31)
        let guideline = Guideline.expectedWeight(phase: stage1, on: end, settings: .default)
        let after = Weight.rounded(guideline)
        let w = paceWeights(endOffset: 74, before: Weight.rounded(after / 0.98), after: after)
        #expect(WeightReport.paceNote(period: try period(2026, 12, .monthEnd), timeline: timeline, roadmap: roadmap, weights: w) == nil)
        let fast = paceWeights(endOffset: 58, before: 100.0, after: 96.5)   // 12/15
        #expect(WeightReport.paceNote(period: try period(2026, 12, .midMonth), timeline: timeline, roadmap: roadmap, weights: fast) == nil)
    }

    @Test("維持中は一言なし")
    func paceMaintaining() throws {
        let arrival = StageOrigin(weight: 111.2, day: day(2027, 3, 1))
        let t = PhaseTimeline(entries: [.init(from: start, phase: stage1), .init(from: arrival.day, phase: .maintaining(stage: 1, arrival: arrival))])
        let w = constantWeights(from: day(2027, 2, 1), days: 60, 111.0)
        #expect(WeightReport.paceNote(period: try period(2027, 3, .monthEnd), timeline: t, roadmap: roadmap, weights: w) == nil)
    }

    // MARK: 体組成

    @Test("体組成の基準: 前の月の末日に終わる7日間。最初の期間は開始日に終わる7日間")
    func compositionBaseline() throws {
        let fats = dailyBodyFats(from: day(2026, 10, 12), Array(repeating: 0.33, count: 7))     // 10/12〜10/18
            + dailyBodyFats(from: day(2026, 10, 25), Array(repeating: 0.32, count: 7))   // 10/25〜10/31
            + dailyBodyFats(from: day(2026, 11, 9), Array(repeating: 0.31, count: 7))    // 11/9〜11/15
        let first = WeightReport.composition(period: try period(2026, 10, .monthEnd), roadmap: roadmap, weights: [], bodyFats: fats, settings: s)
        #expect(abs(try #require(first.baseline.bodyFat) - 0.33) < 1e-12)
        #expect(abs(try #require(first.current.bodyFat) - 0.32) < 1e-12)
        #expect(first.baselineIsPlanStart)
        let mid = WeightReport.composition(period: try period(2026, 11, .midMonth), roadmap: roadmap, weights: [], bodyFats: fats, settings: s)
        #expect(abs(try #require(mid.baseline.bodyFat) - 0.32) < 1e-12)
        #expect(abs(try #require(mid.current.bodyFat) - 0.31) < 1e-12)
        #expect(!mid.baselineIsPlanStart)
        #expect(mid.bodyFatDirection == .down)
        #expect(mid.leanMassDirection == nil)   // 体重がないので除脂肪量は出ない
    }
}
