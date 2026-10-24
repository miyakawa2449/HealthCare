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

## 依頼文

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
