import Foundation
import Testing
import WeightCore
@testable import WeightApp

@MainActor
struct RootRouteTests {
    func makeStore() throws -> PlanStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RootRouteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PlanStore(directory: dir)
    }

    @Test("利用不可 → unavailable")
    func unavailable() throws {
        #expect(RootRoute.route(for: HomeModel(health: MockHealthStore(weights: []), planStore: nil)) == .unavailable)
    }

    @Test("取得前 → loading")
    func loading() throws {
        #expect(RootRoute.route(for: HomeModel(health: MockHealthStore(weights: []), planStore: try makeStore())) == .loading)
    }

    @Test("最初の取得に失敗 → failed")
    func failed() async throws {
        let health = MockHealthStore(weights: [])
        await health.setFailure(HomeModelTests.Failure())
        let model = HomeModel(health: health, planStore: try makeStore())
        await model.refresh()
        #expect(RootRoute.route(for: model) == .failed)
    }

    @Test("計画なし → setup、計画あり → home")
    func setupAndHome() async throws {
        let model = HomeModel(health: MockHealthStore(weights: []), planStore: try makeStore())
        await model.refresh()
        #expect(RootRoute.route(for: model) == .setup)
        try await model.startPlan(startWeight: 123.5, targetWeight: 67.4)
        #expect(RootRoute.route(for: model) == .home)
    }
}
