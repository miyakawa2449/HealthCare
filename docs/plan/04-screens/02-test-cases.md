# テストケースと Preview の一覧

数値はテストの中で `Roadmap` と `Guideline` から計算して期待値にする(デザインの数値は使わない)。
固定のカレンダーは `AppCalendar.tokyo`。

## A. WeightCore(`swift test`)

### A1. `PlanSetup.defaultTargetWeight`

| # | 入力 | 期待 |
| --- | --- | --- |
| 1 | 175cm、BMI 22 | 67.375(丸めない)。`Roadmap` に入れると `targetWeight == 67.4` |
| 2 | 160cm、BMI 22 | 56.32 |
| 3 | 設定の `defaultTargetBMI` を変えると追従する | 175cm、BMI 25 → 76.5625 |

### A2. `PlanSetup.validate`

| # | 入力 | 期待 |
| --- | --- | --- |
| 1 | 123.5 / 67.4 | nil(有効) |
| 2 | 0 / 67.4 | `.startWeightNotPositive` |
| 3 | 123.5 / 0 | `.targetWeightNotPositive` |
| 4 | 67.4 / 67.4(等しい) | `.targetNotBelowStart` |
| 5 | 67.3 / 67.4 | `.targetNotBelowStart` |
| 6 | 67.5 / 67.4(0.1 差) | nil |

### A3. `Roadmap` の最初の区切り

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 123.5 開始。`firstMilestoneWeight` | 117.3(既存テストで確認済み。前提として使う) |
| 2 | `hasReachedFirstMilestone(117.3)` | true(境界は下の区分) |
| 3 | `hasReachedFirstMilestone(117.34)` | true(丸めて 117.3) |
| 4 | `hasReachedFirstMilestone(117.35)` | false(丸めて 117.4) |
| 5 | `firstMilestoneEstimatedArrival(from: initialPhase)` | 開始日 + `Pace.days(toReach: 117.3 / 123.5, …)` 日。2026-10-18 開始なら 2027-01-03 |
| 6 | 計画見直しで起点を 2026-12-01、120.0 に取り直した `.losing(stage: 1, …)` | 新しい起点から計算し直した日(`Pace.days(toReach: 117.3 / 120.0)`) |
| 7 | 起点の体重が区切り以下(117.0 で起点を取り直した) | 起点の日 |
| 8 | `.losing(stage: 2, …)` / `.maintaining` / `.maintenanceMode` | nil |

### A4. `SevenDayAverage.series`

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 10/1〜10/10 毎日 100.0。`series(from: 10/1, to: 10/10)` | 10件。すべて 100.0、`daysUsed` は 1,2,…,7,7,7,7 |
| 2 | 10/1〜10/3 だけ記録。`series(from: 10/1, to: 10/12)` | 10/1〜10/9 は値あり(窓に入る)、10/10〜10/12 は nil |
| 3 | 記録なし | すべて nil |
| 4 | `from > to` | 空 |
| 5 | 各日の値が `SevenDayAverage(endingOn:in:)` と一致する(無作為の記録で突き合わせ) | 一致 |

## B. アプリ本体(`xcodebuild test`)

### B7. `DisplayFormat`

| # | 入力 | 期待 |
| --- | --- | --- |
| 1 | `dayWithWeekday(2026-10-18)` | "10月18日(日)" |
| 2 | `dayWithWeekday(2026-01-05)` | "1月5日(月)"(0 埋めしない) |
| 3 | `approximateDate` 1日 / 10日 | "上旬" |
| 4 | 11日 / 20日 | "中旬" |
| 5 | 21日 / 31日 | "下旬" |
| 6 | `approximateDate(2027-01-03)` | "2027年1月上旬" |
| 7 | `time` 2026-10-18 17:47 JST(UTC 08:47 の Date) | "17:47"(端末のタイムゾーンによらず Asia/Tokyo) |
| 8 | `kilograms(123.45)` | "123.5 kg"(`Weight.rounded` と同じ丸め) |
| 9 | `fullDate(2029-02-03)` | "2029年2月3日" |

### B1. `DailySummaryBuilder.history`

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 計画なし、直近30日に毎日記録 | `history` は 28件、古い順、最後が `day`。`guideline` はすべて nil。`weight` はすべて非 nil |
| 2 | 計画あり(開始 10/18)、当日 11/30 | 28件。`guideline[i] == Guideline.expectedWeight(phase:on:)`、`sevenDayAverage[i] == SevenDayAverage(endingOn:)?.kilograms` |
| 3 | 計画あり、当日が開始日(10/18)。取得範囲は 10/12〜 | `history` は 10/12〜10/18 の7件(取得範囲より前は作らない) |
| 4 | 維持期間(到達 2027-03-23)、当日 2027-04-10 | 到達日より前の `guideline` は nil、到達日以降は到達時体重で一定 |
| 5 | ステージ1で計画見直しを採用して起点が 12/01、当日 12/10 | 12/01 より前の `guideline` は nil |
| 6 | 記録のない日 | `weight == nil`。7日平均は窓に記録があれば出る |

### B3. `PlanRecord.firstMilestoneReachedOn`

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 既存(項目なし)の JSON を読む | `firstMilestoneReachedOn == nil`、`schemaVersion == 1` |
| 2 | 保存 → 読み込み | 往復で等しい |

### B2. `HomeModel`

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 生成直後 | `hasRefreshed == false`。`refresh()` 後は true(失敗でも true) |
| 2 | 計画なし、直近7日に記録あり | `suggestedStartWeight` が7日平均、`suggestionKind == .sevenDayAverage` |
| 3 | 計画なし、直近7日に記録なし、30日以内に記録あり | 最新の1件、`.latest` |
| 4 | 計画なし、記録なし | nil、`.none` |
| 5 | `startPlan(123.5, 67.4)` | `PlanStore` に `initialPhase`(ステージ1、起点 = 今日の Asia/Tokyo)が保存され、`summary.plan != nil`、`stageNumber == 1` |
| 6 | `startPlan(67.4, 67.4)` | 検証エラーを投げ、保存しない |
| 7 | 減量中ステージ1で7日平均(丸め)が区切り以下になった日に `refresh()` | `firstMilestoneReachedOn == その日` が保存される。翌日に7日平均が区切りを上回っても消えない |
| 8 | ステージ2の減量中で区切り以下 | 保存しない(ステージ1だけ) |
| 9 | `PlanStore.load()` が `unsupportedSchemaVersion` を投げる | `lastRefreshFailed == true`、`summary == nil`(初回設定には進まない) |

### B5. 初回設定の値の流れ(View のロジック部分。`SetupForm` の状態を純粋な型に切り出してテスト)

| # | 条件 | 期待 |
| --- | --- | --- |
| 1 | 身長 175 | 最終目標の初期値 "67.4" |
| 2 | 身長を 170 に変える(最終目標は未編集) | "63.6"(22 × 1.7² = 63.58) |
| 3 | 最終目標を手で "70.0" にしてから身長を変える | "70.0" のまま |
| 4 | 開始体重 "abc" | ボタン無効、文言「数字で入れてください」 |
| 5 | 開始体重 "67.0"、最終目標 "67.4" | ボタン無効、文言「最終目標は開始体重より小さい値にしてください」 |

### B4. `RootView` の振り分け(`HomeModel` の状態から画面の種類を返す純粋な関数 `RootView.route(for:)` をテスト)

| # | 状態 | 期待 |
| --- | --- | --- |
| 1 | `isUnavailable` | `.unavailable` |
| 2 | `!hasRefreshed` | `.loading` |
| 3 | `summary == nil && lastRefreshFailed` | `.failed` |
| 4 | `summary.plan == nil` | `.setup` |
| 5 | `summary.plan != nil` | `.home` |

## C. `#Preview`(状態ごと。データは `MockHealthStore` + 一時ディレクトリの `PlanStore`)

| 画面 | 状態 |
| --- | --- |
| `SetupView` | 7日平均の初期値あり / 最新値の初期値 / 記録なし(空欄) / 検証エラー |
| `HomeView` | 記録なし(7日平均が出ない) / 減量中・最初の1か月 / 減量中・計画どおり / 減量中・最初の区切り到達後(次の区切り) / 減量中・最終ステージ / 維持期間 / 維持モード / 読み取り失敗(前回の値) |
| `WeightChart` | 1点だけ / 28日分 / 途中に欠けあり / 維持期間(水平の点線) |
| `WeekRecordCard` | 週の途中(今日が水曜) / 全日記録 / 記録なし |
| `UnavailableView` | ヘルスケアなし / 読み取り失敗 |
| タブ | ロードマップ / レポートの仮の画面 |

Preview を見るときの確認項目: 数値は体重だけか、評価ラベルがないか、赤がないか、最終目標が(最終ステージ以外で)出ていないか、目安の数値が出ていないか。
