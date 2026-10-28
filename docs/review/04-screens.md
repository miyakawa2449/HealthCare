# フェーズ4 Codex レビュー結果

実施日: 2026-10-28
対象: `feature/phase4-screens`(main からの差分)
実行方法: Claude Code から `codex exec -s read-only`。reasoning effort は medium。

## 1回目(4d1f537 時点)

### Codex の回答(原文)

## 指摘

### 1. 重要度: 高

該当: [PlanSetup.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/PlanSetup.swift:19)、[SetupFormState.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/SetupFormState.swift:41)、[Roadmap.swift](/Users/tsuyoshi/dev/HealthCare/WeightCore/Sources/WeightCore/Roadmap.swift:117)

問題の内容:  
`PlanSetup.validate` が有限値かを検証していません。開始体重が正の無限大の場合は検証を通過し、`Roadmap.makeStages` の `while true` で `raw *= 0.9` が永久に無限大のままとなり、アプリがハングします。

再現手順または根拠:

1. 初回設定の開始体重欄へ貼り付けなどで `"inf"` を入力するか、`startPlan(startWeight: .infinity, targetWeight: 67.4)` を直接呼ぶ。
2. `Double(startText)` は無限大を表現できる。
3. `.infinity > 0` および `67.4 < .infinity` が成立するため、検証を通過する。
4. `Roadmap.makeStages` の境界生成が終了しない。

修正案:  
範囲の上下限を設ける必要はありませんが、`startWeight.isFinite` と `targetWeight.isFinite` を検証してください。身長からの初期値計算についても、非有限値を入力欄へ反映しないようにすると安全です。非有限値の境界テストも追加してください。

---

### 2. 重要度: 中

該当: [HomeModel.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:101)、[SetupView.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/SetupView.swift:107)

問題の内容:  
`startPlan` は計画の保存後に行う `refresh()` の失敗を呼び出し元へ伝えません。保存後の再取得に失敗すると、計画は保存済みなのに `summary` は「計画なし」の古い状態のままとなり、初回設定画面が残ります。`SetupView` 側も成功扱いにして `saveFailed = false` とします。

再現手順または根拠:

1. 計画なしの状態で最初の `refresh()` を成功させる。
2. その後、`HealthStore` が取得時にエラーを投げるようにする。
3. `startPlan` を実行する。
4. `PlanStore.save` は成功するが、108行目の `refresh()` は内部でエラーを握りつぶす。
5. `startPlan` は正常終了し、`summary.plan` は nil のままなので `RootRoute` は `.setup` のままになる。
6. 再度ボタンを押すと、保存済み計画を初回設定から上書きできる。

修正案:  
保存後の再構築を `startPlan` 内で失敗として扱えるようにするか、保存成功後は少なくとも保存した `PlanRecord` を基に `summary` を更新してください。保存成功とHealthKit再取得失敗を分離し、「保存済みなのに初回設定へ戻る」状態を作らないテストが必要です。

---

### 3. 重要度: 中

該当: [HomeModel.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:47)、[WeightApp.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/WeightApp.swift:12)

問題の内容:  
`refresh()` の二重実行を防止・統合する仕組みがありません。`@MainActor` でも `await` 中は再入可能なので、複数の取得が並行し、古い要求が後から完了して新しい `summary` や `lastRefreshFailed` を上書きできます。

再現手順または根拠:

1. 取得完了順を制御できる `HealthStore` を用意する。
2. refresh Aを開始してHealthKit取得中に停止させる。
3. データを更新してrefresh Bを開始し、先に成功させる。
4. その後Aを古い値で完了させる。
5. Aが最後に代入するため、画面が古い値へ戻る。成功・失敗の順序によっては `lastRefreshFailed` も最新要求と逆になる。

起動時とフォアグラウンド復帰時の `Task`、および `startPlan` 内から同じメソッドが呼ばれるため、呼び出し元だけでは排他が保証されていません。

修正案:  
進行中のrefreshを共有する、二重実行を無視する、または世代番号を持って最新要求だけが状態を反映するようにしてください。遅い古い成功・遅い古い失敗の両方をテストしてください。

---

### 4. 重要度: 中

該当: [StageCard.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/StageCard.swift:118)

問題の内容:  
見た目では数値を隠している進捗バーが、VoiceOverには「進み具合 42パーセント」のように割合を読み上げます。「毎日の画面に出す数値は体重だけ」というコンセプト制約に対し、アクセシビリティ利用者だけ進捗率を数値で受け取る状態です。

再現手順または根拠:  
`ProgressBar` に数値の `.accessibilityValue("\(...\)パーセント")` が明示されています。VoiceOverを有効にして進捗バーへ移動すると読み上げ対象になります。

修正案:  
数値ではなく、既にカード内に出している穏やかな進み具合の文言をアクセシビリティ値に使うか、バーを装飾要素として非表示にしてください。

なお、Swift Chartsが45・50行目の数値をVoiceOverやオーディオグラフへ公開し、計画値の具体的数値まで読めるかは実機で未確認です。[WeightChart.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/WeightChart.swift:43) も併せてアクセシビリティ確認が必要です。

---

### 5. 重要度: 低

該当: [WeightChart.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/WeightChart.swift:44)

問題の内容:  
計画値が1点しかない計画初日は、計画系列に `LineMark` しかなく、計画の点を明示的に描いていません。設計の「点が1つしかない（計画初日）ときは点だけを打つ」を満たさず、計画の点線系列が視認できない可能性があります。

再現手順または根拠:  
計画初日は起点より前の `guideline` が nil なので計画値は1点です。`PointMark` を追加しているのは7日平均系列だけです。実際に単独の `LineMark` がどの程度描画されるかはPreviewで未確認です。

修正案:  
`guideline.count == 1` のとき、計画色・計画用シンボルの `PointMark` を追加してください。

## 問題なしの観点

- ホームの視覚表示には体脂肪率、除脂肪量、BMI、評価ラベル、目安の数値軸、赤・橙・黄の警告色は見当たりません。
- 最終目標は最終ステージで「次の区切り」として表示される構造で、それ以前のホームには直接表示されません。
- 確定済みのホーム、初回設定、維持期間、維持モード、利用不可時の文言は `04-wording.md` と一致しています。
- `DisplayFormat` はAsia/Tokyo固定で、上旬1〜10日、中旬11〜20日、下旬21日以降の境界も正しいです。
- `WeekRecordCard.weekStart` は月曜始まりで、月曜・水曜・日曜・翌週月曜のテストがあります。
- `DailySummary.history` は取得開始日と直近28日の遅い方から生成しており、取得範囲より前を作りません。現在フェーズの起点より前の計画値も nil です。
- `hasReachedFirstMilestone` は7日平均を0.1kgに丸めてから境界以下を到達としており、117.34/117.35の境界テストがあります。
- `StageCard.fraction` は通常の有限値について0〜1へクランプされ、nil・上振れ・到達超過・起点以下もテストされています。
- `RootRoute` は初回refresh完了前に設定画面を出さず、計画の読み込み失敗時も初回設定へ進みません。
- 身長変更による最終目標の再計算と、手動編集後に上書きしない規則は実装・テストされています。
- 最初の区切りは保存後に再buildされ、一度保存された日付を消さない構造です。
- `PreviewData` は `@MainActor`、`MockHealthStore` はactorで、`replaceWeights` もactor隔離されています。確認した差分内にSwift 6 strict concurrencyのコンパイルエラー要因は見当たりません。
- `git diff --check main` に空白エラーはありません。
- 提示されたテスト成功結果は参照しましたが、この環境は読み取り専用で一時キャッシュも作成できないため、`swift test` と `xcodebuild test` の再実行は未確認です。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 高 | `PlanSetup.validate` に有限値の検証(`.notFinite`)を追加。`SetupFormState` は `.notNumber` として扱い、身長が非有限なら最終目標に反映しない。テスト追加(inf / nan)。 |
| 2 | 中 | `startPlan` は、すでに計画があれば `alreadyStarted` を投げて上書きしない。保存後の取り直しに失敗したら `savedButRefreshFailed` を投げる。`SetupView` はこの2つを「計画は保存しました。ヘルスケアから体重を読み取れなかったので、もう一度開いてみてください。」と出す(新しい文言)。テスト追加。 |
| 3 | 中 | `refresh()` に世代番号を持たせ、最新の要求だけが `summary` / `lastRefreshFailed` / `hasRefreshed` を反映する。遅い古い成功・遅い古い失敗のテストを `DelayedHealthStore` で追加。 |
| 4 | 中 | `ProgressBar` を `accessibilityHidden(true)` にして割合を読み上げない。`WeightChart` は `accessibilityElement(children: .ignore)` で各点の値(計画の数値を含む)を公開しない。 |
| 5 | 低 | 計画値が1点だけのとき `PointMark` を打つ。 |

## 2回目(7b1ba56 時点)

### Codex の回答(原文)

## 指摘

### 1. 重要度: 中

該当ファイルと行: [HomeModel.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:128)、[HomeModel.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:66)

問題の内容:  
`startPlan` 内の `refresh()` が、後から始まった `refresh()` によって破棄された場合を失敗として扱ってしまいます。破棄された要求自体が成功していても、古い `summary` が計画なしのままなら `savedButRefreshFailed` が投げられます。

再現手順または根拠:

1. 計画なしの初回取得を完了し、`summary.plan == nil` の設定画面を出す。
2. `startPlan` を実行し、保存後の refresh A を途中で待機させる。
3. フォアグラウンド復帰などで refresh B を開始し、Bを待機させる。
4. Aを成功させる。
5. Aは66行目で世代が古いとして破棄される。
6. `startPlan` は128行目から戻るが、Bは未完了なので `summary` は計画なしのまま。129行目で `savedButRefreshFailed` を投げる。
7. HealthKit読み取りは失敗していないのに、設定画面には「ヘルスケアから体重を読み取れなかった」と表示される。

現在の追加テストは「新しい要求が先に完了した後、古い要求が完了する」順序のみで、この交差は未確認です。

修正案:  
`refresh()` から適用・失敗・別世代に置き換えられたことを判別できる結果を返し、置き換えられた場合は最新世代の完了を待ってください。あるいは進行中の最新refreshを共有し、`startPlan` がそれを待つ方式にしてください。`savedButRefreshFailed` は、最新の再取得が実際に失敗した場合だけ投げるのが適切です。

## そのほかの確認結果

- `.notFinite` と `.notNumber` の写像は前回指摘 #1 を解消しています。
- `alreadyStarted` により、保存済み計画を初回設定から上書きする問題は解消しています。
- `hasRefreshed` は最新世代だけで立つため、古い要求の結果で初回画面を振り分ける穴は見当たりません。最新要求の完了までは `.loading` が維持されます。
- 古い成功・古い失敗が最新状態を上書きしない処理は正しく実装されています。
- ProgressBar、グラフのアクセシビリティ、計画が1点のときの表示は前回指摘を解消しています。
- 新しい文言は責める表現や評価ラベルを含まず、コンセプト上の問題は見当たりません。
- 前回「問題なし」としたコンセプト・表示・日付・丸めの観点に、今回の修正による副作用は見当たりません。
- 提示されたテスト結果は参照しましたが、読み取り専用環境のため再実行は未確認です。

上記1件があるため、現時点では「マージ可」とは判断しません。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 中 | `refresh()` が `RefreshOutcome`(succeeded / failed / superseded)を返し、進行中の最新の取り直しを `latestRefresh` に持つ。`startPlan` は自分の取り直しが置き換えられても `awaitLatestRefresh()` で最新の結果を待ってから判断する。交差(保存後の取り直しが後から始まった取り直しに置き換えられ、そちらが成功)のテストを追加。アプリ70件通過。 |

## 3回目(379a05d 時点)

### Codex の回答(原文)

## 指摘

### 1. 重要度: 中

該当ファイルと行: [HomeModel.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:86)

問題の内容:  
`awaitLatestRefresh()` は、待っていた Task が `.succeeded` または `.failed` を返した直後、新しい `refresh()` が始まって `latestRefresh` を差し替えていても、古い結果をそのまま返す競合があります。

`.superseded` は Task 内の69行目で世代を確認した時点までしか保証しません。Taskの完了から `await task.value` の継続がMainActorで再開するまでの間に、別の `refresh()` が始まる可能性があります。

再現手順または根拠:

1. `awaitLatestRefresh()` が最新Task Aを待つ。
2. Aが69行目の世代確認を通過し、`.succeeded` で完了する。
3. `awaitLatestRefresh()` の継続が再開する前に、フォアグラウンド復帰などからrefresh Bが始まり、`latestRefresh`がBに差し替わる。
4. 88行目がAの結果を受け取り、89行目で`.superseded`ではないため、そのまま`.succeeded`を返す。
5. Bがまだ進行中、または後で失敗しても、`startPlan`はAの成功を最新結果として扱う可能性がある。

有限回の差し替えで87〜90行目のループ自体が終了しなくなる経路は見当たりません。継続的に外部からrefreshが開始され続ける場合は待ち続け得ますが、それは「常に最新を待つ」という仕様上の挙動です。

修正案:  
待ち始めた時点の世代番号も保持し、`task.value`を取得した後に、その世代が現在の`refreshGeneration`と一致するか再確認してください。不一致なら、結果が`.superseded`でなくても最新Taskを待ち直します。`latestRefresh`を「世代番号とTaskの組」にする方法でも対応できます。

「Task Aが成功完了した後、Aの待機側が再開する前にTask Bが開始される」順序のテストも追加してください。

## その他の確認結果

- 2回目で指摘した「保存後のrefreshが進行中の別refreshに置き換えられる」経路は、追加テストで扱われた完了順については解消しています。
- `Task { @MainActor [self] in … }`はクロージャーと捕捉した`self`の両方がMainActorに隔離されており、確認したコード上、Swift 6 strict concurrency違反は見当たりません。
- `git diff --check main`では、レビュー記録内のMarkdown改行用末尾空白のみが報告されました。実装コードの空白エラーはありません。
- 提示されたテスト成功結果は参照しました。読み取り専用環境で一時キャッシュを作成できないため、こちらでの再実行は未確認です。

上記1件があるため、現時点では「マージ可」とは判断しません。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 中 | `awaitLatestRefresh()` は、待った Task が終わったあと「今も `latestRefresh` と同じ Task か」で判断し、違えば待ち直す(結果の種類では判断しない)。待っている間に新しい取り直しが始まる経路のテストを追加(アプリ71件)。「Task A の完了直後、待機側の再開前に B が始まる」という厳密な順序はテストで強制できないため未確認。コード上は同一性の確認で防いでいる。 |

## 4回目(aa5131a 時点)

### Codex の回答(原文)

指摘はありません。3回目の指摘は解消しています。

[HomeModel.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/HomeModel.swift:88) は、待機した Task の完了後に `latestRefresh` との同一性を再確認しています。A の完了後、待機側の再開前に B が始まった場合も、91行目で差し替えを検出して B を待ち直します。同一性確認から結果返却までは MainActor 上に suspension point がないため、確認した競合経路は閉じています。

厳密な順序を強制したテストは記録どおり未確認ですが、追加テストは待機中の差し替えと最新結果の追従を確認しています。提示されたアプリ71件・WeightCore 139件の成功は参照しましたが、読み取り専用環境のため再実行は未確認です。

**マージ可です。**

### 対応

指摘なし。マージ可。
