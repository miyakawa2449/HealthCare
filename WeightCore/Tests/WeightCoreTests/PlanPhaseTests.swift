import Foundation
import Testing
@testable import WeightCore

struct PlanPhaseTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }

    @Test("起点の体重は 0.1kg に丸めて持つ")
    func originRounded() {
        #expect(StageOrigin(weight: 111.15, day: start).weight == 111.2)
    }

    @Test("最初のフェーズはステージ1の減量中、起点は開始体重と開始日")
    func initialPhase() {
        #expect(roadmap.initialPhase == .losing(stage: 1, origin: StageOrigin(weight: 123.5, day: start)))
        let none = Roadmap(startWeight: 67.0, startDay: start, targetWeight: 67.4, settings: s)
        #expect(none.initialPhase == nil)   // ステージなしの計画にフェーズはない
    }

    @Test("到達したら維持期間へ。最終ステージなら維持モードへ")
    func arrival() {
        let d = day(2027, 3, 23)
        #expect(roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.18, on: d)
                == .maintaining(stage: 1, arrival: StageOrigin(weight: 111.2, day: d)))
        #expect(roadmap.phaseOnArrival(stage: 6, sevenDayAverage: 67.4, on: d)
                == .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: d)))
    }

    @Test("範囲外のステージ番号は受け付けない(0、ステージ数 + 1)")
    func rejectsOutOfRange() {
        let d = day(2027, 3, 23)
        #expect(roadmap.phaseOnArrival(stage: 0, sevenDayAverage: 111.2, on: d) == nil)
        #expect(roadmap.phaseOnArrival(stage: 7, sevenDayAverage: 67.4, on: d) == nil)
        let bogus = PlanPhase.maintaining(stage: 0, arrival: StageOrigin(weight: 111.2, day: d))
        #expect(roadmap.phaseOnAdvance(from: bogus, sevenDayAverage: 111.0, on: d) == nil)
        let bogus7 = PlanPhase.maintaining(stage: 7, arrival: StageOrigin(weight: 60.0, day: d))
        #expect(roadmap.phaseOnAdvance(from: bogus7, sevenDayAverage: 60.0, on: d) == nil)
        #expect(roadmap.rescheduled(from: .losing(stage: 0, origin: StageOrigin(weight: 120.0, day: d))) == roadmap)
        #expect(roadmap.rescheduled(from: .losing(stage: 7, origin: StageOrigin(weight: 60.0, day: d))) == roadmap)
        #expect(roadmap.rescheduled(from: .maintaining(stage: 7, arrival: StageOrigin(weight: 60.0, day: d))) == roadmap)
    }

    @Test("維持モードで計算し直すと、最終ステージの到達予定日が実際の到達日になり、他は変わらない")
    func rescheduledForMaintenanceMode() {
        let d = day(2029, 6, 1)
        let r = roadmap.rescheduled(from: .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: d)))
        #expect(r.stages[5].estimatedArrival == d)
        #expect(r.stages.dropLast().map(\.estimatedArrival) == roadmap.stages.dropLast().map(\.estimatedArrival))
        #expect(r.stages.map(\.boundaryWeight) == roadmap.stages.map(\.boundaryWeight))
    }

    @Test("次のステージへ進んだ日の7日平均(丸め)と日付が、次の減量ステージの起点になる")
    func advance() {
        let maintaining = PlanPhase.maintaining(stage: 1, arrival: StageOrigin(weight: 111.2, day: day(2027, 3, 23)))
        let next = roadmap.phaseOnAdvance(from: maintaining, sevenDayAverage: 110.94, on: day(2027, 5, 22))
        #expect(next == .losing(stage: 2, origin: StageOrigin(weight: 110.9, day: day(2027, 5, 22))))
        // 最終ステージの維持期間からは維持モードへ(通常は phaseOnArrival で直接入るが、念のため)
        let last = PlanPhase.maintaining(stage: 6, arrival: StageOrigin(weight: 67.4, day: day(2029, 1, 1)))
        #expect(roadmap.phaseOnAdvance(from: last, sevenDayAverage: 67.4, on: day(2029, 2, 1))
                == .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: day(2029, 1, 1))))
        // 減量中からは進めない
        #expect(roadmap.phaseOnAdvance(from: roadmap.initialPhase!, sevenDayAverage: 120.0, on: day(2026, 12, 1)) == nil)
    }

    @Test("計画見直しの採用は、減量中の起点を取り直す(境界は不変)")
    func rebase() {
        let rebased = roadmap.initialPhase!.rebased(sevenDayAverage: 118.04, on: day(2026, 11, 20))
        #expect(rebased == .losing(stage: 1, origin: StageOrigin(weight: 118.0, day: day(2026, 11, 20))))
        let maintaining = PlanPhase.maintaining(stage: 1, arrival: StageOrigin(weight: 111.2, day: day(2027, 3, 23)))
        #expect(maintaining.rebased(sevenDayAverage: 110.0, on: day(2027, 4, 1)) == nil)
    }

    @Test("到達予定日をフェーズから計算し直す(減量中: 起点から。維持中: 実際の到達日から)")
    func reschedule() {
        let r = roadmap
        let losing = PlanPhase.losing(stage: 1, origin: StageOrigin(weight: 118.0, day: day(2026, 11, 20)))
        let a = r.rescheduled(from: losing)
        #expect(a.stages.map(\.boundaryWeight) == r.stages.map(\.boundaryWeight))
        #expect(a.stages[0].estimatedArrival == day(2026, 11, 20).adding(days: 89))   // ceil(ln(111.2/118)/ln(0.98)×30)
        #expect(a.stages[1].estimatedArrival == a.stages[0].estimatedArrival.adding(days: s.assumedMaintenanceDays + 158))

        let maintaining = PlanPhase.maintaining(stage: 1, arrival: StageOrigin(weight: 111.2, day: day(2027, 4, 1)))
        let b = r.rescheduled(from: maintaining)
        #expect(b.stages[0].estimatedArrival == day(2027, 4, 1))
        #expect(b.stages[1].estimatedArrival == day(2027, 4, 1).adding(days: s.assumedMaintenanceDays + 158))
        #expect(b.stages[2].estimatedArrival == b.stages[1].estimatedArrival.adding(days: s.assumedMaintenanceDays + 157))   // 100.0 → 90.0

        // ステージ2の減量中: ステージ1の予定日は触らない
        let stage2 = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 110.9, day: day(2027, 5, 22)))
        let c = b.rescheduled(from: stage2)
        #expect(c.stages[0].estimatedArrival == day(2027, 4, 1))
        #expect(c.stages[1].estimatedArrival == day(2027, 5, 22).adding(days: 154))   // ceil(ln(100/110.9)/ln(0.98)×30)
    }

    @Test("最終ステージの計算し直し: 手前は不変、最終の予定日だけ起点から。維持中なら実際の到達日")
    func rescheduleLastStage() {
        let r = roadmap
        let losing = PlanPhase.losing(stage: 6, origin: StageOrigin(weight: 72.0, day: day(2029, 1, 10)))
        let a = r.rescheduled(from: losing)
        #expect(Array(a.stages[0..<5]) == Array(r.stages[0..<5]))
        #expect(a.stages[5].estimatedArrival == day(2029, 1, 10).adding(days: 99))   // ceil(ln(67.4/72.0)/ln(0.98)×30)
        let maintaining = PlanPhase.maintaining(stage: 6, arrival: StageOrigin(weight: 67.4, day: day(2029, 4, 1)))
        let b = r.rescheduled(from: maintaining)
        #expect(Array(b.stages[0..<5]) == Array(r.stages[0..<5]))
        #expect(b.stages[5].estimatedArrival == day(2029, 4, 1))
        // 維持モードも最終ステージの到達日を実際の日にする(手前は不変)
        let c = r.rescheduled(from: .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: day(2029, 4, 1))))
        #expect(Array(c.stages[0..<5]) == Array(r.stages[0..<5]))
        #expect(c.stages[5].estimatedArrival == day(2029, 4, 1))
    }

    @Test("Codable で往復できる")
    func codable() throws {
        let phases: [PlanPhase] = [
            roadmap.initialPhase!,
            .maintaining(stage: 2, arrival: StageOrigin(weight: 100.0, day: start)),
            .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: start)),
        ]
        for p in phases {
            let data = try JSONEncoder().encode(p)
            #expect(try JSONDecoder().decode(PlanPhase.self, from: data) == p)
        }
    }
}
