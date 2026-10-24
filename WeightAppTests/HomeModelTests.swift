import Foundation
import Testing
import WeightCore
@testable import WeightApp

@MainActor
struct HomeModelTests {
    struct Failure: Error {}

    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HomeModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    func todaySamples() -> [WeightSample] {
        let today = CalendarDay(date: Date(), calendar: AppCalendar.tokyo)
        return [WeightSample(kilograms: 123.5, measuredAt: today.startDate(in: AppCalendar.tokyo).addingTimeInterval(8 * 3600), source: .healthPlanet)]
    }

    @Test("成功後に取り直しが失敗しても、前回の値を残して失敗だけを持つ")
    func keepsPreviousOnFailure() async throws {
        let health = MockHealthStore(weights: todaySamples())
        let model = HomeModel(health: health, planStore: try makeStore())
        await model.refresh()
        #expect(model.summary?.sevenDayAverage?.kilograms == 123.5)
        #expect(!model.lastRefreshFailed)

        await health.setFailure(Failure())
        await model.refresh()
        #expect(model.summary?.sevenDayAverage?.kilograms == 123.5)
        #expect(model.lastRefreshFailed)

        await health.setFailure(nil)
        await model.refresh()
        #expect(!model.lastRefreshFailed)
    }

    @Test("最初から失敗したら値はなく、失敗だけを持つ")
    func firstFailure() async throws {
        let health = MockHealthStore(weights: [])
        await health.setFailure(Failure())
        let model = HomeModel(health: health, planStore: try makeStore())
        await model.refresh()
        #expect(model.summary == nil)
        #expect(model.lastRefreshFailed)
    }

    @Test("保存先が取れない、または HealthKit が使えなければ利用不可")
    func unavailable() async throws {
        let noStore = HomeModel(health: MockHealthStore(weights: todaySamples()), planStore: nil)
        #expect(noStore.isUnavailable)
        await noStore.refresh()
        #expect(noStore.summary == nil)
        let noHealth = HomeModel(health: MockHealthStore(weights: []), planStore: try makeStore(), healthAvailable: false)
        #expect(noHealth.isUnavailable)
    }
}
