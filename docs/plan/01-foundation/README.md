# フェーズ1: 開発の土台づくり 計画

作成日: 2026-10-19
状態: **承認待ち**(コードは未着手)

このフォルダは、最初のフェーズ(開発の土台づくり)の計画を内容別に分けたものです。
回答欄のあるファイルに記入してから、実装を指示してください。

| ファイル | 内容 | 回答欄 |
| --- | --- | --- |
| [00-environment.md](00-environment.md) | 環境の確認結果(計画の前提) | なし |
| [01-structure.md](01-structure.md) | 作成するファイルとディレクトリ構成 | なし |
| [02-commands.md](02-commands.md) | 実行して確認するコマンド | なし |
| [03-decisions.md](03-decisions.md) | 決めていただきたいこと(推奨案と理由) | **あり** |
| [04-open-questions.md](04-open-questions.md) | concept.md と AGENTS.md の矛盾・曖昧な点 | **あり** |

## 承認の手順

1. `03-decisions.md` の #1〜#10 に回答する(推奨案のままでよければ「推奨どおり」と書く)。
2. `04-open-questions.md` は今回の土台づくりには影響しないので、後回しでもよい。ただし #1 と #2 は WeightCore のフェーズに入る前に決めておきたい。
3. このファイルの「状態」を「承認」に変えるか、チャットで承認を伝える。

## 承認後の進め方

1. XcodeGen のインストール
2. テストを先に書く(WeightCore の雛形テスト、アプリの読み込みテスト)
3. 実装(project.yml、WeightCore、最小の SwiftUI アプリ、HealthKit の権限設定、.gitignore、README)
4. `02-commands.md` のコマンドで確認
5. Codex へのレビュー依頼をまとめる
