# フェーズ2 Codex レビュー結果

実施日: 2026-10-24
対象: `feature/phase2-core-logic`(main からの差分、コミット 243ff4e 時点)
実行方法: Claude Code から `codex exec -s read-only`(読み取り専用)。モデルは gpt-5.6-sol、reasoning effort は medium。

## Codex の回答(原文)

## 指摘

### 1. 重要度: 高

- 該当ファイルと行: [MaintenanceJudgment.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/MaintenanceJudgment.swift:19)、[MaintenanceJudgmentTests.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Tests/WeightCoreTests/MaintenanceJudgmentTests.swift:66)
- 問題の内容: 12週間を超えた後に初めて28日連続を満たした場合も、`.exceededMaximum` ではなく `.graduated` になります。これにより「次のステージへ進む／維持を続ける」の提案を出せません。
- 再現手順または根拠: ループ内では日付の上限を確認せず、28日連続になった時点で即座に `.graduated` を返します。`maintenanceMaxDays` の確認は全期間を走査した後です。そのため、到達後85日を超えてから始まった連続期間でも、後日28日に達すれば卒業になります。計画書は「84日目までに卒業していれば卒業判定を優先」としており、上限超過後の初卒業まで優先する仕様ではありません。既存テストも12週間よりかなり前の卒業しか確認しておらず、このケースを検出できません。
- 修正案: 上限日までに卒業しなかったことが確定した時点で `.exceededMaximum` にするか、上限後の扱いにユーザー選択状態を渡してください。「上限を超えた後に初めて28日連続となるケース」を追加し、期待値を `.exceededMaximum` として固定してください。

### 2. 重要度: 中

- 該当ファイルと行: [Roadmap.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:37)
- 問題の内容: 再起点時の「到達済みステージ」と維持期間の状態を、現在体重だけから判定しているため、必要な維持期間を到達予定日から落とす場合があります。また、一度到達した後に体重が境界より上へ戻った場合は、その到達履歴も失われます。
- 再現手順または根拠: `startWeight: 111.2` で再起点するとステージ1は到達済みになりますが、残りの配列に対する `scheduled` の最初の要素では維持期間60日が加算されません。ステージ1に到達した当日または維持期間中の再起点なら、本来はステージ2の減量期間より前に維持期間が必要です。逆に維持卒業後なら加算不要であり、現在の引数だけでは両者を区別できません。既存テストは未到達の118.0kgからの再起点だけです。
- 修正案: 到達済みステージ数と現在のフェーズ（減量中／維持中／維持卒業済み）を明示的に渡す設計にするか、再起点を許すフェーズを確定仕様として制限してください。少なくとも、境界ちょうど・維持期間中・複数ステージ到達後・到達後に境界より上へ戻った場合のテストが必要です。

### 3. 重要度: 中

- 該当ファイルと行: [Roadmap.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:25)、[Roadmap.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:68)
- 問題の内容: 最終ステージの境界だけ、0.1kgに丸められない入力経路があります。
- 再現手順または根拠: `targetWeight` はそのまま保存され、最終境界では `boundary = targetWeight` としています。身長175cm・BMI 22を式から直接計算すると67.375kgなので、最終境界も67.375kgになります。さらに `hasReachedTarget(67.4)` は7日平均を67.4に丸めた後、未丸めの67.375と比較するため `false` です。仕様上の初期目標は67.4kgで、ステージ境界も丸め済みである必要があります。
- 修正案: 初期化時に最終目標を `Weight.rounded` で正規化し、保存・境界生成・到達判定で同じ値を使ってください。`targetWeight: 67.375` から最終境界67.4、平均67.4で到達となるテストを追加してください。

### 4. 重要度: 低

- 該当ファイルと行: [Rounding.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Rounding.swift:10)
- 問題の内容: `1e-9` の補正は、浮動小数点誤差だけでなく、本当に境界をわずかに下回る値も境界以上として丸めます。
- 再現手順または根拠: 例えば `Ratio.rounded(0.00504999999995)` は数学上0.0050へ丸める値ですが、スケール後に一律で `1e-9` を足すため0.0051になります。体重では同様の影響幅が約`1e-10kg`、割合では約`1e-13`なので、実測上の影響は極小です。
- 修正案: 補正を採用するなら許容する誤差幅としてコメントとテストで明文化してください。厳密な十進丸めが必要なら `Decimal`、またはULPに基づく補正を検討してください。

## 問題なしの観点

- 割合の分母: 問題なし。
- ステージ境界の非丸め連鎖と固定期待値6件: 最終目標が既に0.1kg単位なら問題なし。
- 進み具合・安全性・計画見直しの境界区分: 問題なし。
- `CalendarDay` のUTC固定による暦日差分: Gregorianの年月日として扱う限り、Asia/Tokyoを含む夏時間のないタイムゾーンで問題なし。
- 31日目＝経過30日、42日目＝経過41日の扱い: 問題なし。
- 維持判定で到達日の7日平均が到達前6日を含む点: 仕様が「到達日から、その日の7日平均を数える」としているため問題なし。下降の影響で後続日に帯を外れればカウントがリセットされます。
- コンセプト上の表示・文言・外部送信制約: 今回の純粋ロジック差分には違反なし。
- テスト再実行: 読み取り専用環境のため未確認。提示された69件成功結果とコードを静的に確認しました。

**総合判断: 高重要度の維持期間判定を修正するまで、mainへのマージは見送るべきです。**


## 対応

| # | 重要度 | 対応 | 確認 |
| --- | --- | --- | --- |
| 1 | 高 | 採用。卒業は到達日から84日以内に限り、以降に28日連続を満たしても `exceededMaximum` のまま(ユーザーが選ぶ)。連続日数は表示用に数え続ける | 「経過84日に28日目 → 卒業」「経過85日 → exceededMaximum」「上限超過後の28日連続 → exceededMaximum」のテスト3件を追加 |
| 2 | 中 | 一部採用。仕様が未定義(維持期間中の計画値と再起点)なので、`Roadmap(rebasing:)` に「減量中のステージでだけ使う」前提をコメントで明記し、03-decisions.md #9 として選択肢 A/B/C を人間に提示。設計変更は回答後 | 未確認(回答待ち) |
| 3 | 中 | 採用。`targetWeight` を初期化時に 0.1kg へ丸め、最終境界と到達判定が同じ値を使うようにした | 「目標 67.375 → 67.4、7日平均 67.4 で到達」のテストを追加 |
| 4 | 低 | 採用。補正の許容誤差(割合 1e-13、体重 1e-10kg)をコメントで明文化し、内側/外側のテストを追加 | テスト追加 |

対応後: `swift test` 73件通過。

## 2回目(2cdc8e2 時点、A 案の設計変更後)

### Codex の回答(原文)

## 指摘

### 1

- 重要度: 中
- 該当ファイルと行: [PlanPhase.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/PlanPhase.swift:40)、[ProgressJudgment.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/ProgressJudgment.swift:14)、[ActualPace.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/ActualPace.swift:14)、[PlanReviewTrigger.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/PlanReviewTrigger.swift:6)
- 問題の内容: ステージ1で計画見直しを採用すると、最初の1か月の除外と実績ペースの14日目下限が再び適用されます。これらは「減量開始直後の水分減少」への対応ですが、計画見直しは最短でも開始44日目なので、再起点時にはその期間を既に過ぎています。「ステージ1だけに適用する」という判断自体は妥当ですが、「ステージ1の現在の起点から適用する」ため、見直し後にもリセットされる影響が見落とされています。
- 再現手順または根拠: 開始日を10月18日、11月30日にステージ1の計画見直しを採用すると、`rebased` が同日を新しい `origin.day` にします。その翌日は `stage == 1` かつ経過1日となるため、進み具合は再び `.settlingIn`、実績ペースは `nil` になります。計画見直しも新起点から最短44日目まで発動しません。`concept.md` は「開始から最初の1か月」としており、新しい計画起点から再度30日間除外するとは定めていません。
- 修正案: 初回開始時の除外期間と、計画見直し後のステージ起点を区別してください。例えば「初期期間を適用するか」を `PlanPhase` に保持する、または元の計画開始日を判定に渡し、ステージ1の再起点後には初期期間と14日目下限を再適用しない設計が考えられます。ステージ1での `rebased` 直後に、進み具合・実績ペース・計画見直しが再度停止しないテストも必要です。

### 2

- 重要度: 中
- 該当ファイルと行: [Roadmap.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:40)、[Roadmap.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:45)、[Roadmap.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:52)
- 問題の内容: フェーズ遷移APIが範囲外のステージ番号を正常な状態として受け入れます。特に `phaseOnArrival` はステージ数を超える番号も最終到達として扱うため、誤った維持モードへ遷移できます。また、ステージなしのロードマップでも `initialPhase` は `.losing(stage: 1)` を返します。
- 再現手順または根拠: 6ステージのロードマップで `phaseOnArrival(stage: 7, ...)` を呼ぶと、`stage >= stages.count` により `.maintenanceMode` になります。`stage: 0` は `.maintaining(stage: 0)` になり、その状態を `phaseOnAdvance` に渡すと `.losing(stage: 1)` に遷移します。一方、`rescheduled(from:)` は同じ範囲外番号を無視して元のロードマップを返すため、API間でも扱いが一致していません。開始体重が目標以下で `stages.isEmpty` の場合も、仕様上は「計画を作れない」のに `initialPhase` は減量中を返します。
- 修正案: `phaseOnArrival` は `1...stages.count`、`phaseOnAdvance` は実在する維持ステージだけを受け付け、それ以外は `nil` などで拒否してください。最終到達は `stage == stages.count` の場合だけにします。`initialPhase` もステージなしを表現できる戻り値にするか、ロードマップ生成時点で無効入力を拒否してください。ステージ0、`count + 1`、空ロードマップのテストを追加してください。

### 3

- 重要度: 低
- 該当ファイルと行: [PlanPhaseTests.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Tests/WeightCoreTests/PlanPhaseTests.swift:50)
- 問題の内容: `Roadmap.rescheduled(from:)` の最終ステージと範囲外ステージ番号の境界テストがありません。現行実装を静的に確認した限り、最終ステージの減量中・維持中の日付計算、および範囲外で元のロードマップを返す処理自体に日数ずれは見つかりませんでしたが、今後の変更で保証されません。
- 再現手順または根拠: 現在のテストはステージ1減量中、ステージ1維持中、ステージ2減量中までです。`.losing(stage: stages.count)`、`.maintaining(stage: stages.count)`、ステージ0、`stages.count + 1` は未テストです。
- 修正案: 最終ステージでは手前の予定日が不変で、最終到達予定日だけが起点から再計算されること、範囲外番号では全フィールドが不変であることを固定してください。範囲外フェーズ自体を生成不能にするなら、拒否されることをテストしてください。

## 問題なしの観点

- 前回指摘 #1（84日以内だけ卒業）: 問題なし。
- 前回指摘 #2（維持中の計画値と再起点）: A案によるフェーズ導入で問題なし。
- 前回指摘 #3（最終目標の0.1kg丸め）: 問題なし。
- 前回指摘 #4（丸め補正の許容誤差明文化）: 問題なし。
- 「最初の1か月」と14日目下限をステージ2以降へ再適用しない判断: 上記のステージ1再起点時を除けば、仕様の目的と整合しており問題なし。
- `rescheduled(from:)` の減量中・維持中・手前のステージ不変、および維持期間60日の加算位置: 問題なし。
- `ActualPace` の日数: 経過1日で `n = 1`、経過28日で `n = 28`となっており問題なし。
- コンセプト上の表示・文言・外部送信制約: 今回の純粋ロジック差分には違反なし。
- テスト再実行: 読み取り専用環境のため未確認。提示された94件成功結果とコードを静的に確認しました。

**総合判断: ステージ1の計画見直し後に初期除外期間が再発する問題と、不正なフェーズ遷移を修正するまで、mainへのマージは見送るべきです。**


### 対応

| # | 重要度 | 対応 | 確認 |
| --- | --- | --- | --- |
| 1 | 中 | 採用。最初の1か月の除外と実績ペースの14日目下限を、ステージの起点ではなく計画の開始日(`roadmap.startDay`)基準にした。判定 API(ProgressJudgment / ActualPace / PlanReviewTrigger)の引数を `settings` から `roadmap` に変更 | ステージ1で経過44日に再起点 → 経過45日に進み具合が判定される、窓が28日のまま、再起点から14日で見直しを提案できる、のテスト3件を追加 |
| 2 | 中 | 採用。`phaseOnArrival` は 1...ステージ数 の外で nil、維持モードは最終ステージだけ。`phaseOnAdvance` は範囲外で nil。`initialPhase` はステージなしで nil | 範囲外(0、ステージ数 + 1)とステージなしのテストを追加 |
| 3 | 低 | 採用。最終ステージの減量中・維持中・維持モードと、範囲外で不変のテストを追加 | テスト追加 |

対応後: `swift test` 99件通過。

### 依頼文(2回目)

あなたは AGENTS.md の「Codex(検証担当)」です。AGENTS.md と CLAUDE.md を最初に読み、そのルールに従ってレビューしてください。コードは書き換えず、指摘にとどめてください。

## レビュー対象

ブランチ `feature/phase2-core-logic` の、前回レビュー(docs/review/02-core-logic.md、コミット 243ff4e 時点)以降の差分: `git diff 243ff4e...HEAD -- WeightCore`。
前回の指摘への対応(44fb833)と、未決 #9 の回答「A 案」を受けた設計変更(2cdc8e2)が含まれます。回答の全文は docs/plan/02-core-logic/03-decisions.md #9、設計は 01-design.md の 2b を見てください。

## 変更の要約と意図

- 計画値(目安)をロードマップのフェーズに従わせた。`PlanPhase`(減量中 / 維持期間 / 維持モード)と `StageOrigin`(起点の7日平均を 0.1kg 丸め + 日付)を新設。
- `Guideline.expectedWeight(phase:on:)`: 減量中はステージの起点から月2%で日割り、維持中は到達時体重で一定。
- `ProgressJudgment` / `ActualPace` / `PlanReviewTrigger` は減量中だけ判定し、ステージ2以降は起点の日から。実績ペースの窓の始まりはステージ開始日より前にしない(28日未満は 30/n 乗)。
- `Roadmap`: `initialPhase` / `phaseOnArrival` / `phaseOnAdvance` / `rescheduled(from:)` を追加し、`Roadmap(rebasing:)` を削除。
- 前回指摘の対応: 維持期間の卒業は84日以内に限る、最終目標を 0.1kg に丸める、丸め補正の許容誤差を明文化。

確認済み: `swift test` 94件通過、`xcodebuild test` でアプリ2件 + 94件通過。

## 特に確認してほしいこと

1. 前回の指摘 #1〜#4 への対応が妥当か(#2 は A 案の設計変更で解消したつもり)。
2. 回答にない判断: 「最初の1か月は判定しない」と「窓の始まりは14日目より前にしない」をステージ1だけに適用し、ステージ2以降は起点の日から判定している。仕様との整合と、見落としている影響。
3. `Roadmap.rescheduled(from:)` の到達予定日の計算(減量中・維持中・手前のステージ不変)に境界や日数のずれがないか。
4. 1-based(31日目)と 0-based(経過30日)の取り違えが新しいコードにないか。特にステージ2以降の `ActualPace`(経過1日で n=1、経過28日で n=28)。
5. テストの抜け。特に `PlanPhase` の遷移と `rescheduled` の境界(最終ステージ、ステージ数を超える引数)。

## 出力形式

AGENTS.md の指示どおり、指摘ごとに「重要度(高/中/低)、該当ファイルと行、問題の内容、再現手順または根拠、修正案」の順で書いてください。推測で断定せず、確認できないことは「未確認」と書いてください。指摘がない観点は「問題なし」と一言で済ませてください。最後に、main へマージしてよいかの総合判断を1行で書いてください。


## 依頼文(1回目)

あなたは AGENTS.md の「Codex(検証担当)」です。AGENTS.md と CLAUDE.md を最初に読み、そのルールに従ってレビューしてください。コードは書き換えず、指摘にとどめてください。

## レビュー対象

ブランチ `feature/phase2-core-logic` の main からの差分(`git diff main...HEAD`)。フェーズ2「WeightCore のドメインロジック」の実装です。
計画と仕様は docs/plan/02-core-logic/(README、01-design、02-test-cases、03-decisions)にあります。03-decisions.md の回答が確定仕様です。

## 変更の要約と意図

AGENTS.md の「ドメインルール」を、UI と HealthKit に依存しない純粋なロジックとして WeightCore に実装した。
- CalendarDay(年月日のみ。Date からの変換は渡された Calendar、日数計算は UTC 固定)
- Ratio / Weight(0.01% と 0.1kg への丸め。ちょうど半分が表現誤差で落ちないよう 1e-9 の補正)
- DailyWeightResolver、SevenDayAverage(使った日数つき)
- Pace / Guideline(「月」= 30日・複利を1か所に集約)、ProgressJudgment(最初の1か月は settlingIn)
- SafetyJudgment、Roadmap(境界、マイルストーン、到達予定日、再起点、Codable)
- ActualPace(窓の始まりは14日目より前にしない。31日目 n=17、42日目 n=28)
- MaintenanceJudgment、PlanReviewTrigger

確認済み: `swift test` 69件通過、`xcodebuild test`(iPhone 17 Pro, iOS 26.5)でアプリ2件 + 69件通過。

## 特に確認してほしいこと

1. AGENTS.md の「コンセプト上の制約」と「ドメインルール」(特に「割合の分母」「境界値と丸め」「ステージ境界の丸め」の行)に反していないか。
2. 境界値と日付処理: CalendarDay の UTC 固定の日数計算に問題はないか(夏時間のないタイムゾーンでの暦日の差分)。「31日目 = 経過30日」のような 1-based と 0-based の取り違えがないか。
3. テストが仕様を正しく確かめているか。抜けているケース(特に境界値)があれば挙げてほしい。
4. Rounding.swift の 1e-9 補正の妥当性。副作用があるケースがあるか。
5. Roadmap の再起点(rebasing)で、到達済みステージの扱いと境界不変が仕様どおりか。
6. MaintenanceJudgment で、到達日当日の7日平均が到達前の下降期間を含む点が問題にならないか。

## 出力形式

AGENTS.md の指示どおり、指摘ごとに「重要度(高/中/低)、該当ファイルと行、問題の内容、再現手順または根拠、修正案」の順で書いてください。推測で断定せず、確認できないことは「未確認」と書いてください。指摘がない観点は「問題なし」と一言で済ませてください。最後に、main へマージしてよいかの総合判断を1行で書いてください。
