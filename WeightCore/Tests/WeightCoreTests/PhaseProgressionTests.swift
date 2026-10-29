import Foundation
import Testing
@testable import WeightCore

struct PhaseProgressionTests {
    let s = PlanSettings.default
    let start = day(2026, 10, 18)
    var roadmap: Roadmap { Roadmap(startWeight: 123.5, startDay: start, targetWeight: 67.4, settings: s) }

    func advance(_ phase: PlanPhase, _ weights: [DailyWeight], through d: CalendarDay, roadmap r: Roadmap? = nil) -> PhaseProgression.Result {
        PhaseProgression.advance(phase: phase, roadmap: r ?? roadmap, weights: weights, through: d, settings: s)
    }

    @Test("境界より上のままなら遷移なし")
    func noTransition() {
        let w = constantWeights(from: start.adding(days: -6), days: 60, 120.0)
        let r = advance(roadmap.initialPhase!, w, through: start.adding(days: 53))
        #expect(r.transitions.isEmpty)
        #expect(r.phase == roadmap.initialPhase!)
        #expect(r.roadmap == roadmap)
    }

    @Test("7日平均(丸め)がちょうど境界になった最初の日に到達し、維持期間へ。到達予定日は到達日になる")
    func arrivesAtBoundary() {
        // 10/18〜11/29 は 112.0、11/30 以降は 111.2(11/30 の窓は 112.0×6 + 111.2 → 111.87 なので未到達)
        var w = constantWeights(from: start, days: 43, 112.0)
        w += constantWeights(from: day(2026, 11, 30), days: 20, 111.2)
        // 7日平均が 111.2 に丸まる最初の日を計算で求める
        let arrivalDay = (0..<20).map { day(2026, 11, 30).adding(days: $0) }.first { Weight.rounded(SevenDayAverage(endingOn: $0, in: w)!.kilograms) <= 111.2 }!
        let r = advance(roadmap.initialPhase!, w, through: day(2026, 12, 25))
        #expect(r.transitions.count == 1)
        guard case .arrived(let stage, let on, let avg) = r.transitions[0] else { Issue.record("arrived ではない"); return }
        #expect(stage == 1)
        #expect(on == arrivalDay)
        #expect(avg == 111.2)
        #expect(r.phase == .maintaining(stage: 1, arrival: StageOrigin(weight: 111.2, day: arrivalDay)))
        #expect(r.roadmap.stages[0].estimatedArrival == arrivalDay)
        #expect(r.roadmap.stages.map(\.boundaryWeight) == roadmap.stages.map(\.boundaryWeight))
    }

    @Test("境界の丸め: 111.25 は到達しない、111.24 は到達")
    func rounding() {
        let notYet = constantWeights(from: start, days: 30, 111.25)
        #expect(advance(roadmap.initialPhase!, notYet, through: start.adding(days: 29)).transitions.isEmpty)
        let reached = constantWeights(from: start, days: 30, 111.24)
        let r = advance(roadmap.initialPhase!, reached, through: start.adding(days: 29))
        guard case .arrived(_, let on, _) = r.transitions.first else { Issue.record("arrived ではない"); return }
        #expect(on == start)   // 起点の日から対象
    }

    @Test("到達後に境界より上へ戻っても、到達日は最初に下回った日のまま。開いていなかった日でもさかのぼる")
    func arrivalDayIsFirstDayBelow() {
        var w = constantWeights(from: start, days: 20, 111.0)   // 10/18〜11/6 は 111.0
        w += constantWeights(from: start.adding(days: 20), days: 30, 114.0)   // 111.0 の +2% の外(卒業しない)
        let r = advance(roadmap.initialPhase!, w, through: start.adding(days: 49))
        guard case .arrived(_, let on, _) = r.transitions.first else { Issue.record("arrived ではない"); return }
        #expect(on == start)
        #expect(r.phase == .maintaining(stage: 1, arrival: StageOrigin(weight: 111.0, day: start)))
    }

    @Test("見直しで起点を取り直した日に既に境界以下なら、起点の日に到達")
    func rebasedOriginAlreadyBelow() {
        let origin = day(2026, 12, 1)
        let phase = roadmap.initialPhase!.rebased(sevenDayAverage: 111.0, on: origin)!
        let w = constantWeights(from: origin.adding(days: -6), days: 20, 111.0)
        let r = advance(phase, w, through: origin.adding(days: 10))
        guard case .arrived(_, let on, _) = r.transitions.first else { Issue.record("arrived ではない"); return }
        #expect(on == origin)
    }

    @Test("維持期間で28日連続範囲内なら卒業し、その日の7日平均と日付を起点に次のステージの減量中へ")
    func graduates() {
        let arrivalDay = day(2027, 3, 23)
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        let w = constantWeights(from: arrivalDay.adding(days: -6), days: 60, 111.0)
        let r = advance(phase, w, through: arrivalDay.adding(days: 40))
        let gradDay = arrivalDay.adding(days: 27)
        #expect(r.transitions == [.graduated(fromStage: 1, on: gradDay, sevenDayAverage: 111.0)])
        #expect(r.phase == .losing(stage: 2, origin: StageOrigin(weight: 111.0, day: gradDay)))
        #expect(r.roadmap.stages[0].estimatedArrival == arrivalDay)
        let days = Pace.days(toReach: 100.0 / 111.0, monthlyRate: s.monthlyRate, settings: s)
        #expect(r.roadmap.stages[1].estimatedArrival == gradDay.adding(days: days))
    }

    @Test("卒業した日の7日平均が既に次の境界以下なら、同じ日に次の到達まで連鎖する")
    func chains() {
        // 範囲 ±2% を保ちながら 100.0 以下、という極端な例は作れないので、到達時体重 101.5 の維持期間で
        // 7日平均 99.9(−1.6% で範囲内、かつ境界 100.0 以下)が28日続く形にする
        let arrivalDay = day(2027, 3, 23)
        let phase = PlanPhase.maintaining(stage: 1, arrival: StageOrigin(weight: 101.5, day: arrivalDay))
        let w = constantWeights(from: arrivalDay.adding(days: -6), days: 60, 99.9)
        let r = advance(phase, w, through: arrivalDay.adding(days: 40))
        let gradDay = arrivalDay.adding(days: 27)
        #expect(r.transitions.count == 2)
        #expect(r.transitions[0] == .graduated(fromStage: 1, on: gradDay, sevenDayAverage: 99.9))
        #expect(r.transitions[1] == .arrived(stage: 2, on: gradDay, sevenDayAverage: 99.9))
        #expect(r.phase == .maintaining(stage: 2, arrival: StageOrigin(weight: 99.9, day: gradDay)))
    }

    @Test("維持期間で範囲外が続いて85日目でも遷移しない(カード側の扱い)")
    func exceededMaximumNoTransition() {
        let arrivalDay = day(2027, 3, 23)
        let phase = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: arrivalDay)!
        let w = constantWeights(from: arrivalDay.adding(days: -6), days: 100, 115.0)
        let r = advance(phase, w, through: arrivalDay.adding(days: 85))
        #expect(r.transitions.isEmpty)
        #expect(r.phase == phase)
    }

    @Test("最終ステージで最終目標以下なら維持モードへ")
    func finalStage() {
        let origin = day(2029, 1, 1)
        let phase = PlanPhase.losing(stage: 6, origin: StageOrigin(weight: 72.9, day: origin))
        let w = constantWeights(from: origin.adding(days: -6), days: 60, 67.4)
        let r = advance(phase, w, through: origin.adding(days: 30))
        #expect(r.transitions == [.arrived(stage: 6, on: origin, sevenDayAverage: 67.4)])
        #expect(r.phase == .maintenanceMode(arrival: StageOrigin(weight: 67.4, day: origin)))
    }

    @Test("維持モードでは遷移しない")
    func maintenanceMode() {
        let phase = PlanPhase.maintenanceMode(arrival: StageOrigin(weight: 67.4, day: day(2029, 2, 3)))
        let w = constantWeights(from: day(2029, 1, 28), days: 60, 60.0)
        let r = advance(phase, w, through: day(2029, 3, 20))
        #expect(r.transitions.isEmpty)
        #expect(r.phase == phase)
    }

    @Test("最初の区切り: 起点以降で最初に7日平均(丸め)が区切り以下になった日。ステージ1の減量中以外は nil")
    func firstMilestoneDay() {
        var w = constantWeights(from: start, days: 10, 118.0)
        w += constantWeights(from: start.adding(days: 10), days: 20, 117.3)
        let reached = (10..<30).map { start.adding(days: $0) }.first { Weight.rounded(SevenDayAverage(endingOn: $0, in: w)!.kilograms) <= 117.3 }!
        #expect(roadmap.firstMilestoneReachedDay(phase: roadmap.initialPhase!, weights: w, through: start.adding(days: 29)) == reached)
        #expect(roadmap.firstMilestoneReachedDay(phase: roadmap.initialPhase!, weights: w, through: reached.adding(days: -1)) == nil)
        let maintaining = roadmap.phaseOnArrival(stage: 1, sevenDayAverage: 111.2, on: day(2027, 3, 23))!
        #expect(roadmap.firstMilestoneReachedDay(phase: maintaining, weights: w, through: day(2027, 4, 1)) == nil)
    }

    @Test("設定値: 再提案の日数は早期到達・計画見直し・維持を続けるで共通の14日(PlanSettings は保存されるので項目を足さない)")
    func settings() {
        #expect(s.earlyArrivalRetryDays == 14)
    }
}
