import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// レポートの表示用モデル(06-reports/02-test-cases.md F)。
struct ReportBuilderTests {
    let s = PlanSettings.default
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    let cal = AppCalendar.tokyo
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }
    var record: PlanRecord { PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil) }

    func weights(from first: CalendarDay, days: Int, start kg: Double, slope: Double) -> [DailyWeight] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return DailyWeight(day: d, kilograms: kg + Double(i) * slope, measuredAt: d.startDate(in: cal), source: .healthPlanet)
        }
    }

    func fats(from first: CalendarDay, days: Int, start f: Double, slope: Double) -> [DailyBodyFat] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return DailyBodyFat(day: d, fraction: f + Double(i) * slope, measuredAt: d.startDate(in: cal), source: .healthPlanet)
        }
    }

    /// 10/12 から 12/31 まで毎日、体重と体脂肪率が少しずつ下がる記録。
    var allWeights: [DailyWeight] { weights(from: CalendarDay(year: 2026, month: 10, day: 12), days: 81, start: 124.0, slope: -0.08) }
    var allFats: [DailyBodyFat] { fats(from: CalendarDay(year: 2026, month: 10, day: 12), days: 81, start: 0.34, slope: -0.0004) }

    @Test("公開済みの一覧と最新")
    func released() {
        let reports = ReportBuilder.reports(record: record, weights: allWeights, bodyFats: allFats, today: CalendarDay(year: 2026, month: 11, day: 24))
        #expect(reports.map(\.id) == ["2026-10-end", "2026-11-mid"])
        #expect(reports.map(\.isLatest) == [false, true])
    }

    @Test("月半ばは体組成の数値を持たない(方向だけ)")
    func midMonthHasNoValues() throws {
        let reports = ReportBuilder.reports(record: record, weights: allWeights, bodyFats: allFats, today: CalendarDay(year: 2026, month: 12, day: 31))
        for report in reports where report.period.kind == .midMonth {
            switch report.composition {
            case .directions, .unavailable: break
            case .values: Issue.record("月半ばに数値がある: \(report.id)")
            }
        }
        let mid = try #require(reports.first { $0.id == "2026-11-mid" })
        guard case .directions(let fat, let lean) = mid.composition else { Issue.record("方向がない"); return }
        #expect(fat == .down)
        #expect(lean != nil)
        #expect(mid.paceNote == nil)
    }

    @Test("月末は数値と方向。基準の列は前の月、最初の月は開始時")
    func monthEndValues() throws {
        let reports = ReportBuilder.reports(record: record, weights: allWeights, bodyFats: allFats, today: CalendarDay(year: 2026, month: 11, day: 30))
        let october = try #require(reports.first { $0.id == "2026-10-end" })
        guard case .values(let first) = october.composition else { Issue.record("10月に数値がない"); return }
        #expect(first.baselineLabel == .planStart)

        let november = try #require(reports.first { $0.id == "2026-11-end" })
        guard case .values(let v) = november.composition else { Issue.record("11月に数値がない"); return }
        #expect(v.baselineLabel == .month(10))
        // 10/25〜10/31 と 11/24〜11/30 の体脂肪率の平均(%、0.1 に丸め)
        let base = allFats.filter { $0.day >= CalendarDay(year: 2026, month: 10, day: 25) && $0.day <= CalendarDay(year: 2026, month: 10, day: 31) }
        let cur = allFats.filter { $0.day >= CalendarDay(year: 2026, month: 11, day: 24) && $0.day <= CalendarDay(year: 2026, month: 11, day: 30) }
        #expect(v.bodyFatPercent.baseline == Weight.rounded(base.map(\.fraction).reduce(0, +) / 7 * 100))
        #expect(v.bodyFatPercent.current == Weight.rounded(cur.map(\.fraction).reduce(0, +) / 7 * 100))
        #expect(v.leanMass != nil)
    }

    @Test("体脂肪率の記録がなければ比べられない")
    func noBodyFat() throws {
        let reports = ReportBuilder.reports(record: record, weights: allWeights, bodyFats: [], today: CalendarDay(year: 2026, month: 11, day: 30))
        #expect(reports.allSatisfy { $0.composition == .unavailable })
    }

    @Test("過去のレポートの目安は、その期間の最終日のフェーズで計算する")
    func pastUsesHistoricalPhase() throws {
        var r = record
        let adopt = CalendarDay(year: 2026, month: 12, day: 5)
        try r.adoptPlanReview(sevenDayAverage: 119.0, on: adopt)
        let reports = ReportBuilder.reports(record: r, weights: allWeights, bodyFats: allFats, today: CalendarDay(year: 2026, month: 12, day: 15))
        let november = try #require(reports.first { $0.id == "2026-11-end" })
        let novEnd = CalendarDay(year: 2026, month: 11, day: 30)
        guard case .losing(1, let guideline, _) = november.standing else { Issue.record("減量中でない"); return }
        #expect(guideline == Guideline.expectedWeight(phase: roadmap.initialPhase!, on: novEnd, settings: s))

        let decMid = try #require(reports.first { $0.id == "2026-12-mid" })
        guard case .losing(1, let g2, _) = decMid.standing else { Issue.record("減量中でない"); return }
        #expect(g2 == Guideline.expectedWeight(phase: r.phase, on: CalendarDay(year: 2026, month: 12, day: 15), settings: s))
        #expect(decMid.changes.map(\.kind) == [.planRebased(stage: 1)])
    }

    @Test("ステージ: 最新で今のフェーズと同じなら到達予定を出す。過去は出さない")
    func stageArrival() throws {
        let reports = ReportBuilder.reports(record: record, weights: allWeights, bodyFats: allFats, today: CalendarDay(year: 2026, month: 11, day: 30))
        let latest = try #require(reports.last)
        #expect(latest.stage?.aimingFirstMilestone == true)
        #expect(latest.stage?.target == roadmap.firstMilestoneWeight)
        #expect(latest.stage?.estimatedArrival == roadmap.firstMilestoneEstimatedArrival(from: roadmap.initialPhase!))
        #expect(reports.first?.stage?.estimatedArrival == nil)
    }

    @Test("最初の区切りに届いた日より後の期間では、次の区切りをめざす")
    func stageAfterFirstMilestone() throws {
        var r = record
        r.firstMilestoneReachedOn = CalendarDay(year: 2026, month: 11, day: 20)
        let reports = ReportBuilder.reports(record: r, weights: allWeights, bodyFats: allFats, today: CalendarDay(year: 2026, month: 11, day: 30))
        #expect(reports.first { $0.id == "2026-11-mid" }?.stage?.aimingFirstMilestone == true)
        #expect(reports.first { $0.id == "2026-11-end" }?.stage?.aimingFirstMilestone == false)
        #expect(reports.first { $0.id == "2026-11-end" }?.stage?.target == roadmap.stages[0].boundaryWeight)
    }

    @Test("公開済みなし: 開始日 11/20、今日 11/24 は空で、次は 11月(11/30)")
    func noneReleased() {
        let r = PlanRecord(roadmap: Roadmap(startWeight: 123.5, startDay: CalendarDay(year: 2026, month: 11, day: 20), targetWeight: 67.4, settings: s),
                           phase: .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: CalendarDay(year: 2026, month: 11, day: 20))),
                           originalRoadmap: nil, declinedEarlyArrivalOn: nil)
        let today = CalendarDay(year: 2026, month: 11, day: 24)
        #expect(ReportBuilder.reports(record: r, weights: allWeights, bodyFats: allFats, today: today).isEmpty)
        #expect(ReportBuilder.nextPeriod(record: r, today: today).id == "2026-11-end")
    }
}

/// 既読と「届きました」(06-reports/02-test-cases.md F #7)。
@MainActor
struct ReportReadTests {
    let cal = AppCalendar.tokyo
    var today: CalendarDay { CalendarDay(date: Date(), calendar: cal) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ReportReadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func makeDefaults() -> UserDefaults {
        let name = "ReportReadTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// 40日前に始めた計画(公開済みが必ず1件以上ある)。
    func model(defaults: UserDefaults) async throws -> HomeModel {
        let store = try makeStore()
        let startDay = today.adding(days: -40)
        let roadmap = Roadmap(startWeight: 123.5, startDay: startDay, targetWeight: 67.4, settings: .default)
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let samples = (0..<41).map { i in
            WeightSample(kilograms: 123.0, measuredAt: startDay.adding(days: i).startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
        let model = HomeModel(health: MockHealthStore(weights: samples), planStore: store, reportReads: ReportReadStore(defaults: defaults))
        await model.refresh()
        return model
    }

    @Test("開いていなければ未読。最新を開いたら未読なし。古いものを開いても最新は未読のまま")
    func unread() async throws {
        let defaults = makeDefaults()
        let model = try await model(defaults: defaults)
        let reports = try #require(model.summary?.reports)
        let latest = try #require(reports.last)
        #expect(model.unreadReport?.id == latest.id)
        if reports.count >= 2 {
            model.markReportOpened(reports[reports.count - 2].id)
            #expect(model.unreadReport?.id == latest.id)
        }
        model.markReportOpened(latest.id)
        #expect(model.unreadReport == nil)
        #expect(ReportReadStore(defaults: defaults).lastOpenedID == latest.id)
        // 最新を開いたあとに古いものを開いても、未読に戻らない
        if let older = reports.first, older.id != latest.id {
            model.markReportOpened(older.id)
            #expect(model.unreadReport == nil)
        }
        #expect(model.summary?.nextReport != nil)
    }
}
