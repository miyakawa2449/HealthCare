import Foundation
import Testing
import WeightCore
@testable import WeightApp

struct HomeCardsTests {
    let s = PlanSettings.default
    let start = CalendarDay(year: 2026, month: 10, day: 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }
    let arrivalDay = CalendarDay(year: 2027, month: 3, day: 23)

    func status(_ record: PlanRecord, maintenance: MaintenanceState? = nil, notice: MaintenanceNotice? = nil,
                earlyArrivalStage: Int? = nil, proposeEarly: Bool = false, proposeReview: Bool = false, pace: ActualPace? = nil) -> PlanStatus {
        PlanStatus(record: record, stageNumber: record.phase.losingStage, guideline: 0, progress: nil, actualPace: pace,
                   maintenance: maintenance, maintenanceNotice: notice, earlyArrivalStage: earlyArrivalStage,
                   shouldProposeEarlyArrival: proposeEarly, shouldProposePlanReview: proposeReview)
    }

    var maintaining: PlanRecord {
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        return PlanRecord(roadmap: roadmap.rescheduled(from: phase), phase: phase, originalRoadmap: nil, declinedEarlyArrivalOn: nil)
    }
    var losing: PlanRecord { PlanRecord(roadmap: roadmap, phase: roadmap.initialPhase!, originalRoadmap: nil, declinedEarlyArrivalOn: nil) }

    func cards(_ plan: PlanStatus, average: Double? = 111.0, on day: CalendarDay) -> [HomeCard] {
        HomeCards.cards(for: plan, sevenDayAverage: average, on: day, settings: s)
    }

    @Test("出来事 → 85日目の順。85日目があれば維持の一言は出ない")
    func eventsAndMaximum() {
        var r = maintaining
        r.appendEvent(.firstMilestoneReached(weight: 117.3, nextBoundary: 111.2), on: start.adding(days: 50))
        r.appendEvent(.stageArrived(stage: 1, weight: 111.2), on: arrivalDay)
        let plan = status(r, maintenance: .exceededMaximum(consecutiveDaysInBand: 3), notice: .aboveBand(consecutiveDays: 20))
        let result = cards(plan, on: arrivalDay.adding(days: 85))
        #expect(result.count == 3)
        #expect(result[0] == .event(r.unreadEvents[0]))
        #expect(result[1] == .event(r.unreadEvents[1]))
        #expect(result[2] == .maintenanceMaximum(canAdvance: true))
    }

    @Test("85日目と早期到達が重なれば85日目だけ")
    func maximumBeatsEarlyArrival() {
        let plan = status(maintaining, maintenance: .exceededMaximum(consecutiveDaysInBand: 0), earlyArrivalStage: 2, proposeEarly: true)
        #expect(cards(plan, on: arrivalDay.adding(days: 85)) == [.maintenanceMaximum(canAdvance: true)])
    }

    @Test("早期到達: 境界の体重つき。断った日から13日は出ず、14日で出る(判定は WeightCore の shouldPropose)")
    func earlyArrival() {
        let plan = status(maintaining, maintenance: .inProgress(consecutiveDaysInBand: 3), earlyArrivalStage: 2, proposeEarly: true)
        #expect(cards(plan, on: arrivalDay.adding(days: 20)) == [.earlyArrival(nextStage: 2, boundary: 100.0)])
        let declined = status(maintaining, maintenance: .inProgress(consecutiveDaysInBand: 3), earlyArrivalStage: 2, proposeEarly: false)
        #expect(cards(declined, on: arrivalDay.adding(days: 20)).isEmpty)
    }

    @Test("85日目で「維持を続ける」から13日は出ず、14日で出る")
    func maximumRetry() {
        var r = maintaining
        r.continuedMaintenanceOn = arrivalDay.adding(days: 85)
        let plan = status(r, maintenance: .exceededMaximum(consecutiveDaysInBand: 0))
        #expect(cards(plan, on: arrivalDay.adding(days: 98)).isEmpty)
        #expect(cards(plan, on: arrivalDay.adding(days: 99)) == [.maintenanceMaximum(canAdvance: true)])
    }

    @Test("計画見直し: 変更前と変更後の予定日。断った日から13日は出ず、14日で出る")
    func planReview() {
        let day = start.adding(days: 60)
        let plan = status(losing, proposeReview: true)
        let result = cards(plan, average: 121.0, on: day)
        let rebased = roadmap.initialPhase!.rebased(sevenDayAverage: 121.0, on: day)!
        #expect(result == [.planReview(stage: 1, before: roadmap.stages[0].estimatedArrival, after: roadmap.rescheduled(from: rebased).stages[0].estimatedArrival)])

        var declined = losing
        declined.declinedPlanReviewOn = day
        #expect(cards(status(declined, proposeReview: true), average: 121.0, on: day.adding(days: 13)).isEmpty)
        #expect(cards(status(declined, proposeReview: true), average: 121.0, on: day.adding(days: 14)).count == 1)
    }

    @Test("元の計画に戻した直後は見直しが出ず、14日後に出る(03-decisions.md #4 の追加)")
    func afterRevert() throws {
        var r = losing
        try r.adoptPlanReview(sevenDayAverage: 121.0, on: start.adding(days: 60))
        let day = start.adding(days: 70)
        try r.revertToOriginalPlan(on: day)
        #expect(cards(status(r, proposeReview: true), average: 121.0, on: day).isEmpty)
        #expect(cards(status(r, proposeReview: true), average: 121.0, on: day.adding(days: 14)).count == 1)
    }

    @Test("計画見直しと速すぎるペースは両方出る")
    func reviewAndTooFast() {
        let fast = ActualPace(monthlyRate: 0.04, windowDays: 28)
        let result = cards(status(losing, proposeReview: true, pace: fast), average: 121.0, on: start.adding(days: 60))
        #expect(result.count == 2)
        if case .planReview = result[0] {} else { Issue.record("1枚目が見直しではない") }
        #expect(result[1] == .tooFast)
    }

    @Test("維持の一言(上)")
    func notice() {
        let plan = status(maintaining, maintenance: .inProgress(consecutiveDaysInBand: 0), notice: .aboveBand(consecutiveDays: 14))
        #expect(cards(plan, on: arrivalDay.adding(days: 20)) == [.maintenanceNotice(.aboveBand(consecutiveDays: 14))])
    }

    @Test("85日目で当日の7日平均がなければ進めない")
    func maximumWithoutAverage() {
        let plan = status(maintaining, maintenance: .exceededMaximum(consecutiveDaysInBand: 0))
        #expect(cards(plan, average: nil, on: arrivalDay.adding(days: 85)) == [.maintenanceMaximum(canAdvance: false)])
    }

    @Test("減量中で何もなければ空")
    func empty() {
        #expect(cards(status(losing), on: start.adding(days: 10)).isEmpty)
    }
}
