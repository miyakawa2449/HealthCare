# テストケースと Preview の一覧

数値は `Roadmap` と `Guideline` から計算して期待値にする。固定のカレンダーは `AppCalendar.tokyo`。
基準の計画: 開始 123.5kg、2026-10-18、最終目標 67.4(境界 111.2 / 100.0 / 90.0 / 81.0 / 72.9 / 67.4)。

## A. WeightCore: `PhaseProgression.advance`

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 減量中ステージ1、7日平均が境界(111.2)より上のまま | 遷移なし、フェーズそのまま |
| 2 | 11/30 から 7日平均(丸め)がちょうど 111.2 | `arrived(stage: 1, on: 11/30, avg)`、`.maintaining(1, arrival: (111.2, 11/30))` |
| 3 | 111.25(丸めて 111.3)の日は到達しない、111.24(111.2)の日は到達 | 境界の丸め |
| 4 | 到達の翌日以降に 7日平均が境界より上に戻っていても | 到達日は最初に下回った日のまま |
| 5 | `day` が到達日の10日後(アプリを開いていなかった) | 到達日は実際に下回った日 |
| 6 | 見直しで起点を取り直した日に既に境界以下 | 起点の日に到達 |
| 7 | 維持期間で 28日連続範囲内(到達日から) | `graduated(fromStage: 1, on: 到達日+27, avg)`、`.losing(2, origin: (その日の avg, その日))` |
| 8 | 卒業した日の 7日平均が既にステージ2の境界(100.0)以下(極端な例) | 同じ日に `arrived(stage: 2)` まで連鎖 |
| 9 | 維持期間で範囲外が続き 85日目 | 遷移なし(`exceededMaximum` はカード側) |
| 10 | 最終ステージ(6)で 67.4 以下 | `arrived(stage: 6)`、`.maintenanceMode` |
| 11 | 維持モード | 遷移なし |
| 12 | 到達予定日の更新: 到達後に `rescheduled(from:)` を適用した roadmap の `stages[0].estimatedArrival == 到達日` | アプリ側(DailySummaryBuilder)のテストで確認 |

## B. アプリ: `PlanRecord` の操作(`PlanRecord+Actions`)

| # | 操作 | 期待 |
| --- | --- | --- |
| 1 | `advanceAfterMaximum(avg, on:)`(維持期間、85日目) | `.losing(2, origin: (avg, day))`、`stages[1].estimatedArrival` が day から計算した日、`events` に `graduated(toStage: 2)`、`continuedMaintenanceOn == nil` |
| 2 | `advanceAfterMaximum` を減量中に呼ぶ | `notApplicable` |
| 3 | `continueMaintenance(on:)` | `continuedMaintenanceOn == day` |
| 4 | `adoptEarlyArrival(avg, on:)`(ステージ1の維持期間で avg ≤ 100.0) | `.maintaining(2, arrival: (avg, day))`、`events` に `stageArrived(2)`、`declinedEarlyArrivalOn == nil` |
| 5 | `adoptEarlyArrival` でステージ5 → 最終 | `.maintenanceMode`、`events` に `targetReached` |
| 6 | `adoptPlanReview(avg, on:)` | `originalRoadmap/originalPhase` に採用前、`phase.origin == (avg, day)`、境界は不変、`stages[k-1].estimatedArrival` が新しい起点から |
| 7 | `adoptPlanReview` を2回 | `originalRoadmap` は最初の採用前のまま(上書きしない) |
| 8 | `declinePlanReview(on:)` | `declinedPlanReviewOn == day` |
| 9 | `revertToOriginalPlan()`(同じステージの減量中) | `roadmap/phase` が採用前に戻り、original は nil |
| 10 | `revertToOriginalPlan()` を維持期間で | `notApplicable` |
| 10b | `revertToOriginalPlan()` のあと | `declinedPlanReviewOn == 当日`。戻した直後の `HomeCards` に見直しのカードが出ず、14日後に出る(03-decisions.md #4 の追加) |
| 11 | `dismissEvent(id)` | その出来事だけ消える |
| 12 | 保存と読み込み | 新しい項目を含めて往復で等しい。項目のない JSON は nil で読める(schemaVersion 1) |
| 13 | フェーズ4の形の plan.json(テストのフィクスチャ。新しい項目なし、2026-10-24 開始)をデコード | 読めて、`events == nil`、`originalPhase == nil`、`roadmap.startDay == 2026-10-24`(03-decisions.md #10 の追加) |

## C. アプリ: `DailySummaryBuilder` の遷移の適用

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 減量中で境界以下になった記録 | build 後に `planStore` のフェーズが維持期間、`events` に `stageArrived`、`stages[0].estimatedArrival == 到達日`、`PlanStatus.maintenance == .inProgress(…)` |
| 2 | 同じ条件で2回 build | 2回目は変化なし(保存しない。`events` が増えない) |
| 3 | 最初の区切り: 起点以降で最初に 117.3 以下の日 | `firstMilestoneReachedOn` がその日、`events` に `firstMilestoneReached` |
| 4 | 最初の区切りとステージ到達が同じ build で起きる | 両方の出来事が古い順に入る |
| 5 | 記録が変わっても(HealthKit の修正)、保存済みの到達日は変わらない | 到達日は保存値を優先 |

## D. アプリ: `HomeCards.cards`

| # | 状態 | 期待 |
| --- | --- | --- |
| 1 | 出来事2件 + 85日目 + 維持の一言 | [event, event, maintenanceMaximum]。一言は出ない |
| 2 | 85日目 + 早期到達 | 85日目だけ |
| 3 | 早期到達 + `declinedEarlyArrivalOn` が13日前 | 出ない。14日前なら出る |
| 4 | 85日目 + `continuedMaintenanceOn` が13日前 / 14日前 | 出ない / 出る |
| 5 | 計画見直し + `declinedPlanReviewOn` 13日前 / 14日前 | 出ない / 出る |
| 6 | 計画見直し + 速すぎるペース | [planReview, tooFast] |
| 7 | 維持の一言(上) | [maintenanceNotice(.aboveBand)] |
| 8 | 85日目で当日の7日平均なし | `maintenanceMaximum(canAdvance: false)` |
| 9 | 減量中で何もない | 空 |

## E. アプリ: `HomeModel` の操作(モック経由)

| # | 操作 | 期待 |
| --- | --- | --- |
| 1 | 85日目で `advanceAfterMaximum()` | 保存されたフェーズがステージ2、`summary.plan.stageNumber == 2`、カードが消える |
| 2 | `continueMaintenance()` | カードが消え、14日後に再び出る(day を進めた build で確認) |
| 3 | `adoptPlanReview()` → `revertToOriginalPlan()` | 起点と予定日が元に戻る |
| 4 | `dismissEvent` | 出来事が消える |
| 5 | 条件外で操作 | `notApplicable` を投げ、保存は変わらない |

## F. アプリ: `RoadmapRows.make`

| # | 状態 | 期待 |
| --- | --- | --- |
| 1 | ステージ1の減量中 | 6ステージ + 5維持期間 + 最終目標。ステージ1が「いまここ」、以降は「到達予定」、最初の区切りの行がステージ1の中 |
| 2 | ステージ1の維持期間(到達 3/23) | ステージ1「到達 2027年3月23日」、維持期間「いまここ(到達から n日目)」 |
| 3 | ステージ3の減量中 | 1・2 は到達済み、維持期間1・2 は終了日つき、3 が「いまここ」 |
| 4 | 維持モード | すべて到達済み、最終目標に到達日 |
| 5 | 見直し採用後 | 「元の計画に戻す」の行が出て、変更前→後の予定日 |
| 6 | ペースの判定 | 月2% を週に換算して `SafetyJudgment.comfortable` の言葉 |

## G. `#Preview`

| 画面 | 状態 |
| --- | --- |
| `EventCard` | 最初の区切り / ステージ到達 / 卒業 / 最終目標 |
| `ProposalCard` | 85日目(選べる) / 85日目(今日の記録なし) / 早期到達 / 計画見直し |
| `NoticeCard` | 速すぎるペース / 維持の一言(上) / (下) |
| `HomeView` | 出来事1件 + 提案1件 / 一言だけ / カードなし |
| `RoadmapView` | ステージ1減量中 / 維持期間 / ステージ3 / 維持モード / 見直し採用後 |
