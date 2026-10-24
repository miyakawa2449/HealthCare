# フェーズ3 Codex レビュー結果

実施日: 2026-10-24
対象: `feature/phase3-data-layer`(main からの差分)
実行方法: Claude Code から `codex exec -s read-only`。モデルは gpt-5.6-sol、reasoning effort は medium。

## 1回目(dffb63e 時点)

### Codex の回答(原文)

静的レビュー結果です。提示されたテスト結果は確認済みとして扱いましたが、読み取り専用環境のため、こちらでの再実行は未確認です。

## 指摘

### 1

- 重要度: 高
- 該当ファイルと行: [DailySummary.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:77)
- 問題の内容: 当日の7日平均がない場合に早期 return するため、維持期間の85日目以降でも `MaintenanceJudgment` が実行されません。結果として、出すべき「次のステージへ進む／維持を続ける」カードの判定が `nil` になります。これは「12週間を超えてもカードで提案する」というドメインルールに反します。
- 再現手順または根拠: 到達から85日経過した `.maintaining` フェーズを保存し、直近7日間の体重を空にして `build` します。`SevenDayAverage` が `nil` になり、77行目で戻るため、`MaintenanceJudgment.evaluate` が返すはずの `.exceededMaximum(consecutiveDaysInBand: 0)` を得られません。
- 修正案: 維持状態と `MaintenanceNoticeJudgment` は現在の `average` の有無にかかわらず評価してください。`average` が必要な進み具合・早期到達だけを個別に条件分岐します。直近7日平均なし・到達85日目の `DailySummaryBuilder` テストも追加してください。

### 2

- 重要度: 中
- 該当ファイルと行: [WeightApp.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/WeightApp.swift:9)、[HomeModel.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:24)
- 問題の内容: `HomeModel` はエラー時に「前回の値を残す」としていますが、フォアグラウンド復帰時に `.id(refreshToken)` で `ContentView` と `HomeModel` 自体を作り直しているため、前回値は残りません。さらにエラーを握りつぶすため、画面は理由を示さず「今日の体重」に戻ります。`isUnavailable` も画面から参照されていません。
- 再現手順または根拠: 一度取得成功後、バックグラウンドへ移動し、HealthKit取得エラーまたは壊れた `plan.json` がある状態で復帰します。新しいモデルの `summary` は最初から `nil` で、catch後もそのままです。
- 修正案: モデルの同一性を維持したまま `refresh()` を呼ぶ構成にし、取得失敗状態を保持・表示してください。成功時にはエラー状態を解除します。成功後の再取得失敗で前回値が保持されること、初回失敗時に利用不可状態が出ることをテストしてください。

### 3

- 重要度: 中
- 該当ファイルと行: [PlanStore.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/PlanStore.swift:34)
- 問題の内容: App Group コンテナを取得できない場合に、無通知でApplication Supportへ保存しています。後から署名やApp Group設定が直ると参照先がApp Groupへ切り替わり、退避先に保存した計画が見えなくなります。また、退避先は将来のウィジェットから共有できません。確定仕様はApp Groupへの保存であり、このフォールバックや移行方法は承認済み計画にありません。
- 再現手順または根拠: App Groupが利用できない状態で計画を保存し、その後App Groupを利用可能にして再起動すると、`defaultDirectory()` が別ディレクトリを返し、以前の `plan.json` は読み込まれません。
- 修正案: App Group取得失敗を明示的なエラーとして扱うか、Application SupportからApp Groupへの一度限りの移行を実装・テストしてください。フォールバックを仕様として採用する場合は、人間の承認を得て計画へ追記する必要があります。

### 4

- 重要度: 中
- 該当ファイルと行: [PlanStore.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/PlanStore.swift:45)
- 問題の内容: `schemaVersion` は保存されていますが、ロード時に値を検証していません。同じフィールド構造なら、未知の将来バージョンや不正なバージョンも現在形式として読み込まれます。この状態ではバージョン番号が移行・互換性判定に機能しません。
- 再現手順または根拠: 正常なJSONの `schemaVersion` だけを `999` に変更すると、現在の `load()` はデコードに成功します。
- 修正案: デコード後に `currentSchemaVersion` と比較し、未対応バージョンには専用エラーを投げてください。バージョン0・2・999などを拒否するテストを追加してください。associated value付きenumのCodable往復自体は既存テストの範囲では問題ありません。

### 5

- 重要度: 低
- 該当ファイルと行: [DailySummary.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:41)、[DailySummaryBuilderTests.swift](/Users/tsuyoshi/dev/HealthCare/WeightAppTests/DailySummaryBuilderTests.swift:36)
- 問題の内容: 計画なしの取得範囲が「直近30日」ではなく、当日を含めて31暦日になっています。
- 再現手順または根拠: `day - 30` の0時以上から `day + 1` の0時未満までなので、`day - 30 ... day` の31日を含みます。現在のテストもこの範囲を期待値として固定しています。
- 修正案: 当日を含む30日なら開始を `day - 29` にしてください。「過去30日＋当日」の意図なら、計画文言と定数名を明確化してください。

## 問題なしの観点

- ContentViewの表示数値: 7日平均と当日体重だけで、体脂肪率・評価ラベル・警告色は表示されておらず問題なし。
- 計画ありの取得期間: 開始日の6日前0時から翌日0時までのJST固定で問題なし。
- `.strictStartDate` と `sourceRevision.source.bundleIdentifier`: 使用方法に問題なし。
- MaintenanceNoticeの範囲内・平均なし・上下切替時の数え直し: WeightCore単体の実装は問題なし。
- ActualPaceの最低14日窓とステージ1の最初の1か月: 問題なし。
- HealthKit権限型: 読み取りは体重と体脂肪率の2型だけで、書き込み要求もなく問題なし。
- Swift 6 concurrency: `MockHealthStore`のactor化は妥当です。`HealthKitStore`の`@unchecked Sendable`にも、この差分内で具体的なデータ競合は確認できませんでした。
- HealthPlanet Bundle ID未設定時の `.other` 扱い: 確定仕様どおりです。

総合判断: 高重要度の維持期間判定欠落があるため、現状のままmainへはマージしない判断です。


### 対応

| # | 重要度 | 対応 | 確認 |
| --- | --- | --- | --- |
| 1 | 高 | 採用。維持期間の判定(85日目のカード)と一言は当日の7日平均がなくても評価する。平均が要るのは進み具合と早期到達だけ | 85日目に直近10日データなしで exceededMaximum が出るテストを追加 |
| 2 | 中 | 採用。WeightApp が HomeModel を1つ持ち、起動時と復帰時に refresh。失敗時は前回の値を残し lastRefreshFailed、利用不可は isUnavailable | HomeModel のテスト3件を追加 |
| 3 | 中 | 採用。退避先をやめ、App Group が取れなければ nil → 利用不可。設計書に理由を明記(承認済み仕様の範囲内と Codex も確認) | 利用不可のテスト |
| 4 | 中 | 採用。schemaVersion を読み込み時に検証し、専用エラーを投げる。2回目の指摘を受けて、本体より先にバージョンだけ読む形に変更 | 0/2/999 と、項目構成が違う v2 JSON のテスト |
| 5 | 低 | 採用。計画なしの取得期間を当日を含む30日(day − 29)に | テストと設計書を修正 |

## 2回目(881600e 時点、確認レビュー)

## 指摘

- 重要度: 中
- 該当ファイルと行: [PlanStore.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/PlanStore.swift:47)
- 問題の内容: `PlanRecord` 全体をデコードした後に `schemaVersion` を検証しています。そのため、異なるスキーマで必須フィールドが変更・削除されている場合、`PlanStoreError.unsupportedSchemaVersion` ではなく `DecodingError` が先に発生します。#4 の「バージョンが違えば専用エラー」という趣旨を完全には満たしていません。
- 再現手順または根拠: `{"schemaVersion":2}` のようなJSONを読み込むと、47行目で `roadmap` の欠落により失敗し、49行目へ到達しません。追加されたテストはv1の完全なJSONについて番号だけを書き換えているため、このケースを検出できません。
- 修正案: まず `schemaVersion` だけを持つ小さな `Decodable` 型でバージョンを読み、検証後に `PlanRecord` 全体をデコードしてください。必須フィールドが異なるv2 JSONのテストも追加します。

## 観点別確認

- #1: 問題なし。当日の平均がなくても維持判定と一言が評価され、平均依存の進み具合・早期到達だけが条件分岐されています。
- #2: 問題なし。モデルの同一性、起動・復帰時更新、失敗時の前回値保持、成功時の失敗状態解除を確認しました。
- #3: 問題なし。App Group以外へ保存しないフェイルクローズの判断であり、承認済みの「App Groupに保存」の範囲内です。新しい保存方式や移行経路を追加する設計変更ではありません。
- #4: 上記1件の対応不足があります。
- #5: 問題なし。`day - 29`から翌日未満で、当日を含む30日です。
- 新たな退行: 上記以外は確認できませんでした。`git diff --check`も問題ありません。

総合判断: **#4を修正してからmainへマージ可。現時点ではマージ見送りです。**


対応: schemaVersion を `SchemaHeader` で本体より先に読んで判定するよう変更(611b607)。

## 3回目(611b607 時点、確認レビュー)

問題なし。

`SchemaHeader` による先行判定と、v2 JSON の回帰テストを確認しました。テスト結果は申告内容を前提とし、再実行は未確認です。

総合判断: main へマージしてよいです。


対応後: `xcodebuild test` でアプリ25件 + WeightCore 122件通過。

## 依頼文(1回目)

あなたは AGENTS.md の「Codex(検証担当)」です。AGENTS.md と CLAUDE.md を最初に読み、そのルールに従ってレビューしてください。コードは書き換えず、指摘にとどめてください。

## レビュー対象

ブランチ `feature/phase3-data-layer` の main からの差分(`git diff main...HEAD`)。フェーズ3「データ層」の実装です。
計画は docs/plan/03-data-layer/(README、01-design、02-test-cases、03-decisions)。03-decisions.md の回答が確定仕様です。
AGENTS.md のドメインルール表は今回の回答で更新済み(実績ペースの最低窓、維持中の一言、早期到達、計画値の基準、最初の1か月)。

## 変更の要約と意図

A. WeightCore の追補
- ActualPace: 窓が14日未満なら nil
- MaintenanceNoticeJudgment: 維持中に範囲外(上/下)が14日続いたら一言。範囲内・7日平均なし・上下の入れ替わりで数え直し
- Roadmap.earlyArrival / phaseOnEarlyArrival、EarlyArrivalProposal(断った日から14日後に再提案)
- DailySampleResolver に汎用化、BodyFatSample / DailyBodyFat / DailyBodyFatResolver、InitialWeightSuggestion
- PlanSettings に actualPaceMinimumWindowDays / maintenanceNoticeDays / earlyArrivalRetryDays

B. アプリのデータ層(WeightApp/Data/)
- AppCalendar(Asia/Tokyo 固定)、HealthSampleMapper / DataSourceSettings、HealthStore プロトコル + MockHealthStore(actor)+ HealthKitStore
- PlanStore / PlanRecord(schemaVersion つき JSON、App Group コンテナ、取れなければ Application Support に退避)
- DailySummary / PlanStatus / DailySummaryBuilder(取得 → 1日の値 → 7日平均 → フェーズの判定)
- HomeModel(フォアグラウンド復帰で権限要求と再取得)、ContentView(7日平均と当日の数値だけ)

計画からの逸脱(意図的): 01-design.md では「計画がなければ build は nil」としていたが、初回設定の UI がまだないため、計画がなくても 7日平均と当日を返し、計画の判定だけ nil(`DailySummary.plan: PlanStatus?`)にした。実機で HealthKit の読み取りを確認するため。

確認済み: swift test 122件、xcodebuild test でアプリ19件 + 122件通過。シミュレーターで権限ダイアログ(体重・体脂肪率の読み取りのみ、確定文言)を確認。

## 特に確認してほしいこと

1. コンセプト上の制約: ContentView に出す数値(7日平均と当日)と文言が「毎日の画面は体重だけ」「評価ラベル・警告色なし」に収まっているか。HomeModel のエラー時の扱い。
2. 境界値と日付: DailySummaryBuilder の取得期間(開始日 − 6日の0時 〜 翌日0時、JST)と `.strictStartDate`。MaintenanceNoticeJudgment の数え直し条件。ActualPace の最低窓(ステージ1に影響しないこと)。
3. HealthKit: 権限要求の型が体重と体脂肪率の2つだけか。`sourceRevision.source.bundleIdentifier` の扱い。Swift 6 strict concurrency での HealthKitStore(@unchecked Sendable)と MockHealthStore(actor)の妥当性。
4. 永続化: PlanRecord の Codable(enum の associated value)と schemaVersion の扱い。App Group の退避先の是非。
5. テストの抜け。特に DailySummaryBuilder と MaintenanceNotice の境界。

## 出力形式

AGENTS.md の指示どおり、指摘ごとに「重要度(高/中/低)、該当ファイルと行、問題の内容、再現手順または根拠、修正案」の順で書いてください。推測で断定せず、確認できないことは「未確認」と書いてください。指摘がない観点は「問題なし」と一言で済ませてください。最後に、main へマージしてよいかの総合判断を1行で書いてください。

