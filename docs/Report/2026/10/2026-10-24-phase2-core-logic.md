# 作業日報 2026-10-24 フェーズ2: WeightCore のドメインロジック

担当: Claude Code(実装)、Codex(レビュー)、人間(判断・承認)
ブランチ: `feature/phase2-core-logic`(main 未マージ。未決 #9 の回答待ち)
前の作業: [2026-10-24-phase1-foundation.md](2026-10-24-phase1-foundation.md)

## 今日やったこと(時系列)

| 作業 | コミット |
| --- | --- |
| フェーズ1を main に fast-forward マージ | (main 56dffce) |
| フェーズ2の計画(設計、テストケース一覧、決定事項8件、最初の1か月の案A/B/C)を提出 | 1572e05 |
| 回答を反映(60日は定数参照、平均に使った日数、月の定義の一致テスト、実績ペースの窓の下限) | (計画の更新) |
| 第1弾: CalendarDay、丸め、1日の体重、7日平均、Pace/目安、進み具合、安全性(38件) | 76c67fc |
| 第2弾: ロードマップ、実績ペース、維持期間、計画見直し(69件) | 243ff4e |
| Codex レビュー → 指摘4件のうち3件を修正、1件を未決として提示(73件) | 44fb833 |

## 決めたこと(03-decisions.md の回答)

- 到達予定日の維持期間は60日。定数 `assumedMaintenanceDays` を1か所に置き、テストもそれを参照。
- 7日平均は窓にある日だけで平均し、使った日数も返す。下限は実機で使ってから決める。
- ソース優先(HealthPlanet)を先に適用し、その中で最初の測定値。
- 「月」= 30日・日ごとの複利を `Pace` に集約。目安の日割りと実績ペースの月換算が逆関数になることをテストで確認。
- 最初の1か月は案A(判定しない、`settlingIn`)。実績ペースの窓の始まりは14日目より前にしない。31日目は窓17日、42日目で初めて28日。
- 計画見直しのずれは上下両方向。維持期間中に7日平均が出ない日はカウントを0に戻す。

## 作ったもの(WeightCore)

```
CalendarDay            年月日だけの日付。Date からは Calendar(Asia/Tokyo)で、日数計算は UTC 固定
Rounding               Ratio(0.01%)/ Weight(0.1kg)。ちょうど半分の表現誤差を救う補正つき
DailyWeight            WeightSample、SampleSource、DailyWeight、DailyWeightResolver
SevenDayAverage        kilograms と daysUsed
Pace / Guideline       月の定義と目安の日割り
ProgressJudgment       settlingIn / onTrack / aheadOfSchedule / slowerPace
SafetyJudgment         comfortable / caution / danger、必要ペースの逆算
Roadmap / Stage        境界、マイルストーン、到達予定日、今いるステージ、再起点、Codable
ActualPace             monthlyRate と windowDays、isTooFast
MaintenanceJudgment    inProgress / graduated / exceededMaximum
PlanReviewTrigger      shouldPropose
PlanSettings           assumedMaintenanceDays、initialPeriodDays、actualPaceWindowStartFloor を追加
```

## 確認結果

| 確認 | 結果 |
| --- | --- |
| `swift test` | 73件通過(12スイート) |
| `xcodebuild test`(iPhone 17 Pro, iOS 26.5) | アプリ2件 + WeightCore 73件通過 |
| Codex レビュー | 高1・中2・低1。高と中1件と低は修正済み。中1件は未決として人間に提示 |

## Codex の指摘と対応

1. **(高)12週を超えた後の28日連続で卒業してしまう。** 「12週超は強制的に進めず、ユーザーが選ぶ」に反するので、卒業は84日以内に限るよう修正。境界テスト(経過84日で卒業、85日で exceededMaximum、上限超過後の28日連続)を追加。
2. **(中)維持期間中や卒業直後の再起点で、到達予定日に含める維持期間を決められない。** 仕様が未定義なので、「減量中のステージでだけ使う」を前提としてコメントに明記し、03-decisions.md #9 に選択肢を提示。
3. **(中)最終目標が丸められない経路がある。** BMI22 から計算した 67.375 がそのまま最終境界になり、7日平均 67.4 で到達にならない。初期化時に 0.1kg へ丸めるよう修正し、テストを追加。
4. **(低)丸めの補正 1e-9 の許容誤差が明文化されていない。** コメントとテストで明文化。

## つまずいたことと学び

1. **二進数の「ちょうど半分」。** (100.505 − 100) ÷ 100 は 0.00504999… になり、普通に丸めると下に落ちる。境界値をテストに固定したことで気づけた。ゼロから遠ざかる向きの微小な補正で救い、許容誤差を文書化した。
2. **1-based と 0-based の混在。** 「31日目」「14日目」は人間の言葉、コードは「経過日数」。設定値は経過日数(`actualPaceWindowStartFloor = 13`)にし、コメントに「14日目 = 経過13日」と両方書く形にした。Codex も「問題なし」と確認。
3. **目安の曲線と維持期間の関係は未定義だった。** 目安は開始体重からの連続曲線なので、維持期間中に体重を保つと「ゆっくりペース」や計画見直しの条件に当たる。Codex の指摘 #2 から派生して気づいた。設計変更を伴うので、フェーズ3の前に決める。
4. **テストデータの作り方。** 7日平均は1日の外れ値を均してしまうので、「11-10 の平均だけ範囲外」を作るには7日間続けて外れ値を置く必要があった。体重を一定にすると平均も一定になり、目安は日ごとに下がるので、窓の最初の日が最もずれが小さい、という性質で「ちょうど2%」の境界を作った。
5. **自分のテスト値の取り違え。** 許容誤差のテストで、補正幅の内側の値を外側として期待してしまった。文書化した数値(1e-10kg)に照らして期待値を直した。

## 残っていること

- 03-decisions.md #9(維持期間中の計画値と再起点)の回答。回答によって `Guideline` の引数がロードマップ基準に変わる。
- 回答後に main へマージ。
- 7日平均の日数下限は実機で使ってから決める。

## 次にやること

#9 の回答を受けて必要なら設計変更し、main にマージ。その後フェーズ3(HealthKit 連携: 体重と体脂肪率の読み取り、HKSource の Bundle ID → SampleSource の変換、プロトコルとモック)の計画を出す。
