# フェーズ2: WeightCore のドメインロジック 計画

作成日: 2026-10-24
状態: **承認待ち**(コードは未着手)
ブランチ: `feature/phase2-core-logic`

AGENTS.md の「ドメインルール」を、WeightCore にテスト駆動で実装する計画。
UI、HealthKit、永続化は扱わない。すべて `swift test` だけで確かめられる純粋なロジックにする。

| ファイル | 内容 | 回答欄 |
| --- | --- | --- |
| [01-design.md](01-design.md) | 型の設計案と各ロジックの定義(式、丸め、日付の扱い) | なし |
| [02-test-cases.md](02-test-cases.md) | テストケースの一覧(境界値を含む) | なし |
| [03-decisions.md](03-decisions.md) | 決めていただきたいこと。「最初の1か月」の案3つを含む | **あり** |

## 対象(kickoff-prompts.md の 2 より)

| # | 対象 | 実装する型 |
| --- | --- | --- |
| 1 | 1日の体重の決定(最初の測定値、HealthPlanet 優先) | `DailyWeightResolver` |
| 2 | 7日平均 | `SevenDayAverage` |
| 3 | ロードマップの生成(ステージ、最初の5%、維持期間、到達予定日) | `Roadmap` |
| 4 | 安全性の判定(週あたりの減量率) | `SafetyJudgment` |
| 5 | 進み具合の判定(目安との比較、±0.5%) | `Guideline`、`ProgressJudgment` |
| 6 | 維持期間の卒業判定 | `MaintenanceJudgment` |
| 7 | 計画見直しの発動判定 | `PlanReviewTrigger` |
| 8 | 実績ペースの判定(月3%超)※ AGENTS.md の「実績ペース」「前倒しの扱い」から追加 | `ActualPace` |
| 9 | 最初の1か月の扱い(03-decisions.md の回答後) | 案により異なる |

## 対象外(後のフェーズ)

- HealthKit からの読み取り、HKSource の Bundle ID 判定(フェーズ3)
- 画面、カード、レポートの文言(フェーズ4 以降)
- 計画の保存と「元の計画に戻す」(永続化のフェーズ。`Roadmap` を `Codable` な値型にして備える)
- 期日指定モード(優先度4)

## 実装の順番

依存の少ないものから。各ステップで「テストを書く → 失敗を確認 → 実装 → 通す → コミット」を繰り返す。

1. `CalendarDay`(日付の境界を扱う土台)
2. `DailyWeightResolver`
3. `SevenDayAverage`
4. `Ratio`(割合の丸め。以降の判定すべてが使う)
5. `Guideline` と `ProgressJudgment`
6. `SafetyJudgment`
7. `Roadmap`(ステージ境界、マイルストーン、到達予定日)
8. `ActualPace`
9. `MaintenanceJudgment`
10. `PlanReviewTrigger`
11. 最初の1か月の扱い(回答後)
12. Codex へレビュー依頼(境界値と日付処理を重点に)

## 確認方法

```sh
cd WeightCore && swift test
xcodegen generate
xcodebuild -project WeightApp.xcodeproj -scheme WeightApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

アプリ側のコードは変えないので、`xcodebuild test` は「WeightCore を組み込んだままビルドとテストが通る」ことの確認。

## 承認の手順

1. `03-decisions.md` の各項目に回答する(推奨どおりなら「推奨どおり」)。
2. 01 と 02 に異論があれば書き添える。
3. チャットで承認を伝える。
