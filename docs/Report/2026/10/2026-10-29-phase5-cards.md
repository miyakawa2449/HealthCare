# 作業日報 2026-10-29 フェーズ5: 画面(後半)— 自動遷移、カード、ロードマップ画面

担当: Claude Code(実装)、Codex(レビュー)、人間(判断・実機確認)
ブランチ: `feature/phase5-cards`
前の作業: [2026-10-29-phase4-screens.md](2026-10-29-phase4-screens.md)

## 今日やったこと(時系列)

| 作業 | コミット |
| --- | --- |
| フェーズ5の計画(README、設計、テスト項目、決定事項、文言)を提出 | 0cc0233 |
| 決定事項の回答を記録(11件すべて推奨どおり + 追加2点: 「元の計画に戻す」で戻した日を断った日にする、フェーズ4形式の plan.json を読む fixture テスト) | fd7dd0f |
| WeightCore: `PhaseProgression`(到達・卒業・連鎖)、`Roadmap.firstMilestoneReachedDay`。`PlanSettings` に項目を足さず再提案の日数は `earlyArrivalRetryDays` を共用 | 295c2c0 |
| アプリ: `PlanRecord` の任意項目(`originalPhase` / `declinedPlanReviewOn` / `continuedMaintenanceOn` / `events`)、`PlanRecord+Actions`、`DailySummaryBuilder.progressed`、`HomeCards`、`HomeModel` の操作。テスト 4ファイル + fixture | 43d6e6d |
| 画面: `HomeCardView`(出来事 / 提案 / 一言)、`RoadmapRows` + `RoadmapView`、タブ差し替え、Preview の状態追加と smoke テスト | e0975d1 |
| Codex レビュー1回目 | (下の「確認結果」) |

## 決めたこと

- 到達日は「起点以降で最初に7日平均(丸め)が境界以下になった日」に遡って決め、保存したら記録が変わっても変えない。最初の区切りも同じ規則(フェーズ4の「当日の値で判定」から変更)。
- 出来事(最初の区切り、到達、卒業、最終目標)は閉じるまで `events` に残す。履歴は持たない。
- 提案のカードは1枚だけ(85日目 > 早期到達 > 計画見直し)。85日目のカードがあるときは維持の一言を出さない。
- 「維持を続ける」「元の計画のままにする」「元の計画に戻す」のあとは14日たってから再提案(早期到達を断ったときと同じ設定値)。
- 終了した維持期間の終了日は、次のステージが今の減量中のときだけ出す(それより前のステージの起点は保存していないため「終了」だけ)。
- `#Preview` の状態が意図どおりか(カードの種類とフェーズ)は smoke テストで確かめる。Xcode の Preview は人間が見る。

## 確認結果

| 確認 | 結果 |
| --- | --- |
| `swift test` | 151件通過 |
| `xcodebuild test`(iPhone 17 Pro, iOS 26.5) | アプリ126件 + WeightCore 151件通過 |
| Codex レビュー | (記入待ち) |
| Xcode の Preview | 未確認(この環境から Preview を取れない。人間が確認) |
| 実機 | 未確認 |

## つまずいたことと学び

1. **派生データが古いと、新しいファイルを足しても「メンバーがない」と出る。** アプリ本体は単体でビルドできるのにテストだけ失敗した。DerivedData を消して解消。
2. **保存される型(`PlanSettings`、`Stage`)に項目を足すと既存の plan.json が読めなくなる。** 再提案の日数は既存の設定値を共用し、維持期間の終了日は保存している範囲で出すことにした。
3. **Preview のデータは「意図した状態」になっているかをテストで確かめる価値がある。** 85日目のつもりで作ったデータが範囲内に28日収まって卒業していた。

## 新しく足した文言

カードとロードマップの文言は `docs/plan/05-cards/04-wording.md` の案のまま。案にない追加は同ファイルの「実装で足した文言」に一覧。

## 残っていること

- Codex レビューの指摘の対応(下に追記)。
- 人間の確認: Xcode の `#Preview`(`HomeCardViews.swift` 11件、`HomeView.swift` の「出来事1件 + 提案1件」「一言だけ」、`RoadmapView.swift` 5件)、実機で既存の計画が読めてロードマップのタブが出ること。

## 次にやること

レビュー対応 → マージ → フェーズ6(レポート)の計画。
