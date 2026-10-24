# フェーズ1 Codex レビュー結果

実施日: 2026-10-24
対象: `feature/phase1-foundation`(main からの差分)
実行方法: Claude Code から `codex exec -s read-only`(読み取り専用)で依頼。モデルは gpt-5.6-sol、reasoning effort は medium。
依頼文: このファイル末尾の「依頼文」を参照。

## Codex の回答(原文)

## 指摘

- 重要度: 中
- 該当ファイルと行: [project.yml](/Users/tsuyoshi/dev/HealthCare/project.yml:18)
- 問題の内容: `TARGETED_DEVICE_FAMILY: "1"` がプロジェクト共通設定にありますが、XcodeGenが各iOSターゲットへ生成する既定値 `"1,2"` に上書きされ、実効設定ではiPhone・iPad対応になっています。「iPhoneのみ」という承認済み計画と一致しません。
- 再現手順または根拠: `xcodegen generate` 後の `WeightApp.xcodeproj/project.pbxproj` で、WeightAppターゲットのDebug/Release双方に `TARGETED_DEVICE_FAMILY = "1,2"` が生成されています。
- 修正案: WeightAppターゲットの `settings.base` に `TARGETED_DEVICE_FAMILY: "1"` を指定し、再生成後のターゲット設定が `1` になることを確認してください。

## 問題なしの観点

1. `PlanSettings.swift`: 問題なし。既定値はドメインルールと一致し、`weeklyCautionLimit` の「safeを超え、この値以下」というコメントも、0.5%ちょうどは「無理がない」、1%ちょうどは「頑張りすぎ注意」という境界規則と整合しています。

2. `Package.swift`: 問題なし。PackageのiOS 18対応はアプリ本体の最低iOS 26.0を引き下げません。macOS 15の指定も`swift test`用途として妥当です。なお、手元のPackageDescription定義では `.iOS(.v26)` はtools-version 6.2から利用可能なため、tools-version 6.0のままでは使用できません。

3. `project.yml` のSwift 6・テスト構成: 上記の端末設定を除き問題なし。生成結果で `SWIFT_VERSION = 6.0`、`SWIFT_STRICT_CONCURRENCY = complete`、`IPHONEOS_DEPLOYMENT_TARGET = 26.0` を確認しました。スキームにもWeightAppTestsとWeightCoreTestsが登録されています。

4. `WeightAppTests.swift`: 問題なし。生成結果で `TEST_HOST` と `BUNDLE_LOADER` がWeightAppを指しているため、ホスト型ユニットテストにおける `Bundle.main` の使用は妥当です。

5. コンセプト上の制約: 問題なし。「今日の体重」以外の数値・評価ラベル・警告色・通知・最終目標は追加されていません。

6. 実機確認: background-delivery付きの署名・インストールとHealthKit権限ダイアログは、報告どおり未確認です。

7. テスト: 通常の`swift test`と`xcodebuild test`の独立再実行は読み取り専用環境のため未確認です。申告された8件・10件の成功と、生成済み設定は確認しました。

総合判断: iPhone限定設定を修正して再生成・再テストした後であれば、mainへマージしてよいです。

## 対応

| 指摘 | 対応 | 確認 |
| --- | --- | --- |
| TARGETED_DEVICE_FAMILY がターゲット側の既定値 "1,2" に上書きされる(中) | project.yml の共通 settings から外し、WeightApp と WeightAppTests の各ターゲットの settings.base に `TARGETED_DEVICE_FAMILY: "1"` を置いた | 再生成後の project.pbxproj で全ターゲットが `1` になることを確認。`xcodebuild test` 10件通過 |

## 依頼文

あなたは AGENTS.md の「Codex(検証担当)」です。AGENTS.md と CLAUDE.md を最初に読み、そのルールに従ってレビューしてください。コードは書き換えず、指摘にとどめてください。

## レビュー対象

ブランチ `feature/phase1-foundation` の、main からの差分(`git diff main...HEAD`)。フェーズ1「開発の土台づくり」の実装です。計画は docs/plan/01-foundation/05-implementation-plan.md にあります。

## 変更の要約と意図

XcodeGen で生成する iOS アプリ(WeightApp)と、ロジック用 Swift Package(WeightCore)の骨組みを作った。計算や判定のロジックは入れず、閾値だけを WeightCore/Sources/WeightCore/PlanSettings.swift に集約した。テストは Swift Testing で、PlanSettings の値を AGENTS.md のドメインルールと照合する8件と、アプリ側の2件(モジュール読み込み、Info.plist の HealthKit 説明文の一致)。

確認済み: `swift test` 8件通過、`xcodebuild test`(iPhone 17 Pro, iOS 26.5)10件通過、シミュレーターで「今日の体重」の画面を確認、`git status` に生成物が出ない。

## 特に見てほしい箇所

1. WeightCore/Sources/WeightCore/PlanSettings.swift: 各値が AGENTS.md の「ドメインルール」表と一致しているか。`weeklyCautionLimit` のコメント(safe を超えこの値以下は注意)が「境界値と丸め」の行と整合しているか。
2. WeightCore/Package.swift: platforms を iOS 18 / macOS 15 にしている。アプリの最低 iOS は 26.0 だが、`swift test` を macOS で回すために macOS を含めた。tools-version 6.0 で `.v26` が指定できるかは未確認。
3. project.yml: SWIFT_STRICT_CONCURRENCY=complete と SWIFT_VERSION=6.0 で Swift 6 言語モードになっているか。スキームの test に `package: WeightCore/WeightCoreTests` を入れている。
4. WeightAppTests/WeightAppTests.swift: `Bundle.main` でホストアプリの Info.plist を読む方法が妥当か。
5. コンセプト上の制約への違反がないか(文言、色、通知など。今回は「今日の体重」の Text だけ)。

## 実機でしか確認できないこと(未確認)

- background-delivery の entitlement を付けた状態で実機に署名・インストールできること。
- HealthKit の権限ダイアログ(権限要求のコードはまだない)。

## 出力形式

AGENTS.md の指示どおり、指摘ごとに「重要度(高/中/低)、該当ファイルと行、問題の内容、再現手順または根拠、修正案」の順で書いてください。推測で断定せず、確認できないことは「未確認」と書いてください。指摘がない観点は「問題なし」と一言で済ませてください。最後に、main へマージしてよいかの総合判断を1行で書いてください。
