# 設計案: 遷移、保存、カード、ロードマップ

## 1. フェーズの自動遷移(`PhaseProgression`、WeightCore)

```swift
public enum PhaseTransition: Sendable, Equatable {
    /// 減量中にステージの区切りに届いた(次は維持期間、最終ステージなら維持モード)。
    case arrived(stage: Int, on: CalendarDay, sevenDayAverage: Double)
    /// 維持期間を卒業して次のステージの減量中へ。
    case graduated(fromStage: Int, on: CalendarDay, sevenDayAverage: Double)
}

public enum PhaseProgression {
    /// `phase` から `day` までに起きる遷移を順に適用し、最後のフェーズと遷移の列を返す。遷移がなければ空。
    /// 連鎖は最大 stages.count 回まで(それ以上は異常なので止める)。
    public static func advance(phase: PlanPhase, roadmap: Roadmap, weights: [DailyWeight], through day: CalendarDay, settings: PlanSettings)
        -> (phase: PlanPhase, transitions: [PhaseTransition])
}
```

規則:

- **到達の検出(減量中)**: 起点の日から `day` まで1日ずつ、7日平均(丸め)が `stages[k-1].boundaryWeight` 以下になった**最初の日**を到達日にする。到達時体重はその日の7日平均(丸め)。
  アプリを数日開かなくても、到達日は実際に下回った日になる(維持期間の28日はそこから数える)。
  起点の日そのものも対象(見直しで起点を取り直した日に既に下回っていた場合)。
- **卒業(維持期間)**: `MaintenanceJudgment.evaluate` が `.graduated(on: g)` なら、`Roadmap.phaseOnAdvance(from:sevenDayAverage: g の7日平均, on: g)`。
- **維持モード**: 遷移なし。
- 遷移のあと、新しいフェーズで同じ判定を `day` まで続ける(卒業した日の7日平均が既に次の境界以下なら、その日に到達になる)。
- 判定は WeightCore の既存関数を呼ぶだけで、丸めの規則はそれらに従う。

## 2. 保存する項目(`PlanRecord`)

```swift
struct PlanRecord {
    …既存(roadmap, phase, originalRoadmap, declinedEarlyArrivalOn, firstMilestoneReachedOn)…
    /// 見直しを採用したときの、採用前のフェーズ(「元の計画に戻す」用)。originalRoadmap と対で持つ
    var originalPhase: PlanPhase?
    /// 見直しの提案を断った日。14日後に再提案
    var declinedPlanReviewOn: CalendarDay?
    /// 85日目のカードで「維持を続ける」を選んだ日。14日後に再提案(03-decisions.md #3)
    var continuedMaintenanceOn: CalendarDay?
    /// まだ閉じていない出来事(古い順)
    var events: [PlanEvent]?
}

struct PlanEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        case firstMilestoneReached(weight: Double)
        case stageArrived(stage: Int, weight: Double)             // 維持期間へ
        case graduated(toStage: Int, startWeight: Double, boundary: Double)
        case targetReached(weight: Double)                        // 維持モードへ
    }
    var id: UUID
    var kind: Kind
    var day: CalendarDay
}
```

- 項目はすべて省略可能にして `schemaVersion` は 1 のまま(03-decisions.md #10)。
- `events` は閉じたら消す(履歴は残さない。レポートのフェーズで必要になれば別に持つ)。

### ユーザーの選択(`PlanRecord` の純粋な操作。`PlanRecord+Actions.swift`)

| 操作 | 条件 | 変更 |
| --- | --- | --- |
| `advanceAfterMaximum(sevenDayAverage:on:)` | 維持期間で `exceededMaximum`、当日の7日平均あり | `phaseOnAdvance` → `rescheduled`。`continuedMaintenanceOn = nil`。出来事 `graduated` を足す |
| `continueMaintenance(on:)` | 同上 | `continuedMaintenanceOn = day` |
| `adoptEarlyArrival(sevenDayAverage:on:)` | 維持期間で早期到達 | `phaseOnEarlyArrival` → `rescheduled`。`declinedEarlyArrivalOn = nil`。出来事 `stageArrived`(次が最終なら `targetReached`) |
| `declineEarlyArrival(on:)` | 同上 | `declinedEarlyArrivalOn = day`(既存) |
| `adoptPlanReview(sevenDayAverage:on:)` | 減量中で見直しの提案 | `originalRoadmap/originalPhase` が nil なら今の値を保存。`phase = phase.rebased(…)`、`roadmap = roadmap.rescheduled(from: phase)`。`declinedPlanReviewOn = nil` |
| `declinePlanReview(on:)` | 同上 | `declinedPlanReviewOn = day` |
| `revertToOriginalPlan()` | `originalRoadmap` があり、今のフェーズが採用時と同じステージの減量中 | `roadmap = originalRoadmap`、`phase = originalPhase`、両方 nil に |
| `dismissEvent(id:)` | | `events` から外す |

- 採用・前進のあとは `DailySummaryBuilder` が次の取り直しで遷移を再判定する(例: 見直し採用後に既に境界以下なら到達)。

## 3. `DailySummaryBuilder` の流れ(A5)

```
load record
→ weights を取得・日次化
→ record があれば:
    PhaseProgression.advance(…through: day) で phase と transitions
    transitions ごとに roadmap = roadmap.rescheduled(from: 新 phase)、events に追加
    最初の区切り: ステージ1の減量中で未到達、起点以降で最初に7日平均(丸め)≤ firstMilestoneWeight の日 → firstMilestoneReachedOn、events に追加
    変わっていれば planStore.save
→ 判定(既存の planStatus)
```

- 取得範囲は「開始日の6日前から」のままで足りる(起点以降をすべて見られる)。
- `HomeModel.recordFirstMilestoneIfReached` と再 build は削除する。
- `PlanStatus` に `events: [PlanEvent]`、`declinedPlanReviewOn`、`continuedMaintenanceOn`、`originalRoadmap` の有無、見直し採用後の到達予定(変更前/後)を足す。

## 4. カードの選別と優先順位(`HomeCards`、純粋)

```swift
enum HomeCard: Equatable, Identifiable {
    case event(PlanEvent)
    case maintenanceMaximum(canAdvance: Bool)                       // B5
    case earlyArrival(nextStage: Int, boundary: Double)            // B6
    case planReview(before: CalendarDay, after: CalendarDay, stage: Int)   // B7
    case tooFast                                                   // B8
    case maintenanceNotice(MaintenanceNotice)                      // B9
}
enum HomeCards {
    static func cards(for plan: PlanStatus, on day: CalendarDay, settings: PlanSettings) -> [HomeCard]
}
```

出す順(上から):

1. 出来事(古い順。閉じるまで残る。03-decisions.md #5)
2. 提案は**1枚だけ**: 85日目 > 早期到達 > 計画見直し
   - 85日目: `maintenance == .exceededMaximum` かつ(`continuedMaintenanceOn` が nil、または 14日以上前)
   - 早期到達: `shouldProposeEarlyArrival` かつ 85日目のカードが出ていない
   - 計画見直し: `shouldProposePlanReview` かつ(`declinedPlanReviewOn` が nil、または 14日以上前)
3. 一言: 速すぎるペース(`actualPace.isTooFast`)、維持の一言(85日目のカードが出ていれば出さない。AGENTS.md)

- `canAdvance`: 当日の7日平均があるとき。なければボタンを無効にして「今日の記録が入ってから選べます」(03-decisions.md #9)。
- 計画見直しの before/after: before = 今の `stages[k-1].estimatedArrival`、after = `roadmap.rescheduled(from: phase.rebased(今日の7日平均, 今日))` の同じステージの予定日。当日の7日平均がなければ提案しない(`PlanReviewTrigger` が当日の平均を要求するので自然に満たす)。

## 5. カードの View

- `EventCard`: 見出し(大)、一言、「閉じる」。色はアクセントのみ。
- `ProposalCard`: 見出し、説明(変更前→後の予定日など)、ボタン2つ(主: アクセント塗り、副: 枠だけ)。
- `NoticeCard`: 文言だけ。
- `HomeView` の `cards` の場所に `ForEach` で差し込む。操作は `HomeModel` のメソッドを呼び、終わったら `refresh()`。

### `HomeModel` の操作

```swift
func advanceAfterMaximum() async throws
func continueMaintenance() async throws
func adoptEarlyArrival() async throws
func declineEarlyArrival() async throws
func adoptPlanReview() async throws
func declinePlanReview() async throws
func revertToOriginalPlan() async throws
func dismissEvent(_ id: PlanEvent.ID) async throws
```

共通: `planStore.load()` → 対応する `PlanRecord` の操作 → `save` → `refresh()`。条件を満たさなければ `PlanActionError.notApplicable` を投げる(カードが古い状態で押された場合)。

## 6. ロードマップ画面(`RoadmapView`)

```
ロードマップ

計画のペース
  標準のペースは月2%。1週間あたりでは無理のない範囲です。      ← SafetyJudgment.judge(週換算) の言葉

ステージ1   123.1 → 110.8 kg          到達予定 2027年3月下旬 / 到達 2027年3月20日
  最初の区切り 117.0 kg   届いた 2026年12月…  ← 到達済みなら日付
  いまここ                                  ← 保存したフェーズがこのステージの減量中
維持期間                      卒業 2027年4月…  / いまここ(到達から n日目)
ステージ2   110.8 → 99.7 kg           到達予定 2027年8月中旬
…
最終目標   67.4 kg                    到達予定 2029年…

[元の計画に戻す]                       ← originalRoadmap があるときだけ
  見直し前の計画に戻します(到達予定 2028年… → 2027年…)
```

- 行の状態: 到達済み(`stage < 今のステージ`、または維持期間・維持モードで `stage <= 今のステージ`)は「到達 {年月日}」(`estimatedArrival` は到達後に実際の日に置き換わっている)、今のステージは「いまここ」、これからは「到達予定 {年月旬}」。
- 維持期間の行は各ステージ(最終を除く)の後に置く。到達済みの維持期間は「終了 {年月日}」(次のステージの起点の日。保存しているのは今の減量ステージの起点だけなので、日付が出るのは1つ前の維持期間だけ。それより前は「終了」のみ。実装時の割り切り、2026-10-29)、今の維持期間は「いまここ(到達から n日目)」、未来は「約2か月」(`assumedMaintenanceDays`)。
- 最終目標はここにだけ出す(コンセプト)。評価ラベルは出さない。
- `RoadmapRows.make(plan:on:)` を純粋関数にしてテストする。

## 7. フェーズ4からの変更点

- `HomeModel.recordFirstMilestoneIfReached` を `DailySummaryBuilder` へ移す(遷移と同じ場所で、同じ「起点以降で最初の日」の規則にする)。フェーズ4では「当日の7日平均」で判定していたが、過去にさかのぼる規則に揃える。
- `RootView` のロードマップの仮の画面を `RoadmapView` に差し替える。
