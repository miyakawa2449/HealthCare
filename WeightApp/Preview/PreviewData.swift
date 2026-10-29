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
}
