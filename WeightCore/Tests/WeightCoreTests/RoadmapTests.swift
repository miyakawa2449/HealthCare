import Foundation
import Testing
@testable import WeightCore

struct RoadmapTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)

    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }

    @Test("境界は6つ(固定の期待値)")
    func boundaries() {
        #expect(roadmap.stages.map(\.boundaryWeight) == [111.2, 100.0, 90.0, 81.0, 72.9, 67.4])
        #expect(roadmap.stages.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(roadmap.stages.map(\.startWeight) == [123.5, 111.2, 100.0, 90.0, 81.0, 72.9])
    }

    @Test("最初の5%のマイルストーン")
    func milestone() {
        #expect(roadmap.firstMilestoneWeight == 117.3)
    }

    @Test("境界が目標と一致したら、それが最終ステージ")
    func boundaryEqualsTarget() {
        let r = Roadmap(startWeight: 100.0, startDay: start, targetWeight: 81.0, settings: s)
        #expect(r.stages.map(\.boundaryWeight) == [90.0, 81.0])
    }

    @Test("目標が境界の途中なら目標で打ち切る")
    func cutAtTarget() {
        let r = Roadmap(startWeight: 80.0, startDay: start, targetWeight: 67.4, settings: s)
        #expect(r.stages.map(\.boundaryWeight) == [72.0, 67.4])
    }

    @Test("開始が目標以下ならステージなし")
    func noStages() {
        #expect(Roadmap(startWeight: 67.0, startDay: start, targetWeight: 67.4, settings: s).stages.isEmpty)
        #expect(Roadmap(startWeight: 67.4, startDay: start, targetWeight: 67.4, settings: s).stages.isEmpty)
    }

    @Test("到達予定日: ステージ1は156日後、ステージ2は維持期間(定数)と158日を足す")
    func estimatedArrival() {
        let stages = roadmap.stages
        #expect(stages[0].estimatedArrival == day(2027, 3, 23))
        #expect(stages[0].estimatedArrival == start.adding(days: 156))
        #expect(stages[1].estimatedArrival == stages[0].estimatedArrival.adding(days: s.assumedMaintenanceDays + 158))
    }

    @Test("今いるステージ(丸めた7日平均が境界以下なら到達済み)")
    func currentStage() {
        #expect(roadmap.stage(containing: 111.2)?.number == 2)
        #expect(roadmap.stage(containing: 111.25)?.number == 1)   // 丸めて 111.3
        #expect(roadmap.stage(containing: 123.5)?.number == 1)
        #expect(roadmap.stage(containing: 125.0)?.number == 1)    // 開始より増えてもステージ1
        #expect(roadmap.stage(containing: 67.4) == nil)           // 最終目標に到達
        #expect(roadmap.hasReachedTarget(sevenDayAverage: 67.44))
        #expect(!roadmap.hasReachedTarget(sevenDayAverage: 67.45))
    }

    @Test("Codable で往復できる")
    func codable() throws {
        let data = try JSONEncoder().encode(roadmap)
        let decoded = try JSONDecoder().decode(Roadmap.self, from: data)
        #expect(decoded == roadmap)
    }

    @Test("見直しの採用で起点を取り直しても、境界は変えない")
    func rebase() {
        let rebased = Roadmap(rebasing: roadmap, startWeight: 118.0, startDay: day(2026, 11, 20))
        #expect(rebased.stages.map(\.boundaryWeight) == [111.2, 100.0, 90.0, 81.0, 72.9, 67.4])
        #expect(rebased.firstMilestoneWeight == 117.3)
        #expect(rebased.startWeight == 118.0)
        #expect(rebased.startDay == day(2026, 11, 20))
        // ステージ1の到達予定は 118.0 → 111.2 を月2%で: ceil(ln(111.2/118.0)/ln(0.98)×30) = 89日
        #expect(rebased.stages[0].estimatedArrival == day(2026, 11, 20).adding(days: 89))
        #expect(rebased.stages[1].estimatedArrival == rebased.stages[0].estimatedArrival.adding(days: s.assumedMaintenanceDays + 158))
    }
}
