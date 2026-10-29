import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct RoadmapRowsTests {
    let s = PlanSettings.default
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }
    let arrivalDay = CalendarDay(year: 2027, month: 3, day: 23)

    func record(_ phase: PlanPhase, roadmap: Roadmap? = nil, milestone: CalendarDay? = nil) -> PlanRecord {
        let r = roadmap ?? self.roadmap
        return PlanRecord(roadmap: r.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil, firstMilestoneReachedOn: milestone)
    }

    @Test("ステージ1の減量中: 6ステージ + 5維持期間 + 最終目標。1が「いまここ」、以降は到達予定。最初の区切りはステージ1の中")
    func stage1Losing() {
        let rows = RoadmapRows.make(record: record(roadmap.initialPhase!), on: start.adding(days: 10))
        #expect(rows.stages.count == 6)
        #expect(rows.stages.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(rows.stages[0].status == .current)
        #expect(rows.stages[0].firstMilestone == .init(weight: 117.3, reachedOn: nil))
        #expect(rows.stages[1].firstMilestone == nil)
        for st in rows.stages.dropFirst() { #expect(st.status == .estimated(roadmap.stages[st.number - 1].estimatedArrival)) }
        #expect(rows.stages.map(\.maintenance) == [.upcoming, .upcoming, .upcoming, .upcoming, .upcoming, nil])
        #expect(rows.stages[0].startWeight == 123.5)
        #expect(rows.stages[0].boundaryWeight == 111.2)
        #expect(rows.target == .init(weight: 67.4, status: .estimated(roadmap.stages[5].estimatedArrival)))
        #expect(rows.revert == nil)
        #expect(rows.paceText == "標準のペースは月2%。1週間あたりでは無理のない範囲です。")
    }

    @Test("最初の区切りに届いた日が入る")
    func milestoneReached() {
        let rows = RoadmapRows.make(record: record(roadmap.initialPhase!, milestone: start.adding(days: 60)), on: start.adding(days: 70))
        #expect(rows.stages[0].firstMilestone == .init(weight: 117.3, reachedOn: start.adding(days: 60)))
    }

    @Test("ステージ1の維持期間: 1 は到達日、維持期間は「いまここ(到達から n日目)」")
    func stage1Maintaining() {
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        let rows = RoadmapRows.make(record: record(phase, milestone: start.adding(days: 60)), on: arrivalDay.adding(days: 11))
        #expect(rows.stages[0].status == .arrived(arrivalDay))
        #expect(rows.stages[0].maintenance == .current(dayNumber: 12))
        #expect(rows.stages[1].status == .estimated(arrivalDay.adding(days: s.assumedMaintenanceDays + Pace.days(toReach: 100.0 / 111.2, monthlyRate: s.monthlyRate, settings: s))))
        #expect(rows.stages[1].maintenance == .upcoming)
    }

    @Test("ステージ3の減量中: 1・2 は到達済み、維持期間1 は終了、2 は終了日つき、3 が「いまここ」")
    func stage3Losing() {
        // 1 到達 → 卒業 → 2 到達 → 卒業 → 3 減量中、の順に rescheduled を重ねる
        var r = roadmap
        let a1 = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        r = r.rescheduled(from: a1)
        let g1 = PlanPhase.losing(stage: 2, origin: StageOrigin(weight: 111.0, day: arrivalDay.adding(days: 28)))
        r = r.rescheduled(from: g1)
        let a2Day = arrivalDay.adding(days: 200)
        let a2 = r.phaseOnArrival(stage: 2, sevenDayAverage: 100.0, on: a2Day)!
        r = r.rescheduled(from: a2)
        let g2 = PlanPhase.losing(stage: 3, origin: StageOrigin(weight: 99.8, day: a2Day.adding(days: 30)))
        r = r.rescheduled(from: g2)
        let rec = PlanRecord(roadmap: r, phase: g2, originalRoadmap: nil, declinedEarlyArrivalOn: nil, firstMilestoneReachedOn: start.adding(days: 60))
        let rows = RoadmapRows.make(record: rec, on: a2Day.adding(days: 40))
        #expect(rows.stages[0].status == .arrived(arrivalDay))
        #expect(rows.stages[0].maintenance == .ended(nil))   // ステージ2の起点は保存していないので日付なし
        #expect(rows.stages[1].status == .arrived(a2Day))
        #expect(rows.stages[1].maintenance == .ended(a2Day.adding(days: 30)))
        #expect(rows.stages[2].status == .current)
        #expect(rows.stages[2].maintenance == .upcoming)
        #expect(rows.stages[3].status == .estimated(r.stages[3].estimatedArrival))
    }

    @Test("維持モード: すべて到達済み、最終ステージと最終目標に同じ到達日(自動遷移の結果をそのまま渡す)")
    func maintenanceMode() {
        let originDay = CalendarDay(year: 2029, month: 3, day: 1)
        let losing = PlanPhase.losing(stage: 6, origin: StageOrigin(weight: 72.9, day: originDay))
        let before = roadmap.rescheduled(from: losing)
        // 起点から 70日は 70.0、その後 67.3 → 到達日は 7日平均(丸め)が 67.4 以下になる最初の日
        let weights = (0..<100).map { i in DailyWeight(day: originDay.adding(days: i), kilograms: i < 70 ? 70.0 : 67.3, measuredAt: originDay.adding(days: i).startDate(in: AppCalendar.tokyo), source: .healthPlanet) }
        let today = originDay.adding(days: 99)
        let result = PhaseProgression.advance(phase: losing, roadmap: before, weights: weights, through: today, settings: s)
        var record = PlanRecord(roadmap: before, phase: losing, originalRoadmap: nil, declinedEarlyArrivalOn: nil, firstMilestoneReachedOn: start.adding(days: 60))
        record.apply(result)
        guard case .maintenanceMode(let arrival) = record.phase else { Issue.record("維持モードではない: \(record.phase)"); return }
        let rows = RoadmapRows.make(record: record, on: today)
        for st in rows.stages { #expect(st.status == .arrived(record.roadmap.stages[st.number - 1].estimatedArrival)) }
        #expect(rows.stages[5].status == .arrived(arrival.day))
        #expect(rows.target == .init(weight: 67.4, status: .arrived(arrival.day)))
        #expect(rows.maintenanceMode == arrival.day)
        #expect(arrival.day != before.stages[5].estimatedArrival)   // 予定日のままではない
    }

    @Test("見直し採用後: 元の計画に戻す行(今の予定 → 元の予定)")
    func afterReview() throws {
        var rec = PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
        let day = start.adding(days: 60)
        try rec.adoptPlanReview(sevenDayAverage: 121.0, on: day)
        let rows = RoadmapRows.make(record: rec, on: day.adding(days: 1))
        #expect(rows.revert == .init(stage: 1, current: rec.roadmap.stages[0].estimatedArrival, original: roadmap.stages[0].estimatedArrival))
        #expect(rows.stages[0].status == .current)
    }

    @Test("ペースの判定は月2%を週に換算して無理がない")
    func pace() {
        #expect(RoadmapRows.paceJudgment(settings: s) == .comfortable)
    }
}
