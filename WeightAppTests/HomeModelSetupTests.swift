import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// HomeModel の初回設定と最初の区切りの保存。
@MainActor
struct HomeModelSetupTests {
    let cal = AppCalendar.tokyo
    var today: CalendarDay { CalendarDay(date: Date(), calendar: cal) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HomeModelSetupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func samples(from first: CalendarDay, days: Int, _ kg: Double) -> [WeightSample] {
        (0..<days).map { i in
            let d = first.adding(days: i)
            return WeightSample(kilograms: kg, measuredAt: d.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)
        }
    }

    @Test("生成直後は hasRefreshed が false。refresh 後は失敗でも true")
    func hasRefreshed() async throws {
        let health = MockHealthStore(weights: [])
        let model = HomeModel(health: health, planStore: try makeStore())
        #expect(!model.hasRefreshed)
        await health.setFailure(HomeModelTests.Failure())
        await model.refresh()
        #expect(model.hasRefreshed)
    }

    @Test("直近7日に記録があれば7日平均が初期値")
    func suggestionAverage() async throws {
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -2), days: 3, 123.5)), planStore: try makeStore())
        await model.refresh()
        #expect(model.startWeightSuggestion == .sevenDayAverage(123.5))
    }

    @Test("直近7日に記録がなければ最新の1件")
    func suggestionLatest() async throws {
        var weights = samples(from: today.adding(days: -20), days: 5, 124.0)
        weights.append(contentsOf: samples(from: today.adding(days: -10), days: 1, 123.0))
        let model = HomeModel(health: MockHealthStore(weights: weights), planStore: try makeStore())
        await model.refresh()
        #expect(model.startWeightSuggestion == .latest(123.0))
    }

    @Test("記録がなければ none")
    func suggestionNone() async throws {
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: try makeStore())
        await model.refresh()
        #expect(model.startWeightSuggestion == .none)
    }

    @Test("startPlan で計画が保存され、ステージ1の減量中になる。起点は今日")
    func startPlan() async throws {
        let store = try makeStore()
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -6), days: 7, 123.5)), planStore: store)
        await model.refresh()
        try await model.startPlan(startWeight: 123.5, targetWeight: 67.4)
        let record = try #require(try store.load())
        #expect(record.phase == .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: today)))
        #expect(record.roadmap.startDay == today)
        #expect(record.roadmap.targetWeight == 67.4)
        #expect(model.summary?.plan?.stageNumber == 1)
        #expect(model.summary?.plan?.progress == .settlingIn)
    }

    @Test("検証に通らなければ投げて保存しない")
    func startPlanInvalid() async throws {
        let store = try makeStore()
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: store)
        await #expect(throws: HomeModel.StartPlanError.invalid(.targetNotBelowStart)) {
            try await model.startPlan(startWeight: 67.4, targetWeight: 67.4)
        }
        #expect(try store.load() == nil)
    }

    @Test("ステージ1で7日平均(丸め)が最初の区切り以下になったら到達日を保存し、戻っても消えない")
    func recordsFirstMilestone() async throws {
        let store = try makeStore()
        let startDay = today.adding(days: -60)
        let roadmap = Roadmap(startWeight: 123.5, startDay: startDay, targetWeight: 67.4, settings: .default)
        try store.save(PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let health = MockHealthStore(weights: samples(from: today.adding(days: -6), days: 7, 117.3))
        let model = HomeModel(health: health, planStore: store)
        await model.refresh()
        // 起点以降で最初に7日平均(丸め)が区切り以下になった日 = 記録が始まった日
        let reached = today.adding(days: -6)
        #expect(try store.load()?.firstMilestoneReachedOn == reached)
        #expect(model.summary?.plan?.firstMilestoneReachedOn == reached)
        #expect(model.summary?.plan?.record.unreadEvents.map(\.kind) == [.firstMilestoneReached(weight: 117.3, nextBoundary: 111.2)])

        // 翌日以降に区切りを上回っても消えない(今日の値で再取得)
        await health.replaceWeights(samples(from: today.adding(days: -6), days: 7, 118.0))
        await model.refresh()
        #expect(try store.load()?.firstMilestoneReachedOn == reached)
    }

    @Test("ステージ2では最初の区切りを保存しない")
    func noMilestoneOnStage2() async throws {
        let store = try makeStore()
        let roadmap = Roadmap(startWeight: 123.5, startDay: today.adding(days: -300), targetWeight: 67.4, settings: .default)
        let maintaining = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: today.adding(days: -100))!
        let stage2 = roadmap.phaseOnAdvance(from: maintaining, sevenDayAverage: 111.0, on: today.adding(days: -40))!
        try store.save(PlanRecord(roadmap: roadmap, phase: stage2, originalRoadmap: nil, declinedEarlyArrivalOn: nil))
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -6), days: 7, 105.0)), planStore: store)
        await model.refresh()
        #expect(try store.load()?.firstMilestoneReachedOn == nil)
    }

    @Test("保存した計画が読めなければ失敗になり、初回設定には進まない")
    func unreadablePlanIsFailure() async throws {
        let store = try makeStore()
        try Data(#"{"schemaVersion": 2}"#.utf8).write(to: store.fileURL)
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: store)
        await model.refresh()
        #expect(model.lastRefreshFailed)
        #expect(model.summary == nil)
        #expect(RootRoute.route(for: model) == .failed)
    }
}

/// 取得の完了順を制御できる HealthStore。呼ばれた順に delays の待ち時間を使う。
actor DelayedHealthStore: HealthStore {
    private var weights: [WeightSample]
    private var delays: [Duration]
    private var failures: [Bool]
    private var calls = 0

    init(weights: [WeightSample], delays: [Duration], failures: [Bool] = []) {
        self.weights = weights
        self.delays = delays
        self.failures = failures
    }

    func replaceWeights(_ weights: [WeightSample]) { self.weights = weights }

    func requestReadAuthorization() async throws {}

    func weightSamples(from: Date, to: Date) async throws -> [WeightSample] {
        let index = calls
        calls += 1
        let snapshot = weights
        if index < delays.count { try await Task.sleep(for: delays[index]) }
        if index < failures.count, failures[index] { throw HomeModelTests.Failure() }
        return snapshot.filter { $0.measuredAt >= from && $0.measuredAt < to }
    }

    func bodyFatSamples(from: Date, to: Date) async throws -> [BodyFatSample] { [] }
}

@MainActor
struct HomeModelRefreshOrderTests {
    let cal = AppCalendar.tokyo
    var today: CalendarDay { CalendarDay(date: Date(), calendar: cal) }

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HomeModelRefreshOrderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func sample(_ kg: Double) -> [WeightSample] {
        [WeightSample(kilograms: kg, measuredAt: today.startDate(in: cal).addingTimeInterval(8 * 3600), source: .healthPlanet)]
    }

    @Test("遅く終わった古い取得は、先に終わった新しい結果を上書きしない")
    func staleSuccessIsIgnored() async throws {
        let health = DelayedHealthStore(weights: sample(123.5), delays: [.milliseconds(300), .zero])
        let model = HomeModel(health: health, planStore: try makeStore())
        let first = Task { await model.refresh() }           // 古い値(123.5)で 300ms 待つ
        try await Task.sleep(for: .milliseconds(50))
        await health.replaceWeights(sample(120.0))
        await model.refresh()                                // 新しい値で先に終わる
        #expect(model.summary?.sevenDayAverage?.kilograms == 120.0)
        await first.value
        #expect(model.summary?.sevenDayAverage?.kilograms == 120.0)
        #expect(!model.lastRefreshFailed)
    }

    @Test("遅く終わった古い失敗は、先に終わった新しい成功を失敗にしない")
    func staleFailureIsIgnored() async throws {
        let health = DelayedHealthStore(weights: sample(123.5), delays: [.milliseconds(300), .zero], failures: [true, false])
        let model = HomeModel(health: health, planStore: try makeStore())
        let first = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        await model.refresh()
        #expect(!model.lastRefreshFailed)
        await first.value
        #expect(!model.lastRefreshFailed)
        #expect(model.summary?.sevenDayAverage?.kilograms == 123.5)
    }

    @Test("保存後の取り直しに失敗したら savedButRefreshFailed を投げ、計画は保存されている")
    func savedButRefreshFailed() async throws {
        let store = try makeStore()
        let health = MockHealthStore(weights: sample(123.5))
        let model = HomeModel(health: health, planStore: store)
        await model.refresh()
        await health.setFailure(HomeModelTests.Failure())
        await #expect(throws: HomeModel.StartPlanError.savedButRefreshFailed) {
            try await model.startPlan(startWeight: 123.5, targetWeight: 67.4)
        }
        #expect(try store.load()?.roadmap.startDay == today)
        // もう一度押しても上書きしない
        await #expect(throws: HomeModel.StartPlanError.alreadyStarted) {
            try await model.startPlan(startWeight: 100.0, targetWeight: 67.4)
        }
        #expect(try store.load()?.roadmap.startWeight == 123.5)
        // 次の取り直しが成功すればホームに進む
        await health.setFailure(nil)
        await model.refresh()
        #expect(RootRoute.route(for: model) == .home)
    }
}

extension HomeModelRefreshOrderTests {
    @Test("保存後の取り直しが別の取り直しに置き換えられても、最新の結果が成功なら失敗にしない")
    func startPlanSupersededBySuccessfulRefresh() async throws {
        let store = try makeStore()
        // 1回目: 初回取得(即)、2回目: startPlan の取り直し(300ms)、3回目: 復帰時の取り直し(100ms)
        let health = DelayedHealthStore(weights: sample(123.5), delays: [.zero, .milliseconds(300), .milliseconds(100)])
        let model = HomeModel(health: health, planStore: store)
        await model.refresh()
        #expect(RootRoute.route(for: model) == .setup)

        let starting = Task { try await model.startPlan(startWeight: 123.5, targetWeight: 67.4) }
        try await Task.sleep(for: .milliseconds(50))
        let outcome = await model.refresh()          // 後から始まって先に終わる
        #expect(outcome == .succeeded)
        try await starting.value                     // 投げない
        #expect(RootRoute.route(for: model) == .home)
        #expect(model.summary?.plan?.stageNumber == 1)
    }

    @Test("refresh の戻り値: 置き換えられた古い要求は superseded、最新は succeeded")
    func outcomes() async throws {
        let health = DelayedHealthStore(weights: sample(123.5), delays: [.milliseconds(300), .zero])
        let model = HomeModel(health: health, planStore: try makeStore())
        let first = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await model.refresh() == .succeeded)
        #expect(await first.value == .superseded)
        #expect(await model.awaitLatestRefresh() == .succeeded)
    }

    @Test("利用不可なら failed")
    func unavailableOutcome() async {
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: nil)
        #expect(await model.refresh() == .failed)
        #expect(await model.awaitLatestRefresh() == .failed)
    }
}

extension HomeModelRefreshOrderTests {
    @Test("awaitLatestRefresh は、待っている間に始まった新しい取り直しの結果を返す")
    func awaitLatestFollowsNewerRefresh() async throws {
        // A: 300ms で成功、B: 100ms で失敗。待ち始めは A、途中で B が始まり先に終わる
        let health = DelayedHealthStore(weights: sample(123.5), delays: [.milliseconds(300), .milliseconds(100)], failures: [false, true])
        let model = HomeModel(health: health, planStore: try makeStore())
        let a = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        let waiter = Task { await model.awaitLatestRefresh() }
        try await Task.sleep(for: .milliseconds(20))
        let b = Task { await model.refresh() }
        #expect(await b.value == .failed)
        #expect(await waiter.value == .failed)
        #expect(await a.value == .superseded)
        #expect(model.lastRefreshFailed)
    }
}

extension HomeModelSetupTests {
    @Test("開始日を過去に指定すると、その日が計画の開始日と起点の日になる")
    func startPlanWithPastStartDay() async throws {
        let store = try makeStore()
        let model = HomeModel(health: MockHealthStore(weights: samples(from: today.adding(days: -4), days: 5, 123.1)), planStore: store)
        await model.refresh()
        let startDay = today.adding(days: -4)
        try await model.startPlan(startWeight: 123.1, targetWeight: 67.4, startDay: startDay)
        let record = try #require(try store.load())
        #expect(record.roadmap.startDay == startDay)
        #expect(record.phase == .losing(stage: 1, origin: StageOrigin(weight: 123.1, day: startDay)))
        let days = Pace.days(toReach: record.roadmap.stages[0].boundaryWeight / 123.1, monthlyRate: PlanSettings.default.monthlyRate, settings: .default)
        #expect(record.roadmap.stages[0].estimatedArrival == startDay.adding(days: days))
    }

    @Test("開始日が今日より後なら投げて保存しない")
    func startPlanFutureStartDay() async throws {
        let store = try makeStore()
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: store)
        await model.refresh()
        await #expect(throws: HomeModel.StartPlanError.startDayInFuture) {
            try await model.startPlan(startWeight: 123.1, targetWeight: 67.4, startDay: today.adding(days: 1))
        }
        #expect(try store.load() == nil)
    }

    @Test("開始体重の提案は日付ごとに変わる(7日平均 → 最新値 → なし)")
    func suggestionByDay() {
        let w = [DailyWeight(day: today.adding(days: -10), kilograms: 124.0, measuredAt: Date(), source: .healthPlanet)]
        #expect(HomeModel.startWeightSuggestion(on: today.adding(days: -10), weights: w) == .sevenDayAverage(124.0))
        #expect(HomeModel.startWeightSuggestion(on: today, weights: w) == .latest(124.0))
        #expect(HomeModel.startWeightSuggestion(on: today.adding(days: -11), weights: w) == .none)
    }
}

extension HomeModelSetupTests {
    @Test("最初の記録が60日前でも、初回設定の開始日はその日まで遡れる")
    func earliestStartDayBeyondHistory() async throws {
        let first = today.adding(days: -60)
        let model = HomeModel(health: MockHealthStore(weights: samples(from: first, days: 61, 123.5)), planStore: try makeStore())
        await model.refresh()
        let form = SetupFormState(today: today, weights: model.recordedWeights)
        #expect(form.earliestStartDay == first)
        #expect(model.recordedWeights.count == 61)
    }

    @Test("28日表示の範囲より前の記録も、選んだ開始日の7日平均に使う")
    func suggestionUsesRecordsBeforeHistoryWindow() async throws {
        // 29日前 124.0、28日前 123.0、27日前 122.0。27日前を開始日に選ぶと3件の平均 123.0
        var weights = samples(from: today.adding(days: -29), days: 1, 124.0)
        weights += samples(from: today.adding(days: -28), days: 1, 123.0)
        weights += samples(from: today.adding(days: -27), days: 1, 122.0)
        let model = HomeModel(health: MockHealthStore(weights: weights), planStore: try makeStore())
        await model.refresh()
        var form = SetupFormState(today: today, weights: model.recordedWeights)
        form.startDayChanged(today.adding(days: -27))
        #expect(form.startSuggestion == .sevenDayAverage(123.0))
        #expect(form.startText == "123.0")
    }
}
