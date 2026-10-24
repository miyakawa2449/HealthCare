# フェーズ3: データ層(HealthKit 連携と永続化)+ WeightCore の追補 計画

作成日: 2026-10-24
状態: **完了**(2026-10-24 に main へマージ)
ブランチ: `feature/phase3-data-layer`

フェーズ2の回答(2026-10-24)で決まった追加仕様(実績ペースの最低窓、維持中の一言、維持中の早期到達)を WeightCore に入れ、
そのうえでアプリ本体の「データ層」を作る。画面は作らない(フェーズ4)。

| ファイル | 内容 | 回答欄 |
| --- | --- | --- |
| [01-design.md](01-design.md) | 型と責務の設計案(WeightCore 追補、HealthKit、永続化、集約) | なし |
| [02-test-cases.md](02-test-cases.md) | テストケースの一覧(境界値を含む) | なし |
| [03-decisions.md](03-decisions.md) | 決めていただきたいこと | **あり** |

## 対象

### A. WeightCore の追補(フェーズ2の回答より)

| # | 内容 | 実装する型 |
| --- | --- | --- |
| A1 | 実績ペースの窓に最低14日を設け、未満なら nil | `ActualPace`、`PlanSettings.actualPaceMinimumWindowDays` |
| A2 | 維持中の一言: 範囲外が14日続いたら(上/下)、7日平均なしでリセット、維持期間と維持モード両方、85日目のカード優先 | `MaintenanceNotice`、`PlanSettings.maintenanceNoticeDays` |
| A3 | 維持中の早期到達: 7日平均(丸め)が次の境界以下になった日に選択肢を出す。採用で次の維持期間へ(次が最終なら維持モード)、`rescheduled` で予定日更新 | `Roadmap.earlyArrival(...)`、`Roadmap.phaseOnEarlyArrival(...)` |
| A4 | 体脂肪率の1日の値(体重と同じ規則: HealthPlanet 優先、その中で最初) | `DailySampleResolver`(体重のリゾルバを汎用化) |
| A5 | 初回設定の開始体重の初期値(直近7日平均、7日分なければ最新値) | `InitialWeightSuggestion` |

### B. アプリ本体のデータ層

| # | 内容 | 実装する型 |
| --- | --- | --- |
| B1 | HealthKit をプロトコルの背後に置く。体重と体脂肪率の読み取り権限の要求、期間指定の取得 | `HealthStore`(protocol)、`HealthKitStore`、`MockHealthStore` |
| B2 | HKSample → WeightCore の値型への変換。HKSource の Bundle ID → `SampleSource` | `HealthSampleMapper`、`DataSourceSettings.healthPlanetBundleIDs` |
| B3 | ロードマップ・フェーズ・元の計画の保存(JSON) | `PlanStore`、`PlanRecord` |
| B4 | 取得 → 1日の値 → 7日平均 → フェーズ判定 をまとめ、画面が使う値を1つの型で返す | `DailySummaryBuilder`、`DailySummary` |
| B5 | HealthKit の更新の検知: フォアグラウンド復帰時の再取得だけ(バックグラウンド受信はウィジェットのフェーズ。03-decisions.md #4) | `WeightApp` の scenePhase |
| B6 | カレンダーの固定(Asia/Tokyo) | `AppCalendar` |

### 対象外(後のフェーズ)

- 画面(ホーム、ロードマップ、レポート)、カードと文言、初回設定の UI(フェーズ4)
- レポート(月半ば/月末)の集計(フェーズ5)
- ウィジェット
- 期日指定モード

## 実装の順番

1. A1〜A5(WeightCore。テスト → 実装 → `swift test`)
2. B6 `AppCalendar`、B2 `HealthSampleMapper`(純粋な変換。モックなしでテストできる)
3. B1 `HealthStore` プロトコルと `MockHealthStore`、`HealthKitStore`(実機でしか動かない部分は薄く)
4. B3 `PlanStore`
5. B4 `DailySummaryBuilder`(モックで結合テスト)
6. B5 観測の登録
7. ContentView に 7日平均と当日の体重だけを出す(03-decisions.md #5。実機での読み取り確認のため)
8. `swift test`、`xcodegen generate`、`xcodebuild test`、シミュレーターで起動
9. Codex へレビュー依頼(境界値、日付、HealthKit の権限とソース判定、永続化の互換性を重点に)

コミットは A、B2+B6、B1、B3、B4+B5、ContentView の6つ程度に分ける。

## 確認方法

```sh
cd WeightCore && swift test && cd ..
xcodegen generate
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

シミュレーターの HealthKit には手入力でデータを入れられる(ヘルスケア app)。HealthPlanet 由来の判定は実機でしか確認できない。

### 実機でしか確認できないこと

- HealthKit の権限ダイアログに確定文言が出ること、許可後に体重と体脂肪率が読めること
- HealthPlanet が書き込むサンプルの `HKSource.bundleIdentifier`: 2026-10-24 に実機で `jp.co.tanita-thl.HealthPlanet` と確認し、`DataSourceSettings` に設定済み

## 承認の手順

1. `03-decisions.md` の各項目に回答する。
2. 01 と 02 に異論があれば書き添える。
3. チャットで承認を伝える。
