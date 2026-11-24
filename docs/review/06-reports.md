# フェーズ6 Codex レビュー結果

実施日: 2026-11-24
対象: `feature/phase6-reports`(main からの差分)
実行方法: Claude Code から `codex exec -s read-only`。reasoning effort は medium。

## 1回目(e520994 時点)

### Codex の回答(原文)

以下は `main...HEAD` のコミット済み差分に対する指摘です。未コミットの `ReportView.swift` は対象外としました。

1. 重要度: 高  
   該当ファイルと行: [ReportContent.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/ReportContent.swift:124)、[ReportView.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/ReportView.swift:384)、[ReportWording.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/ReportWording.swift:69)  
   問題の内容: 最終ステージの月末レポートに、最終目標の体重と到達予定が「次の区切り」として表示されます。また、最終到達時の出来事にも「最後の区切り {体重}」が表示されます。「最終目標はロードマップ画面にだけ出す」制約に反します。  
   再現手順または根拠: 最終ステージの `.losing` を渡すと、`stageInfo.boundaryWeight` は `roadmap.targetWeight` です。これが `ReportStage.target` に入り、`ReportView` で「次の区切り 67.4 kg」および到達予定として描画されます。最終到達後は `.reachedTarget` が「最後の区切り {weight}」になります。最終ステージ減量中のレポートPreview・テストはなく、この経路は既存テストで検出されません。  
   修正案: 最終ステージではレポート用の `target` と最終目標に対する `estimatedArrival` を設定せず、ステージ番号と進み具合だけを表示してください。`.reachedTarget` も数値付きの「最後の区切り」ではなく、最終目標を示さない維持モード移行の文言にしてください。最終ステージ減量中と最終到達月の表示テストを追加してください。

2. 重要度: 中  
   該当ファイルと行: [ReportView.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/ReportView.swift:325)、[ReportContent.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/App/ReportContent.swift:44)  
   問題の内容: 月末レポートで体組成の変化方向が表示されません。`CompositionValues.Pair.direction` は保持されていますが、画面は基準値と現在値だけを描画しています。承認済み設計の「月末は数値と方向」に未達です。  
   再現手順または根拠: 前月の体脂肪率30.0%、今月29.0%の月末レポートを開いても、「下がった」は表示されません。除脂肪量も同様です。  
   修正案: 各行に `direction` を用いた文言または矢印を表示してください。色は既存の月半ばと同様、アクセント色と灰色だけにしてください。表示テストも追加してください。

3. 重要度: 低  
   該当ファイルと行: [ReportView.swift](/Users/tsuyoshi/dev/HealthCare/WeightApp/Views/ReportView.swift:291)  
   問題の内容: 月半ばで体組成を比較できない場合、「数値は月末レポートでお届けします」という承認済みの添え書きが表示されません。`.directions` の場合にだけ表示されています。  
   再現手順または根拠: `midNoBodyFat` Preview相当の `.unavailable` を表示すると、「体脂肪率の記録が少なく、比べられませんでした。」だけになります。  
   修正案: 月半ばでは比較可否にかかわらず、月末案内を体組成カードの共通フッターとして表示してください。

マージ可否: **不可**。コンセプト上の変更不可制約に反する高重要度の指摘があります。

### 対応

| # | 重要度 | 対応 |
| --- | --- | --- |
| 1 | 高 | **対応しない(人間の確認事項として残す)。** concept.md の画面の表で、メイン画面の「表示しないもの」は「最終目標(最終ステージでは「次の区切り」として出す)」とされており、ホームのステージカードもフェーズ4からこの扱い。到達時の「最後の区切り {体重} kg に届きました」はフェーズ5で人間が決めた文言(05-cards/04-wording.md)。レポートはホームと同じ扱いにそろえた |
| 2 | 中 | 対応。月末の表で、項目名の下に方向(矢印と「下がった / 横ばい / 上がった」)を出す。色はアクセントと灰色だけ |
| 3 | 低 | 対応。月半ばでは、比べられないときも「数値は…の月末レポートでお届けします。」を出す |

あわせて、レビュー対象外だった未コミットの変更(レポートタブを離れたら最新に戻す)と、画像への書き出しで見つけた一言の省略(折り返して全文を出す)も同じコミットに入れた。
