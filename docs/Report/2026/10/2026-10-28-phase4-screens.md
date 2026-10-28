# 作業日報 2026-10-28 フェーズ4: 画面(前半)

担当: Claude Code(実装)、Codex(レビュー)、人間(判断・承認)
ブランチ: `feature/phase4-screens`(push 済み。main へのマージは実機確認後の承認待ち)
前の作業: [2026-10-24-phase3-data-layer.md](2026-10-24-phase3-data-layer.md)

## 今日やったこと(時系列)

| 作業 | コミット |
| --- | --- |
| フェーズ4の計画(README、設計、テスト項目、決定事項10件、文言一覧)を提出 | a30f0bf |
| 決定事項の回答(すべて推奨どおり)と文言の修正3か所を記録。設計書の名前の統一、concept.md の但し書き | 0853048 |
| WeightCore: `PlanSetup`、最初の区切りの判定と予定日、`SevenDayAverage.series`(TDD、139件) | e28ebb1 |
| `DisplayFormat`、`AppTheme`、`HomeSettings` | 92dfb97 |
| `DailySummary.history`(`DailyPoint`)、`PlanRecord.firstMilestoneReachedOn` | 87d41d3 |
| `HomeModel` の初回設定と最初の区切りの保存、`SetupFormState`、`RootRoute` | c7023f5 |
| 画面: `RootView`(振り分けとタブ)、`SetupView`、`HomeView` と各カード、`UnavailableView`、`PreviewData` | 4d1f537 |
| Codex レビュー1回目 → 指摘5件(高1・中3・低1)を修正 | 7b1ba56 |
| Codex レビュー2回目 → 指摘1件(中)を修正 | 379a05d |
| Codex レビュー3回目 → 指摘1件(中)を修正 | aa5131a |
| Codex レビュー4回目 → 指摘なし、マージ可 | |

## 決めたこと(03-decisions.md)

- 進み具合の一言をホームに出す(言葉で伝える)。履歴は直近28日。
- 最初の区切り(5%)の到達日を `PlanRecord` に保存し、以後は戻らない。
- 最終ステージでは「次の区切り」として最終目標の値を出す(concept.md に但し書きを追加)。
- タブの骨組み(ホーム / ロードマップ / レポート)を入れ、未実装の2つは1行の仮の画面。「次のレポート」の行は出さない。
- 身長は初回設定で入力し、最終目標の初期値(BMI 22)の計算にだけ使う。保存しない。
- 背景と文字はシステム色、アクセントの緑だけ固定。ダークモードの調整はフェーズ8。
- 7日平均の日数下限は据え置き。入力は数値のテキスト欄。
- 文言: 「点線の近くにいれば順調です」→「点線は計画のペースです」(離れたときに評価に読めるため)。維持モードは「保っていく時期です」。保存先が取れないときは App Group の確認を案内。

## 作ったもの

```
WeightCore
  PlanSetup                  最終目標の初期値(BMI × 身長²)、入力の検証(有限・正・目標 < 開始)
  Roadmap                    hasReachedFirstMilestone / firstMilestoneEstimatedArrival(ステージ1の減量中だけ)
  SevenDayAverage.series     日ごとの7日平均の系列
WeightApp/App
  HomeSettings               historyDays = 28
  DisplayFormat              日付「10月18日(日)」、時刻、到達予定「2027年1月上旬」、体重
  AppTheme                   アクセントの緑、背景・カードはシステム色。警告色は定義しない
  HomeModel                  hasRefreshed、startWeightSuggestion、startPlan、最初の区切りの保存、
                             refresh の世代番号と最新の取り直しの共有(RefreshOutcome / awaitLatestRefresh)
  SetupFormState             初回設定の入力欄の状態(身長→最終目標の上書き規則、検証)
  RootRoute                  画面の振り分け(利用不可 / 読み込み中 / 失敗 / 初回設定 / ホーム)
WeightApp/Data
  DailySummary               history: [DailyPoint](記録の有無、7日平均、計画値)。PlanStatus に roadmap と到達日
  PlanStore                  PlanRecord.firstMilestoneReachedOn(schemaVersion は 1 のまま)
WeightApp/Views
  RootView                   振り分け、MainTabView、PlaceholderView、UnavailableView
  SetupView                  開始体重・身長・最終目標・要約・ボタン
  HomeView                   見出し、WeightCard(数値・グラフ・凡例)、StageCard(減量中 / 維持期間 / 維持モード)、WeekRecordCard
  WeightChart                Swift Charts。軸・目盛り・数値なし。点線は今のフェーズの起点から
WeightApp/Preview
  PreviewData                MockHealthStore + 一時ディレクトリの PlanStore から状態ごとの HomeModel
```

`ContentView` は廃止。

## 確認結果

| 確認 | 結果 |
| --- | --- |
| `swift test` | 139件通過(20スイート) |
| `xcodebuild test`(iPhone 17 Pro, iOS 26.5) | アプリ71件 + WeightCore 139件通過 |
| シミュレーター起動 | HealthKit の権限ダイアログ(体脂肪率・体重の読み取り、確定文言)まで確認。この環境からはダイアログの先を操作できず、初回設定とホームの見た目は未確認 |
| `#Preview` | Xcode の MCP に未接続のため未取得。状態ごとの Preview(初回設定4、ホーム8、グラフ4、記録カレンダー3、利用不可3)は用意済み |
| Codex レビュー | 1回目 高1・中3・低1 → 修正。2回目 中1 → 修正。3回目 中1 → 修正。4回目 指摘なし、マージ可 |

## Codex の指摘と対応

1. **(高)開始体重に無限大を入れると `Roadmap` の境界計算が終わらない。** `PlanSetup.validate` に有限値の検証を追加。
2. **(中)保存後の取り直しに失敗しても `startPlan` が成功扱いになり、初回設定から上書きできる。** 既存の計画があれば `alreadyStarted`、取り直しに失敗したら `savedButRefreshFailed` を投げ、画面は「計画は保存しました…」と出す。
3. **(中)`refresh()` の二重実行で古い結果が新しい結果を上書きする。** 世代番号を持たせ、最新の要求だけを反映。
4. **(中)進み具合のバーが VoiceOver に割合の数値を読み上げる。** バーは読み上げ対象外にし、グラフも各点の値を公開しない(毎日の画面に出す数値は体重だけ)。
5. **(低)計画値が1点のとき点線が見えない。** 点を打つ。
6. **(中・2回目)`startPlan` の取り直しが別の取り直しに置き換えられると失敗扱いになる。** 最新の取り直しを共有し、`awaitLatestRefresh` で待つ。
7. **(中・3回目)待った Task の完了直後に新しい取り直しが始まると古い結果を返す。** 結果の種類ではなく Task の同一性で判断する。

## つまずいたことと学び

1. **`@MainActor` でも `await` の間は再入する。** 起動時・復帰時・初回設定の3か所から `refresh()` が呼ばれるので、世代番号と「最新の Task の共有」が要った。順序の競合は Codex が3回にわたって一段ずつ深く指摘した。並行処理は「最新を待つ」「同一性で判断する」まで詰めてから出す。
2. **アクセシビリティも「見せすぎない」の対象。** 画面に数値を出していなくても、`accessibilityValue` や Swift Charts の既定の読み上げで数値が出る。コンセプト上の制約は VoiceOver も含めて確認する。
3. **`Double("inf")` が通る。** 入力の検証は「正の数」だけでなく「有限」も見る。
4. **シミュレーターの GUI はこの環境から操作できない。** `xcrun simctl` で起動とスクリーンショットはできるが、権限ダイアログのタップや Health への入力はできない。見た目の確認は Xcode の Preview か実機に頼る。
5. **Preview の取得には Xcode の MCP が要る。** 未接続だったので、Preview は用意だけして人間の確認に回した。

## 新しく足した文言

04-wording.md で確定した文言に加えて、実装中に次を足した(04-wording.md の末尾にも記載)。

| 場面 | 文言 |
| --- | --- |
| 初回設定: 検証(0 以下) | 0 より大きい値にしてください |
| 初回設定: 要約(最初の区切りが出せないとき) | 開始日は今日({日付})。 |
| 初回設定: 保存はできたが取り直しに失敗 / すでに保存済み | 計画は保存しました。ヘルスケアから体重を読み取れなかったので、もう一度開いてみてください。 |
| VoiceOver: グラフ | 直近{n}日の7日平均と計画のグラフ |
| VoiceOver: 記録カレンダー | {日}日 記録あり |

## 残っていること(人間の確認)

- Xcode で `#Preview` を状態ごとに見る: 数値は体重だけか、評価ラベル・赤色がないか、最終目標が最終ステージ以外に出ていないか、文言の印象。
- 実機: 初回設定で HealthPlanet 由来の直近7日平均が初期値に入ること。「この計画で始める」でホームに切り替わり、翌日以降に開いても計画が残ること。文字の大きさ、ダークモードの見え方(調整はフェーズ8)。
- 確認後に main へマージ。

## 次にやること

フェーズ5(画面・後半): フェーズの自動遷移(ステージ到達で維持期間へ、28日で卒業して次のステージへ)、カード(最初の1か月、最初の区切りの到達、計画見直しと「元の計画に戻す」、85日目、早期到達、維持中の一言、速すぎるペース)と選択の保存、ロードマップ画面。
