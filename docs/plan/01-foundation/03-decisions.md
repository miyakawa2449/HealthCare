# 決めていただきたいこと

各項目の「回答」欄に記入してください。推奨案のままでよければ「推奨どおり」と書けば十分です。

## 一覧

| # | 項目 | 推奨案 | 回答 |
| --- | --- | --- | --- |
| 1 | 製品名(ターゲット名) | `WeightApp` | |
| 2 | Bundle ID | 所有ドメインの逆引き + `.weightapp` | |
| 3 | 対応する最低 iOS | iOS 26.0 | |
| 4 | Development Team | `VC9862P72J` を project.yml に直書き | |
| 5 | テストフレームワーク | Swift Testing | |
| 6 | Swift 言語モード | Swift 6(strict concurrency) | |
| 7 | 除脂肪量の扱い | 体重と体脂肪率から計算する | |
| 8 | バックグラウンド受信の entitlement | 今回入れる | |
| 9 | HealthKit の説明文 | 下記の文案 | |
| 10 | XcodeGen の導入方法 | `brew install xcodegen` を Claude Code が実行 | |

## 各項目の詳細

### 1. 製品名(ターゲット名)

- 推奨案: `WeightApp`
- 理由: 仮称のまま。ASCII なのでパスやスキーム名で困らない。ホーム画面に出る表示名(CFBundleDisplayName)は1行の設定で後から変えられるので、今は決めなくてよい。
- 回答:
- 表示名(決めるなら):

### 2. Bundle ID

- 推奨案: 所有しているドメインがあればその逆引き + `.weightapp`(例: `jp.example.weightapp`)。ドメインがなければ `com.tsuyoshimiyakawa.weightapp`。
- 理由: 後でウィジェット(`<ID>.widget`)と App Group(`group.<ID>`)を派生させるので、先に決めて固定したい。Apple ID 内で一意なら何でもよい。
- 回答:

### 3. 対応する最低 iOS

- 推奨案: iOS 26.0
- 理由: 利用者はご自身1人。SDK は 27.1、手元のシミュレーターは 26.x。お使いの iPhone が iOS 26 以上ならこれで十分。18 以下の端末なら 18.0 にする。
- 確認したいこと: お使いの iPhone の iOS バージョン
- 回答:

### 4. Development Team

- 推奨案: Team ID `VC9862P72J` を project.yml に書く。
- 理由: 実機で HealthKit を使うには署名が必須。個人リポジトリで秘密情報でもないので直書きで可。
- 代替案: gitignore した xcconfig に逃がす(リポジトリを公開する予定があるなら)。
- 回答:

### 5. テストフレームワーク

- 推奨案: Swift Testing(`import Testing`)。XCTest は使わない。
- 理由: 境界値テストをパラメータ化して書きやすい。`swift test` と `xcodebuild test` の両方で動く。
- 回答:

### 6. Swift 言語モード

- 推奨案: Swift 6(strict concurrency 有効)
- 理由: 新規プロジェクトなので最初から厳しくする方が安い。HealthKit の非同期処理で効く。
- 回答:

### 7. 除脂肪量の扱い

- 推奨案: 体重 × (1 − 体脂肪率) で計算し、HealthKit の権限は体重と体脂肪率の2つに留める。
- 理由: 月末レポートのデザインに「除脂肪量」があるが、指示は「体重と体脂肪率の読み取り」。計算で済むなら権限を増やさない。HealthPlanet が除脂肪量を HealthKit に書くかは不明。
- 代替案: HealthKit の `leanBodyMass` の読み取り権限も追加する。
- 回答:

### 8. バックグラウンド受信の entitlement

- 推奨案: `com.apple.developer.healthkit.background-delivery` を今回入れる。
- 理由: 権限設定の一部であり、入れておいても今の動作に影響しない。実機でしか確認できない点は README に明記する。
- 代替案: 受信処理を書くフェーズまで入れない。
- 回答:

### 9. HealthKit の説明文(権限ダイアログに出る文言)

- 文案: 「体重と体脂肪率を Apple ヘルスケアから読み取り、7日平均とレポートの作成に使います。データは端末の中だけで扱います。」
- 理由: コンセプトの言葉づかい(責めない、外部送信しない)に合わせた。権限ダイアログに出る唯一の文言なので確認してほしい。
- 回答(修正があれば文案を書いてください):

### 10. XcodeGen の導入方法

- 推奨案: `brew install xcodegen` を Claude Code が実行する。
- 理由: AGENTS.md で XcodeGen は必須。ツールのインストールなので承認をもらってから実行する。
- 代替案: ご自身で先にインストールしておく。
- 回答:

## 既定として進めるもの(異論があれば記入)

| 項目 | 既定 | 異論・修正 |
| --- | --- | --- |
| 対応端末 | iPhone のみ | |
| 画面の向き | 縦向きのみ | |
| 言語 | 日本語のみ | |
| WeightCore の置き場所 | リポジトリ直下の `WeightCore/` | |
| Info.plist の管理 | 手書きファイルをコミット(XcodeGen に生成させない) | |

## 新しく足す文言の一覧

| 文言 | 使う場所 |
| --- | --- |
| #9 の説明文 | HealthKit の権限ダイアログ |

ContentView の「今日の体重」はデザインの見出しをそのまま使うので、新しい文言には数えない。
