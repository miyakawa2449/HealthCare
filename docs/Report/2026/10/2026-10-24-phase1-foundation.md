# 作業日報 2026-10-24 フェーズ1: 開発の土台づくり

担当: Claude Code(実装)、Codex(レビュー)、人間(判断・承認)
ブランチ: `feature/phase1-foundation`(main 未マージ)

## 今日やったこと(時系列)

| 時刻 | 作業 | コミット |
| --- | --- | --- |
| 13:46 | GitHub リポジトリに接続し、初回コミットを push。`.gitignore` を追加 | 421d5ad |
| 14:18 | 03-decisions / 04-open-questions の回答を concept.md と AGENTS.md に反映 | 6e24629 |
| 14:29 | フェーズ1 実装計画(05-implementation-plan.md)を作成、3件の確認事項を承認 | 8f6b381 |
| 14:30 | XcodeGen 2.46.0 をインストール。WeightCore パッケージと PlanSettings をテスト先行で作成 | 353a96c |
| 14:33 | アプリ本体(project.yml、SwiftUI、Info.plist、entitlements)とテストを作成。シミュレーターで起動確認 | 098f4be |
| 14:33 | README を作成。環境ドキュメントを更新 | c279241, 601cca0 |
| 14:45 | Codex にレビューを依頼し、指摘1件を修正。レビュー結果を docs/review/ に保存 | 0184016 |

## 決めたこと

### 仕様(回答を文書に反映)

- ステージはB案。各ステージ開始時の体重の10%減を次の境界にし、6ステージ(123.5 → 111.2 → 100.0 → 90.0 → 81.0 → 72.9 → 67.4)。境界値は丸めずに連鎖させて最後に小数第1位へ丸め、計画作成時に確定して見直しでも変えない。
- 速いペースを伝えるのは実績ペース(直近28日間の7日平均の変化率)が月3%超のときだけ。週0.5%/1%の安全性判定は計画を立てるときの基準。
- 目安の日割りは日ごとの複利、1か月は30日固定(開始体重 × 0.98^(経過日数 ÷ 30))。
- 維持期間は28日連続で±2%以内なら卒業、外れたら数え直し。12週超はカードで提案。最終目標の後は終わりのない維持モード。
- 割合の分母: 進み具合は目安の値、維持期間は到達時体重、計画見直しは計画値、ペースはその時点の7日平均。境界値は下の区分に含め、0.01%に丸めてから比較。
- レポートは月半ば(1〜15日)と月末(月全体)。計画見直しの「2週間」は14日の窓で別扱い。
- 除脂肪量は体重 × (1 − 体脂肪率)で計算。HealthKit の読み取りは体重と体脂肪率の2つだけ。
- 開始体重は初回設定で HealthKit の直近7日平均を初期値にし、ユーザーが確認・修正する。

### プロジェクト設定

- Bundle ID `com.miyakawa.weightapp`、最低 iOS 26.0、Swift 6(strict concurrency)、Swift Testing(XCTest は使わない)、Team ID 直書き、iPhone 縦向きのみ。
- HealthKit の説明文を確定し、Info.plist に記載。
- 閾値は `PlanSettings` に集約(当初計画の「空の型」から変更)。
- feature ブランチで作業し、Codex レビュー後に main へマージ。
- テスト用シミュレーターは iPhone 17 Pro(iOS 26.5)。iPhone 16 Pro は iOS 18 系にしかなかったため計画を訂正。

## 作ったもの

```
project.yml                      XcodeGen 定義
WeightApp/App/                   @main と ContentView(「今日の体重」のみ)
WeightApp/Resources/Info.plist   HealthKit 説明文
WeightApp/WeightApp.entitlements healthkit、background-delivery
WeightAppTests/                  Swift Testing 2件
WeightCore/                      Swift Package。PlanSettings と Swift Testing 8件
README.md
docs/plan/01-foundation/05-implementation-plan.md
docs/review/01-foundation.md     Codex レビューの原文と対応
```

## 確認結果

| 確認 | 結果 |
| --- | --- |
| `swift test` | 8件通過 |
| `xcodebuild build`(iPhone 17 Pro, iOS 26.5) | 成功 |
| `xcodebuild test` | 10件通過(アプリ2件 + WeightCore 8件) |
| シミュレーター起動 | 「今日の体重」だけの画面を確認 |
| `git status` | 生成物(.xcodeproj、.build、.DS_Store)は出ない |
| 実機 | 未確認(background-delivery 付きの署名・インストール、権限ダイアログ) |

## つまずいたことと学び

1. **シミュレーター名の思い込み。** 10/19 の環境確認で「iPhone 16 Pro, OS=26.5」と書いていたが、iOS 26.5 には存在しなかった。計画を出す直前に `simctl list` で再確認して気づいた。環境情報は使う直前に再確認する。
2. **テストバンドルとホストアプリの Bundle の取り違え。** Info.plist の文言テストで `Bundle(for:)` にテスト側のクラスを渡し、テストバンドルを読んでいた。ホスト型テストでは `Bundle.main` がアプリ本体を指す。
3. **XcodeGen の共通設定はターゲット既定値に負ける。** `TARGETED_DEVICE_FAMILY` を共通 settings に書いても、XcodeGen がターゲットに生成する "1,2" に上書きされる。Codex のレビューで発覚。iPhone のみにしたい設定はターゲット側に書く。
4. **Codex は CLI から直接呼べる。** `codex exec -s read-only` で読み取り専用のレビューを依頼し、結果を受け取れる。人間が仲介しなくてよい。
5. **`.iOS(.v26)` は tools-version 6.2 から。** Package.swift を 6.0 のままにするなら iOS 18 指定で問題ない(Codex の補足)。

## 新しく足した文言

| 文言 | 使う場所 |
| --- | --- |
| 体重と体脂肪率を Apple ヘルスケアから読み取り、7日平均とレポートの作成に使います。データは外部のサーバーに送信しません。 | HealthKit の権限ダイアログ(Info.plist) |

## 残っていること

- `feature/phase1-foundation` を main にマージする(PR かローカルの fast-forward かは未決)。
- 実機確認(署名・インストール、HealthPlanet の Bundle ID の確認)。
- 「最初の1か月は判定をゆるめる」の具体案はフェーズ2の計画で出す。

## 次にやること

フェーズ2(WeightCore のロジック)の計画。7日平均、目安の日割り、ステージ境界の計算、進み具合の判定、安全性判定を、AGENTS.md のドメインルール表と「境界値と丸め」をテストケースにしてテスト駆動で書く。
