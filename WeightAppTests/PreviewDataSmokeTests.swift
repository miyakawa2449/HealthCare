import Foundation
import Testing
import WeightCore
@testable import WeightApp

/// `#Preview` のデータが意図した状態(カードの種類、フェーズ)になることを確かめる。数値は見ない。
@MainActor
struct PreviewDataSmokeTests {
    /// PreviewData は Task で refresh を始めるだけなので、ここで改めて refresh し、最新の取り直しが終わるまで待つ。
    func cards(_ model: HomeModel) async -> [HomeCard] {
        await settle(model)
        return model.cards
    }

    func settle(_ model: HomeModel) async {
        await model.refresh()
        _ = await model.awaitLatestRefresh()
    }

    @Test("出来事1件 + 提案1件(85日目)")
    func eventAndProposal() async {
        let model = PreviewData.homeModel(.eventAndProposal)
        let cards = await cards(model)
        #expect(cards.count == 2, "\(cards)")
        if case .event = cards.first {} else { Issue.record("1枚目が出来事ではない: \(cards)") }
        #expect(cards.last == .maintenanceMaximum(canAdvance: true))
    }

    @Test("一言だけ")
    func noticeOnly() async {
        let model = PreviewData.homeModel(.noticeOnly)
        let cards = await cards(model)
        #expect(cards.count == 1, "\(cards)")
        if case .maintenanceNotice(.aboveBand) = cards.first {} else { Issue.record("維持の一言(上)ではない: \(cards)") }
    }

    @Test("カードなし(計画どおり)")
    func onTrack() async {
        let model = PreviewData.homeModel(.onTrack)
        #expect(await cards(model).isEmpty)
    }

    @Test("ステージ3の減量中のまま(自動遷移で変わらない)")
    func stage3() async {
        let model = PreviewData.homeModel(.stage3)
        await settle(model)
        #expect(model.summary?.plan?.phase.losingStage == 3, "\(String(describing: model.summary?.plan?.phase))")
        #expect(model.cards.isEmpty)
    }

    @Test("見直し採用後は「元の計画に戻す」が出る")
    func afterReview() async {
        let model = PreviewData.homeModel(.afterReview)
        await settle(model)
        let rows = RoadmapRows.make(record: model.summary!.plan!.record, on: model.summary!.day)
        #expect(rows.revert != nil)
        #expect(rows.stages[0].isCurrent)
    }

    @Test("維持モード")
    func maintenanceMode() async {
        let model = PreviewData.homeModel(.maintenanceMode)
        await settle(model)
        let rows = RoadmapRows.make(record: model.summary!.plan!.record, on: model.summary!.day)
        #expect(rows.maintenanceMode != nil)
    }
}
