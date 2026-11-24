import Foundation
import WeightCore

/// `#Preview` 用のデータ。HealthKit や実データに頼らず、`MockHealthStore` と一時ディレクトリの `PlanStore` から `HomeModel` を作る。
/// ここの数値は見た目の確認用で、テストの期待値には使わない。
@MainActor
enum PreviewData {
    private static let cal = AppCalendar.tokyo
    private static var today: CalendarDay { CalendarDay(date: Date(), calendar: cal) }

    private static func tempStore() -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Preview-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    /// `first` から `days` 日、毎日 08:00 に測った体重(HealthPlanet 由来)。`gap` の日は欠けにする。
    private static func samples(from first: CalendarDay, days: Int, start: Double, slopePerDay: Double, gap: Range<Int>? = nil) -> [WeightSample] {
        (0..<days).compactMap { i in
            if let gap, gap.contains(i) { return nil }
            let d = first.adding(days: i)
            let wobble = Double((i * 7) % 5) * 0.1 - 0.2
            return WeightSample(kilograms: start + Double(i) * slopePerDay + wobble,
                                measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    /// モデルを作り、Preview が出る前に取得まで済ませる。
    private static func model(health: MockHealthStore, store: PlanStore) -> HomeModel {
        let model = HomeModel(health: health, planStore: store)
        Task { await model.refresh() }
        return model
    }

    static func loadingModel() -> HomeModel {
        HomeModel(health: MockHealthStore(weights: []), planStore: tempStore())
    }

    // MARK: 初回設定

    enum SetupState { case sevenDayAverage, latest, none, invalid, olderRecords }

    static func setupModel(_ state: SetupState) -> HomeModel {
        let weights: [WeightSample] = switch state {
        case .sevenDayAverage: samples(from: today.adding(days: -6), days: 7, start: 123.9, slopePerDay: -0.1)
        case .latest: samples(from: today.adding(days: -20), days: 3, start: 124.0, slopePerDay: 0)
        case .none: []
        case .invalid: samples(from: today.adding(days: -6), days: 7, start: 66.0, slopePerDay: 0)
        case .olderRecords: samples(from: today.adding(days: -10), days: 11, start: 123.1, slopePerDay: -0.1, gap: 3..<5)
        }
        return model(health: MockHealthStore(weights: weights), store: tempStore())
    }

    // MARK: ホーム

    enum HomeState {
        case noRecords, settlingIn, onTrack, afterFirstMilestone, finalStage, maintaining, maintenanceMode, refreshFailed
        /// 出来事1件(ステージ到達)+ 提案1件(85日目)。
        case eventAndProposal
        /// 一言だけ(維持の範囲から上に14日以上)。
        case noticeOnly
        /// ステージ3の減量中(ロードマップ用)。
        case stage3
        /// 計画見直しを採用したあと(ロードマップに「元の計画に戻す」が出る)。
        case afterReview
    }

    static func homeModel(_ state: HomeState) -> HomeModel {
        let store = tempStore()
        let settings = PlanSettings.default
        let weights: [WeightSample]
        switch state {
        case .noRecords:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -40), targetWeight: 67.4, settings: settings)
            try? store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
            weights = samples(from: today.adding(days: -40), days: 25, start: 123.5, slopePerDay: -0.08)
        case .settlingIn:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -10), targetWeight: 67.4, settings: settings)
            try? store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
            weights = samples(from: today.adding(days: -16), days: 17, start: 124.2, slopePerDay: -0.15)
        case .onTrack:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -45), targetWeight: 67.4, settings: settings)
            try? store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
            weights = (-6...45).map { i in
                let d = today.adding(days: i - 45)
                let kg = Guideline.expectedWeight(startWeight: 123.5, daysElapsed: i, settings: settings) + Double((i * 7) % 5) * 0.1 - 0.2
                return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
            }
        case .afterFirstMilestone:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -90), targetWeight: 67.4, settings: settings)
            try? store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                       firstMilestoneReachedOn: today.adding(days: -5)))
            weights = samples(from: today.adding(days: -96), days: 97, start: 123.5, slopePerDay: -0.07)
        case .finalStage:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -900), targetWeight: 67.4, settings: settings)
            let phase = PlanPhase.losing(stage: 6, origin: StageOrigin(weight: 72.9, day: today.adding(days: -40)))
            try? store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                       firstMilestoneReachedOn: today.adding(days: -800)))
            weights = samples(from: today.adding(days: -46), days: 47, start: 73.1, slopePerDay: -0.05)
        case .maintaining:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -200), targetWeight: 67.4, settings: settings)
            let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: today.adding(days: -11))!
            try? store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                       firstMilestoneReachedOn: today.adding(days: -120)))
            weights = samples(from: today.adding(days: -34), days: 35, start: 112.8, slopePerDay: -0.05)
        case .maintenanceMode:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -1200), targetWeight: 67.4, settings: settings)
            let phase = roadmap.phaseOnArrival(stage: 6, sevenDayAverage: 67.4, on: today.adding(days: -60))!
            try? store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                       firstMilestoneReachedOn: today.adding(days: -1100)))
            weights = samples(from: today.adding(days: -34), days: 35, start: 67.3, slopePerDay: 0.01)
        case .eventAndProposal:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -300), targetWeight: 67.4, settings: settings)
            let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: today.adding(days: -85))!
            var record = PlanRecord(roadmap: roadmap.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                    firstMilestoneReachedOn: today.adding(days: -200))
            record.appendEvent(.stageArrived(stage: 1, weight: 111.2), on: today.adding(days: -85))
            try? store.save(record)
            // 到達の翌日から範囲(±2%)の上に出たままで卒業していない
            weights = samples(from: today.adding(days: -91), days: 7, start: 111.1, slopePerDay: 0)
                + samples(from: today.adding(days: -84), days: 85, start: 114.0, slopePerDay: 0.005)
        case .noticeOnly:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -200), targetWeight: 67.4, settings: settings)
            let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: today.adding(days: -40))!
            try? store.save(PlanRecord(roadmap: roadmap.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                       firstMilestoneReachedOn: today.adding(days: -120)))
            weights = samples(from: today.adding(days: -46), days: 47, start: 112.5, slopePerDay: 0.05)
        case .stage3:
            var roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -600), targetWeight: 67.4, settings: settings)
            roadmap = roadmap.rescheduled(from: roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: today.adding(days: -420))!)
            roadmap = roadmap.rescheduled(from: .losing(stage: 2, origin: StageOrigin(weight: 111.0, day: today.adding(days: -390))))
            roadmap = roadmap.rescheduled(from: roadmap.phaseOnArrival(stage: 2, sevenDayAverage: 100.0, on: today.adding(days: -150))!)
            let phase = PlanPhase.losing(stage: 3, origin: StageOrigin(weight: 99.8, day: today.adding(days: -120)))
            roadmap = roadmap.rescheduled(from: phase)
            try? store.save(PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                       firstMilestoneReachedOn: today.adding(days: -520)))
            weights = (-6...120).map { i in
                let d = today.adding(days: i - 120)
                let kg = Guideline.expectedWeight(startWeight: 99.8, daysElapsed: max(i, 0), settings: settings) + Double((i * 7) % 5) * 0.1 - 0.2
                return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
            }
        case .afterReview:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -80), targetWeight: 67.4, settings: settings)
            var record = PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
            try? record.adoptPlanReview(sevenDayAverage: 121.8, on: today.adding(days: -3))
            try? store.save(record)
            weights = samples(from: today.adding(days: -86), days: 87, start: 123.3, slopePerDay: -0.02)
        case .refreshFailed:
            let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -45), targetWeight: 67.4, settings: settings)
            try? store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
            weights = samples(from: today.adding(days: -51), days: 52, start: 123.5, slopePerDay: -0.08)
            let health = MockHealthStore(weights: weights)
            let model = HomeModel(health: health, planStore: store)
            Task {
                await model.refresh()
                struct Failure: Error {}
                await health.setFailure(Failure())
                await model.refresh()
            }
            return model
        }
        return model(health: MockHealthStore(weights: weights), store: store)
    }

    // MARK: 部品用の履歴

    /// グラフ・カレンダーの部品に渡す `DailyPoint` の列。`endingOn` を最後の日にする。
    nonisolated static func points(days: Int, endingOn end: CalendarDay? = nil, start: Double, slopePerDay: Double,
                                   withGuideline: Bool, gap: Range<Int>? = nil, flatGuideline: Double? = nil) -> [DailyPoint] {
        let cal = AppCalendar.tokyo
        let end = end ?? CalendarDay(date: Date(), calendar: cal)
        let first = end.adding(days: -(days - 1))
        let samples = (0..<days).compactMap { i -> WeightSample? in
            if let gap, gap.contains(i) { return nil }
            let d = first.adding(days: i)
            let wobble = Double((i * 7) % 5) * 0.1 - 0.2
            return WeightSample(kilograms: start + Double(i) * slopePerDay + wobble,
                                measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
        let daily = DailyWeightResolver.resolve(samples, calendar: cal)
        let byDay = Dictionary(daily.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return SevenDayAverage.series(from: first, to: end, in: daily).enumerated().map { i, p in
            let guideline: Double? = withGuideline
                ? (flatGuideline ?? Guideline.expectedWeight(startWeight: start, daysElapsed: i, settings: .default))
                : nil
            return DailyPoint(day: p.day, weight: byDay[p.day], sevenDayAverage: p.average?.kilograms, guideline: guideline)
        }
    }

    // MARK: レポート

    enum ReportState {
        case midOnTrack, midAhead, midSlower, midSettlingIn, midNoBodyFat, midFewRecords
        case endLosing, endFirstMonth, endTooFast, endAhead, endArrivedInPeriod, endMaintenanceMode
    }

    /// レポート1件。日付は固定で、HealthKit のサンプルと同じ形(`WeightSample`、`BodyFatSample`)から1日の値を決めて作る。
    nonisolated static func report(_ state: ReportState) -> ReportContent {
        let cal = AppCalendar.tokyo
        let settings = PlanSettings.default
        func d(_ y: Int, _ m: Int, _ day: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: day) }

        /// `first`〜`last` の毎日 08:00。`weight(i, day)` が nil の日は記録なし。
        func build(start: CalendarDay, startWeight: Double, first: CalendarDay, last: CalendarDay,
                   weight: (Int, CalendarDay) -> Double?, fat: ((Int) -> Double)?) -> ([DailyWeight], [DailyBodyFat], Roadmap) {
            let roadmap = Roadmap(startWeight: startWeight, startDay: start, targetWeight: 67.4, settings: settings)
            var ws: [WeightSample] = []
            var fs: [BodyFatSample] = []
            for i in 0...first.days(until: last) {
                let day = first.adding(days: i)
                let at = day.startDate(in: cal).addingTimeInterval(8 * 3600)
                if let kg = weight(i, day) { ws.append(WeightSample(kilograms: kg, measuredAt: at, source: .healthPlanet)) }
                if let fat { fs.append(BodyFatSample(fraction: fat(i), measuredAt: at, source: .healthPlanet)) }
            }
            return (DailyWeightResolver.resolve(ws, calendar: cal), DailyBodyFatResolver.resolve(fs, calendar: cal), roadmap)
        }

        func wobble(_ i: Int) -> Double { Double((i * 7) % 5) * 0.1 - 0.2 }

        /// ステージ1の計画に対して、目安 × `factor` の体重。`gaps` の日付(日)は欠け。
        func losing(start: CalendarDay, year: Int, month: Int, kind: ReportPeriod.Kind, factor: Double,
                    gaps: Set<Int> = [], withFat: Bool = true, only: ClosedRange<Int>? = nil) -> ReportContent {
            let phase = PlanPhase.losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start))
            let last = d(year, month, ReportPeriod.lastDayOfMonth(year: year, month: month))
            let (weights, fats, roadmap) = build(start: start, startWeight: 123.5, first: start.adding(days: -6), last: last, weight: { i, day in
                if day.month == month, gaps.contains(day.day) { return nil }
                if let only, day.month == month, !only.contains(day.day) { return nil }
                return Guideline.expectedWeight(phase: phase, on: day, settings: settings) * factor + wobble(i)
            }, fat: withFat ? { i in 0.335 - 0.00013 * Double(i) } : nil)
            let record = PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
            let period = ReportPeriod.periods(year: year, month: month, planStart: start, settings: .default).first { $0.kind == kind }!
            return ReportBuilder.content(period: period, record: record, timeline: record.timeline, weights: weights, bodyFats: fats,
                                         isLatest: true, settings: .default)
        }

        switch state {
        case .midOnTrack: return losing(start: d(2026, 10, 1), year: 2026, month: 11, kind: .midMonth, factor: 1.0, gaps: [5, 11])
        case .midAhead: return losing(start: d(2026, 10, 1), year: 2026, month: 11, kind: .midMonth, factor: 0.985)
        case .midSlower: return losing(start: d(2026, 10, 1), year: 2026, month: 11, kind: .midMonth, factor: 1.015, gaps: [3])
        case .midSettlingIn: return losing(start: d(2026, 11, 1), year: 2026, month: 11, kind: .midMonth, factor: 0.99)
        case .midNoBodyFat: return losing(start: d(2026, 10, 1), year: 2026, month: 11, kind: .midMonth, factor: 1.0, withFat: false)
        case .midFewRecords: return losing(start: d(2026, 10, 1), year: 2026, month: 11, kind: .midMonth, factor: 1.0, only: 1...4)
        case .endLosing: return losing(start: d(2026, 10, 1), year: 2026, month: 11, kind: .monthEnd, factor: 1.0, gaps: [7, 19, 26])
        case .endFirstMonth: return losing(start: d(2026, 10, 24), year: 2026, month: 10, kind: .monthEnd, factor: 0.995)
        case .endAhead: return losing(start: d(2026, 10, 1), year: 2026, month: 12, kind: .monthEnd, factor: 0.985)
        case .endTooFast:
            let start = d(2026, 10, 1)
            let phase = PlanPhase.losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start))
            let (weights, fats, roadmap) = build(start: start, startWeight: 123.5, first: start.adding(days: -6), last: d(2026, 12, 31),
                                                 // 11月半ばまでは計画どおり、その後は速め(区切り 111.2 には届かない)
                                                 weight: { i, _ in (i < 52 ? 123.5 - 0.05 * Double(i) : 120.9 - 0.14 * Double(i - 52)) + wobble(i) },
                                                 fat: { i in 0.335 - 0.0002 * Double(i) })
            let record = PlanRecord(roadmap: roadmap, phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                    firstMilestoneReachedOn: d(2026, 12, 18))
            let period = ReportPeriod.periods(year: 2026, month: 12, planStart: start, settings: .default).last!
            return ReportBuilder.content(period: period, record: record, timeline: record.timeline, weights: weights, bodyFats: fats, isLatest: true, settings: .default)
        case .endArrivedInPeriod, .endMaintenanceMode:
            let isMode = state == .endMaintenanceMode
            let start = d(2026, 1, 1)
            let (year, month, arrivalDay, arrivalWeight) = isMode ? (2029, 3, 5, 67.4) : (2026, 6, 10, 111.2)
            let arrival = d(year, month, arrivalDay)
            let last = d(year, month, ReportPeriod.lastDayOfMonth(year: year, month: month))
            let (weights, fats, roadmap) = build(start: start, startWeight: 123.5, first: d(year, month - 1, 20), last: last, weight: { i, day in
                (day < arrival ? arrivalWeight + 0.08 * Double(arrival.days(until: day) * -1) : arrivalWeight + 0.3) + wobble(i)
            }, fat: { i in (isMode ? 0.22 : 0.31) - 0.0001 * Double(i) })
            let phase: PlanPhase = isMode ? roadmap.phaseOnArrival(stage: 6, sevenDayAverage: arrivalWeight, on: arrival)!
                                          : roadmap.phaseOnArrival(stage: 1, sevenDayAverage: arrivalWeight, on: arrival)!
            var record = PlanRecord(roadmap: roadmap.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil,
                                    firstMilestoneReachedOn: d(2026, 3, 1))
            if isMode {
                record.phaseHistory = [.init(from: start, phase: roadmap.initialPhase!),
                                       .init(from: d(2028, 9, 1), phase: .losing(stage: 6, origin: StageOrigin(weight: 72.8, day: d(2028, 9, 1)))),
                                       .init(from: arrival, phase: phase)]
            } else {
                record.phaseHistory = [.init(from: start, phase: roadmap.initialPhase!), .init(from: arrival, phase: phase)]
            }
            let period = ReportPeriod.periods(year: year, month: month, planStart: start, settings: .default).last!
            return ReportBuilder.content(period: period, record: record, timeline: record.timeline, weights: weights, bodyFats: fats, isLatest: true, settings: .default)
        }
    }
}
