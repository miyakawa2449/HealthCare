# フェーズ5 Codex レビュー結果

実施日: 2026-10-29
対象: `feature/phase5-cards`(main からの差分)
実行方法: Claude Code から `codex exec -s read-only`。reasoning effort は medium。

## 1回目(e0975d1 時点)

### Codex の回答(原文)

マージ前に修正が必要です。重要度「高」2件、「中」2件、「低」1件です。

1. 重要度: 高  
   該当: [HomeCardViews.swift:76](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/HomeCardViews.swift:76)、[HomeCards.swift:46](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeCards.swift:46)  
   問題: 最終目標到達イベントがホームに「最終目標 67.4 kg」と表示されます。「最終目標はロードマップ画面にだけ出す」という変更不可の制約に反します。  
   再現手順または根拠: 最終ステージ到達時に `.targetReached` が保存され、未読イベントがそのままホームカードへ入り、見出しに最終目標と体重が表示されます。早期到達で最終ステージへ進む場合も同様です。  
   修正案: ホームでは「最後の区切りに届きました」など、最終目標であることを明示しない表現にするか、このイベントはロードマップだけで伝えてください。体重を出す場合も「今のステージの区切り」として扱ってください。

2. 重要度: 高  
   該当: [DailySummary.swift:58](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:58)、[DailySummary.swift:93](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:93)、[HomeModel.swift:109](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:109)  
   問題: `refresh()` とカード操作が重なると、先に開始した refresh が古い `PlanRecord` を後から保存し、カード操作を失わせる競合があります。`refreshGeneration` は画面への反映だけを抑止し、`progressed` による保存は抑止しません。  
   再現手順または根拠:

   1. refresh A が `planStore.load()` でイベントを含む記録を読み、HealthKit取得を待つ。
   2. その間に「閉じる」が記録を再読込してイベントを削除し、保存する。
   3. refresh A が自動遷移を検出すると、古いイベントを含む記録へ遷移を加えて93行目で保存する。
   4. 閉じたイベントが復活します。見直し採用や「維持を続ける」なども同様に失われ得ます。

   修正案: PlanStoreへの更新をactorなど一つの調停箇所へ集約し、最新レコードに対する原子的な変更として保存してください。少なくともHealthKit取得後に再読込して変更を適用し、保存直前の世代・リビジョン確認も必要です。この競合を遅延HealthStoreで再現するテストも追加してください。

3. 重要度: 中  
   該当: [PhaseProgression.swift:47](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/PhaseProgression.swift:47)、[Roadmap.swift:96](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:96)、[RoadmapRows.swift:89](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/RoadmapRows.swift:89)、[RoadmapRowsTests.swift:77](/Users/tsuyoshi/dev/HealthCare/WeightAppTests/RoadmapRowsTests.swift:77)  
   問題: 最終ステージ到達時、最終ステージ行の到達日が実際の日に更新されません。最終目標行は実日付、最終ステージ行は以前の予定日となり、同じ境界に異なる到達日が表示されます。  
   再現手順または根拠: 遷移後に `rescheduled(from: .maintenanceMode)` が呼ばれますが、`.maintenanceMode` は何も更新しません。`RoadmapRows` は最終ステージを `stage.estimatedArrival` で到達済みにします。テストは79行目で予定日を手動で実日付へ書き換えており、実際の遷移経路を再現していません。  
   修正案: `.maintenanceMode(arrival:)` の再スケジュール時に最後のステージの日付を `arrival.day` に更新するか、`RoadmapRows` が最終ステージだけ保存フェーズの到達日を使うようにしてください。自動遷移結果をそのまま `RoadmapRows.make` に渡す回帰テストが必要です。

4. 重要度: 中  
   該当: [HomeCardViews.swift:15](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/HomeCardViews.swift:15)  
   問題: 毎日のホーム画面に「12週間」という、体重・日付以外の数値が表示されます。「毎日の画面に出す数値は体重だけ」および今回の確認条件「数値は体重と日付だけ」に反します。  
   再現手順または根拠: 維持期間が85日目に入ると、提案カードの見出しが必ず「維持期間が12週間を超えました」になります。  
   修正案: 「維持期間が長くなりました」など数値を含まない文言に変更してください。なお、[04-wording.md:63](/Users/tsuyoshi/dev/HealthCare/docs/plan/05-cards/04-wording.md:63) の回答欄は空のため、最終文言の人間承認は未確認です。

5. 重要度: 低  
   該当: [RoadmapRows.swift:127](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/RoadmapRows.swift:127)、[04-wording.md:60](/Users/tsuyoshi/dev/HealthCare/docs/plan/05-cards/04-wording.md:60)  
   問題: 2つ前より古い維持期間の終了日は失われ、後から復元できません。現在の「終了」だけでよいという割り切りなら表示上は成立しますが、当初設計の「終了年月日」およびテスト計画F3とは一致しません。閉じたイベントも削除されるため、代替の履歴にはなりません。  
   再現手順または根拠: ステージ3減量中ではステージ2の起点しか残らず、ステージ1の維持終了日は `.ended(nil)` になります。  
   修正案: 日付表示を要件から外すなら設計・テスト計画を更新してください。残すなら、到達・自動卒業・手動前進・早期到達を記録する省略可能なフェーズ履歴を保存するのが妥当です。将来のレポートにも利用でき、単なる終了日配列より経緯を失いません。

そのほか、到達日の最初の日・丸め比較、卒業日の7日平均を起点にする処理、14日再提案の `>=`、フェーズ4 JSONの省略可能項目、`events == nil` と空配列の画面上の扱いは差分上問題を確認できませんでした。テストはこの読み取り専用環境では再実行しておらず、151件・126件の通過は提示内容のみ確認しています。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 高 | 文言の判断として人間に選択肢を出す(「最終目標 {体重} kg に届きました」のまま / 「最後の区切り {体重} kg に届きました」に変える)。コンセプトの意図は「普段の画面に遠い目標を出さない」であり、到達した瞬間の知らせをどう扱うかは仕様にないため。未変更 |
| 2 | 高 | 修正(コミット 次)。`PlanStore.update` で読み → 変更 → 書き をロックの中で行い、builder の自動遷移の保存とカードの操作の両方がこれを通る。再現テスト `HomeModelActionsTests.dismissDuringRefreshIsKept`(修正前のコードで失敗することを確認) |
| 3 | 中 | 修正。`Roadmap.rescheduled(from: .maintenanceMode)` で最終ステージの到達予定日を到達日にする。`PlanPhaseTests`(既存の「維持モードは不変」の期待を改めた)と `RoadmapRowsTests.maintenanceMode`(自動遷移の結果をそのまま渡す) |
| 4 | 中 | 文言の判断として人間に選択肢を出す(「維持期間が12週間を超えました」のまま / 「維持期間が長くなりました」など数値なしに変える)。ステージカードには既に「到達から n日目」の日数が出ているため、日数が制約の対象かは人間の判断。未変更 |
| 5 | 低 | 割り切りを設計(01-design.md 6.)とテスト項目(02-test-cases.md F3)に明記。フェーズ履歴の保存はレポート(フェーズ6)の計画で検討 |

## 2回目(d2679df 時点)

### Codex の回答(原文)

## 指摘

### 1. 重要度: 中

- 該当: [DailySummary.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:58)
- 問題: HealthKit の取得中に計画が差し替わると、古い計画の取得範囲を最新の計画へ適用します。最新計画の開始日が以前より早い場合、到達日の誤記録や自動遷移の見落としが発生します。
- 根拠・再現:
  1. 開始日が10月20日の計画で `build` を開始すると、10月14日以降だけ取得します。
  2. 取得待ち中に、開始日が10月1日の計画を `save` します。
  3. 67行目の `update` は最新計画を読みますが、渡す体重は10月14日以降だけです。
  4. 10月7日に境界へ到達していた場合、到達を見落とすか、10月14日以降の日を到達日として保存します。「起点以降で最初に到達した日」というルールに反します。

  また、取得中に計画が消えた場合は `plan == nil` になりますが、`recordedWeights` は古い開始日以降だけです。「計画がなければHealthKitの全履歴」という `DailySummary` の契約を満たしません。

  現在のUI操作には開始日変更・計画削除の経路はありませんが、`PlanStore.save` による差し替えでは再現可能です。
- 修正案: ロック内で最新レコードの「計画の有無・開始日」と取得開始時のスナップショットを比較し、異なっていたら遷移を適用せず、ロックを抜けて最新条件で取得からやり直してください。`await` はロック外のままにします。計画が消えた場合も全履歴を再取得してから plan なしの summary を作る必要があります。

## 解消確認

- 指摘2の主対象だったカード操作との上書き競合は解消しています。`update` の `body` は同期クロージャーなので内部で `await` できず、`load`・`save` も同じロックを使っています。
- 指摘3は解消しています。最終ステージの到達日は `PhaseProgression → rescheduled(from: .maintenanceMode) → PlanRecord.apply` の経路で保存され、結合テストも追加されています。
- `swift test` は実行を試みましたが、読み取り専用環境で一時キャッシュを作成できず未確認です。`git diff --check` は問題ありませんでした。
- 指摘1・4の文言判断は、依頼どおり今回の判定対象外です。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 中 | 修正。`DailySummaryBuilder.build` は、取得中に計画の有無か開始日が変わっていたら遷移を適用せず、取得からやり直す(最大2回。それでも変わり続けるときは遷移を適用せずに最新の記録で組み立てる)。テスト `planReplacedDuringFetch`(開始日の早い計画に差し替え → 正しい到達日)と `planRemovedDuringFetch`(計画が消えた → 全履歴で計画なし) |

## 3回目(c2cafd5 時点)

### Codex の回答(原文)

## 指摘

### 1. 重要度: 中

- 該当: [DailySummary.swift:62](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:62)、[DailySummary.swift:87](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:87)
- 問題: 3回目の取得中にも計画が差し替わった場合、遷移の保存は防げますが、古い取得範囲のデータと最新の `PlanRecord` を組み合わせた不整合な `DailySummary` を成功として返します。2回目の指摘が上限到達時には残っています。
- 再現手順または根拠:
  1. 3回の取得それぞれを遅延させ、取得中に開始日の異なる計画へ差し替えます。
  2. 3回目を開始日の遅い計画で開始し、取得中に計画を削除すると、`record == nil` になりますが、`recordedWeights` は全履歴ではなく遅い開始日の6日前以降だけです。
  3. 開始日の早い計画へ差し替えた場合は、遷移こそ保存されないものの、欠けた履歴を使って `planStatus`、維持判定、実績ペース、計画見直し判定を組み立てます。
  4. 追加されたテストは1回目の再取得で安定するケースだけで、上限到達時の経路は通っていません。
- 修正案: 再試行上限に達しても不整合な summary を成功として返さず、エラーとして現在の summary を維持するか、整合するスナップショットが得られるまで再試行してください。上限を残す場合は、3回とも取得中に計画を変更するテストを追加し、誤った遷移を保存しないことに加えて、不完全な `recordedWeights` や最新計画と不一致な判定を返さないことを確認してください。

## 解消確認

- 通常の再取得経路では、2回目の指摘は解消しています。計画の有無と開始日の変更をロック内の最新記録に対して検出し、不一致な取得結果で遷移を保存していません。
- 開始日が同じで境界値などだけが異なる計画への差し替えは、取得範囲が変わらず、最新の `record` に遷移を適用するため問題ありません。
- テストは読み取り専用環境のため再実行しておらず、アプリ129件・WeightCore 152件の通過は提示内容のみ確認しました。

上記1件があるため、現時点では「マージ可」とは判定しません。文言の判断は今回の対象外です。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 中 | 修正。上限(3回)まで差し替わり続けたら `DailySummaryBuilderError.planReplacedRepeatedly` を投げ、不整合な summary を返さない(`HomeModel` は前回の値を保ち `lastRefreshFailed`)。テスト `planReplacedRepeatedly`(3回とも取得中に開始日を変え、失敗すること・遷移を保存しないことを確認) |

## 4回目(9968679 時点)

### Codex の回答(原文)

## 指摘

### 1. 重要度: 低

- 該当: [2026-10-29-phase5-cards.md:35](/Users/tsuyoshi/dev/HealthCare/docs/Report/2026/10/2026-10-29-phase5-cards.md:35)
- 問題: テスト結果が「アプリ129件」と記録されていますが、提示された実行結果はアプリ130件です。
- 再現手順または根拠: 今回 `planReplacedRepeatedly` が1件追加され、ユーザー提示では「アプリ130件、WeightCore 152件が通る」とされています。
- 修正案: 「アプリ130件 + WeightCore 152件通過」へ更新してください。

## 解消確認

3回目の指摘は解消しています。

- [DailySummary.swift:68](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:68) で最大3回すべて不一致ならエラーとなり、不整合な `DailySummary` は返りません。
- 不一致時は [DailySummary.swift:95](/Users/tsuyoshi/dev/HealthCare/WeightApp/Data/DailySummary.swift:95) で遷移・判定前に再試行しています。
- `HomeModel.refresh` は既存の失敗処理に入り、前回の `summary` を維持します。
- 追加テストは3回すべての差し替え、エラー、遷移の未保存を確認しています。
- 上記の文書上の件を除き、変更箇所に回帰は確認できませんでした。

読み取り専用環境のためテストは再実行しておらず、アプリ130件・WeightCore 152件の通過は提示内容のみ確認しました。文言の判断は今回の対象外です。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 低 | 日報の件数を130件に修正 |

文言2件(「最終目標」「12週間」)を除いてマージ可。
