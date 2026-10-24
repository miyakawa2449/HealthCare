import Testing
@testable import WeightCore

struct EarlyArrivalTests {
    let s = PlanSettings.default
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: day(2026, 10, 18), targetWeight: 67.4, settings: s) }
    var maintaining1: PlanPhase { .maintaining(stage: 1, arrival: StageOrigin(weight: 111.2, day: day(2027, 3, 23))) }

    @Test("次の境界ちょうど(丸め後)なら早期到達。上なら nil")
    func detection() {
        #expect(roadmap.earlyArrival(phase: maintaining1, sevenDayAverage: 100.04) == 2)
        #expect(roadmap.earlyArrival(phase: maintaining1, sevenDayAverage: 100.05) == nil)
        #expect(roadmap.earlyArrival(phase: maintaining1, sevenDayAverage: 95.0) == 2)
    }

    @Test("採用したら次のステージの維持期間へ。次が最終なら維持モード")
    func adoption() {
        let d = day(2027, 4, 10)
        #expect(roadmap.phaseOnEarlyArrival(from: maintaining1, sevenDayAverage: 100.04, on: d)
                == .maintaining(stage: 2, arrival: StageOrigin(weight: 100.0, day: d)))
        let maintaining5 = PlanPhase.maintaining(stage: 5, arrival: StageOrigin(weight: 72.9, day: day(2028, 1, 1)))
        #expect(roadmap.earlyArrival(phase: maintaining5, sevenDayAverage: 67.4) == 6)
        #expect(roadmap.phaseOnEarlyArrival(from: maintaining5, sevenDayAverage: 67.4, on: d)
                == .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: d)))
    }

    @Test("維持モードと減量中では nil")
    func otherPhases() {
        #expect(roadmap.earlyArrival(phase: .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: day(2029, 1, 1))), sevenDayAverage: 60.0) == nil)
        #expect(roadmap.earlyArrival(phase: roadmap.initialPhase!, sevenDayAverage: 100.0) == nil)
        #expect(roadmap.phaseOnEarlyArrival(from: roadmap.initialPhase!, sevenDayAverage: 100.0, on: day(2027, 1, 1)) == nil)
        // 境界より上なのに採用はできない
        #expect(roadmap.phaseOnEarlyArrival(from: maintaining1, sevenDayAverage: 100.05, on: day(2027, 4, 10)) == nil)
    }

    @Test("採用後の予定日: ステージ2は採用日、ステージ3は採用日 + 60 + 157")
    func reschedule() {
        let d = day(2027, 4, 10)
        let next = roadmap.phaseOnEarlyArrival(from: maintaining1, sevenDayAverage: 100.0, on: d)!
        let r = roadmap.rescheduled(from: next)
        #expect(r.stages[1].estimatedArrival == d)
        #expect(r.stages[2].estimatedArrival == d.adding(days: s.assumedMaintenanceDays + 157))
    }

    @Test("断った日から14日後に、まだ次の境界以下なら再提案する")
    func retryAfterDecline() {
        let declined = day(2027, 4, 10)
        #expect(EarlyArrivalProposal.shouldPropose(earlyArrivalStage: 2, declinedOn: nil, today: declined, settings: s))
        #expect(!EarlyArrivalProposal.shouldPropose(earlyArrivalStage: 2, declinedOn: declined, today: declined, settings: s))
        #expect(!EarlyArrivalProposal.shouldPropose(earlyArrivalStage: 2, declinedOn: declined, today: declined.adding(days: 13), settings: s))
        #expect(EarlyArrivalProposal.shouldPropose(earlyArrivalStage: 2, declinedOn: declined, today: declined.adding(days: 14), settings: s))
        #expect(!EarlyArrivalProposal.shouldPropose(earlyArrivalStage: nil, declinedOn: nil, today: declined, settings: s))
    }
}
