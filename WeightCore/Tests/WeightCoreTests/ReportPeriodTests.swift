import Foundation
import Testing
@testable import WeightCore

struct ReportPeriodTests {
    let s = ReportSettings.default

    @Test("月半ばは1日〜15日、公開日は15日")
    func midMonth() throws {
        let periods = ReportPeriod.periods(year: 2026, month: 11, planStart: day(2026, 10, 18), settings: s)
        let mid = try #require(periods.first)
        #expect(mid.kind == .midMonth)
        #expect(mid.firstDay == day(2026, 11, 1))
        #expect(mid.lastDay == day(2026, 11, 15))
        #expect(mid.releaseDay == day(2026, 11, 15))
        #expect(mid.dayCount == 15)
        #expect(mid.id == "2026-11-mid")
        #expect(mid.previousMonthEnd == day(2026, 10, 31))
    }

    @Test("月末の日は暦から求める(30日、31日、2月、うるう年)", arguments: [
        (2026, 11, 30), (2026, 12, 31), (2027, 2, 28), (2028, 2, 29),
    ])
    func monthEnd(year: Int, month: Int, last: Int) throws {
        let periods = ReportPeriod.periods(year: year, month: month, planStart: day(2026, 1, 1), settings: s)
        let end = try #require(periods.last)
        #expect(end.kind == .monthEnd)
        #expect(end.firstDay == day(year, month, 1))
        #expect(end.lastDay == day(year, month, last))
        #expect(end.dayCount == last)
        #expect(end.id == String(format: "%04d-%02d-end", year, month))
    }

    @Test("1月の前の月の末日は前年の12月31日")
    func previousMonthEndOverYear() throws {
        let p = try #require(ReportPeriod.periods(year: 2027, month: 1, planStart: day(2026, 1, 1), settings: s).first)
        #expect(p.previousMonthEnd == day(2026, 12, 31))
    }

    @Test("開始日 10/24、今日 11/24 の公開済みは 10月(24〜31日)と11月前半")
    func releasedFromPlanStart() {
        let released = ReportPeriod.released(planStart: day(2026, 10, 24), through: day(2026, 11, 24), settings: s)
        #expect(released.map(\.id) == ["2026-10-end", "2026-11-mid"])
        #expect(released[0].firstDay == day(2026, 10, 24))
        #expect(released[0].lastDay == day(2026, 10, 31))
        #expect(released[0].dayCount == 8)
        #expect(released[0].isClippedByPlanStart)
        #expect(!released[1].isClippedByPlanStart)
    }

    @Test("開始日より前に終わる月半ばは作らない")
    func noMidMonthBeforeStart() {
        let periods = ReportPeriod.periods(year: 2026, month: 10, planStart: day(2026, 10, 24), settings: s)
        #expect(periods.map(\.kind) == [.monthEnd])
    }

    @Test("開始日が1〜15日なら月半ばは開始日〜15日")
    func midMonthClipped() throws {
        let mid = try #require(ReportPeriod.periods(year: 2026, month: 11, planStart: day(2026, 11, 10), settings: s).first)
        #expect(mid.kind == .midMonth)
        #expect(mid.firstDay == day(2026, 11, 10))
        #expect(mid.dayCount == 6)
    }

    @Test("開始日が15日ちょうどなら月半ばは1日だけ")
    func midMonthOneDay() throws {
        let mid = try #require(ReportPeriod.periods(year: 2026, month: 11, planStart: day(2026, 11, 15), settings: s).first)
        #expect(mid.kind == .midMonth)
        #expect(mid.dayCount == 1)
    }

    @Test("公開日ちょうどの日から含まれる")
    func releaseBoundary() {
        let start = day(2026, 11, 1)
        #expect(ReportPeriod.released(planStart: start, through: day(2026, 11, 14), settings: s).isEmpty)
        #expect(ReportPeriod.released(planStart: start, through: day(2026, 11, 15), settings: s).map(\.id) == ["2026-11-mid"])
        #expect(ReportPeriod.released(planStart: start, through: day(2026, 11, 29), settings: s).map(\.id) == ["2026-11-mid"])
        #expect(ReportPeriod.released(planStart: start, through: day(2026, 11, 30), settings: s).map(\.id) == ["2026-11-mid", "2026-11-end"])
    }

    @Test("東京の 11/30 23:59 は月末のレポートが公開済み、11/29 23:59 はまだ")
    func releaseInTokyo() {
        let start = day(2026, 11, 1)
        let late30 = CalendarDay(date: jst(2026, 11, 30, 23, 59), calendar: TestCalendar.tokyo)
        let late29 = CalendarDay(date: jst(2026, 11, 29, 23, 59), calendar: TestCalendar.tokyo)
        #expect(ReportPeriod.released(planStart: start, through: late30, settings: s).last?.id == "2026-11-end")
        #expect(ReportPeriod.released(planStart: start, through: late29, settings: s).last?.id == "2026-11-mid")
    }

    @Test("年をまたいで並ぶ")
    func acrossYear() {
        let released = ReportPeriod.released(planStart: day(2026, 12, 20), through: day(2027, 1, 31), settings: s)
        #expect(released.map(\.id) == ["2026-12-end", "2027-01-mid", "2027-01-end"])
    }

    @Test("次の期間", arguments: [
        (day(2026, 11, 24), "2026-11-end"),
        (day(2026, 11, 30), "2026-12-mid"),
        (day(2026, 11, 14), "2026-11-mid"),
        (day(2026, 11, 15), "2026-11-end"),
        (day(2026, 12, 31), "2027-01-mid"),
    ])
    func next(today: CalendarDay, expected: String) {
        #expect(ReportPeriod.next(planStart: day(2026, 10, 24), after: today, settings: s).id == expected)
    }

    @Test("開始日が今日より後でも、次の期間は開始日を含む期間")
    func nextBeforeStart() {
        let next = ReportPeriod.next(planStart: day(2026, 11, 20), after: day(2026, 11, 20), settings: s)
        #expect(next.id == "2026-11-end")
        #expect(next.firstDay == day(2026, 11, 20))
    }
}

struct RecordContinuityTests {
    let s = ReportSettings.default

    func midNovember() throws -> ReportPeriod {
        try #require(ReportPeriod.periods(year: 2026, month: 11, planStart: day(2026, 10, 1), settings: s).first)
    }

    @Test("15日中13日に記録")
    func thirteenOfFifteen() throws {
        let period = try midNovember()
        var entries: [CalendarDay: Double] = [:]
        for d in 1...15 where d != 5 && d != 11 { entries[day(2026, 11, d)] = 120 }
        let c = RecordContinuity(period: period, weights: dailyWeights(entries))
        #expect(c.recordedDays == 13)
        #expect(c.totalDays == 15)
        #expect(c.marks.count == 15)
        #expect(c.marks.map(\.day) == (1...15).map { day(2026, 11, $0) })
        #expect(c.marks[4].recorded == false)
        #expect(c.marks[10].recorded == false)
        #expect(c.marks[0].recorded == true)
    }

    @Test("期間外の記録は数えない")
    func outside() throws {
        let period = try midNovember()
        let w = dailyWeights([day(2026, 10, 31): 120, day(2026, 11, 16): 120, day(2026, 11, 1): 120])
        let c = RecordContinuity(period: period, weights: w)
        #expect(c.recordedDays == 1)
    }

    @Test("記録なし")
    func none() throws {
        let c = RecordContinuity(period: try midNovember(), weights: [])
        #expect(c.recordedDays == 0)
        #expect(c.totalDays == 15)
        #expect(c.allRecorded == false)
    }

    @Test("すべての日")
    func all() throws {
        let c = RecordContinuity(period: try midNovember(), weights: constantWeights(from: day(2026, 11, 1), days: 15, 120))
        #expect(c.allRecorded)
    }
}
