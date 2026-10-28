# フェーズ4: 画面(前半) 計画

作成日: 2026-10-28
状態: **承認待ち**(コードは未着手)
ブランチ: `feature/phase4-screens`

フェーズ3までで、WeightCore の判定とデータ層(HealthKit 読み取り、計画の保存、`DailySummary`)ができている。
このフェーズでは、それを使って「初回設定」と「ホーム画面」を `docs/design/concept_design.pdf` の1枚目どおりに作り、
毎日の画面に出す文言を確定する。カード(計画見直し、85日目、早期到達、維持中の一言)、ロードマップ画面、レポートは作らない。

| ファイル | 内容 | 回答欄 |
| --- | --- | --- |
| [01-design.md](01-design.md) | 画面の構成、状態ごとの表示、型と責務(WeightCore の追補、`DailySummary` の拡張、画面) | なし |
| [02-test-cases.md](02-test-cases.md) | テストケースと `#Preview` の一覧 | なし |
| [03-decisions.md](03-decisions.md) | 決めていただきたいこと | **あり** |
| [04-wording.md](04-wording.md) | 画面に出す文言の一覧(確定用) | **あり**(直したい文言があれば書き換える) |

## 対象

### A. WeightCore の追補(画面のために要る純粋なロジック)

| # | 内容 | 実装する型 |
| --- | --- | --- |
| A1 | 最終目標の初期値: 身長と BMI から標準体重を求める | `PlanSetup.defaultTargetWeight(heightCentimeters:settings:)` |
| A2 | 初回設定の入力の検証(開始体重 > 最終目標、どちらも正の値) | `PlanSetup.validate(startWeight:targetWeight:)` |
| A3 | 最初の区切り(5%)の到達判定と到達予定日(ステージ1の減量中だけ) | `Roadmap.hasReachedFirstMilestone(sevenDayAverage:)`、`Roadmap.firstMilestoneEstimatedArrival(from:)` |
| A4 | 7日平均の日ごとの系列(グラフ用)。各日について `SevenDayAverage(endingOn:)` を並べる | `SevenDayAverage.series(from:to:in:)` |

### B. アプリ本体

| # | 内容 | 実装する型 |
| --- | --- | --- |
| B1 | `DailySummary` に履歴(日ごとの体重の有無、7日平均、計画値)を足す。グラフと記録カレンダーが使う | `DailySummary.history`、`DailyPoint` |
| B2 | `HomeModel` に「読み込み前」「計画なし(初回設定が要る)」の状態と、計画の作成・保存を足す | `HomeModel.hasRefreshed`、`HomeModel.suggestedStartWeight`、`HomeModel.startPlan(startWeight:targetWeight:)` |
| B3 | 最初の区切りに到達した日の保存(到達したら戻らない) | `PlanRecord.firstMilestoneReachedOn`(03-decisions.md #3) |
| B4 | 画面の振り分け: ヘルスケアが使えない / 読み込み中 / 初回設定 / ホーム | `RootView` |
| B5 | 初回設定画面: 開始体重(初期値は直近7日平均か最新値)、身長(初期値 175cm)、最終目標(初期値 BMI22)、計画の要約、「この計画で始める」 | `SetupView` |
| B6 | ホーム画面: 日付と見出し、7日平均カード(大きな数値、当日の測定、グラフ、点線の計画)、ステージカード(今のステージ、めざす体重、進み具合のバー、到達予定、進み具合の一言)、今週の記録カード | `HomeView`、`WeightCard`、`WeightChart`、`StageCard`、`WeekRecordCard` |
| B7 | 表示用の整形(日付「10月18日(日)」、時刻「17:47」、到達予定「2027年1月上旬」、体重「123.5 kg」) | `DisplayFormat` |
| B8 | 色と見た目の定義(アクセントの緑、背景、カード)。赤・警告色は定義しない | `AppTheme` |
| B9 | タブ(ホーム / ロードマップ / レポート)の骨組み。ロードマップとレポートは中身をまだ作らない(03-decisions.md #5) | `RootView` |

### 対象外(後のフェーズ)

- フェーズの自動遷移(ステージ到達で維持期間へ、28日で卒業して次のステージへ)、カードと選択の保存(計画見直し、85日目、早期到達、維持中の一言、速すぎるペース)→ **フェーズ5**。
  このフェーズのホーム画面は「保存されているフェーズをそのまま表示する」までで、フェーズを変える処理は入れない。
- ロードマップ画面の中身 → フェーズ5。レポート画面と「次のレポート」の行 → フェーズ6。
- ウィジェット、バックグラウンド受信 → フェーズ7。測る時間帯の案内、期日指定モード → フェーズ8。
- 計画の作り直し(初回設定のやり直し)。必要になったら設定画面と一緒に考える。

## 実装の順番

1. A1〜A4(WeightCore。テスト → 実装 → `swift test`)
2. B7 `DisplayFormat`、B8 `AppTheme`(純粋な整形。テストできる)
3. B1 `DailySummary.history`、B3 `PlanRecord.firstMilestoneReachedOn`(データ層。モックでテスト)
4. B2 `HomeModel` の状態と `startPlan`(モックでテスト)
5. B5 `SetupView` と `#Preview`
6. B6 ホーム画面の各カードと `#Preview`(状態ごと)
7. B4・B9 `RootView` とタブ、`WeightApp` から差し替え
8. `swift test`、`xcodegen generate`、`xcodebuild test`、シミュレーターで初回設定 → ホームの流れを確認
9. Codex へレビュー依頼(コンセプト上の制約: 数値は体重だけ、評価ラベルなし、赤なし、最終目標はホームに出ない。日付の整形と週の境界、初回設定の検証)
10. 実機で見た目と文言を確認してもらい、直す

コミットは A、B7+B8、B1+B3、B2、B5、B6、B4+B9 の7つ程度に分ける。

## 確認方法

```sh
cd WeightCore && swift test && cd ..
xcodegen generate
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

- シミュレーターでは、ヘルスケア app に体重を手入力して初回設定の初期値とホームの表示を確認する。
- `#Preview` は状態ごとに分け(データなし / 最初の1か月 / 計画どおり / 最初の区切り到達後 / 維持期間 / 維持モード / 読み取り失敗)、見た目がコンセプト上の制約に反していないかを確認する。

### 実機でしか確認できないこと

- 初回設定で、HealthPlanet 由来の直近7日平均が初期値に出ること
- 文字の大きさと色の見え方(ダークモードは 03-decisions.md #8)

## 承認の手順

1. `03-decisions.md` の各項目に回答する(推奨どおりなら「推奨どおり」)。
2. `04-wording.md` の文言で直したいものがあれば書き換える(そのまま使うなら「このままでよい」)。
3. 01 と 02 に異論があれば書き添える。
4. チャットで承認を伝える。
