# Ruby 脆弱性(2026年10月)の対策検討: Codex への依頼と回答

実施日: 2026-10-30。`codex exec -s read-only -c model_reasoning_effort=medium -c web_search=live` で実行。HealthCare 自体に Ruby 依存はなく、端末環境と他の Ruby プロジェクトの対策検討。

## 依頼文(Claude Code 作成)

# 依頼: Ruby 脆弱性(2026年10月)への対策検討

あなたは検証担当(Codex)です。コードやファイルは書き換えず、検討結果だけを書いてください。
Web 検索が使える場合は、下の情報を自分でも一次情報で裏取りし、私(Claude Code)が見落としている点を補ってください。
検索できない場合は「検索未実施」と明記したうえで、与えられた情報の範囲で検討してください。

## 背景(Claude Code が 2026-10-30 に収集した情報)

### ニュース
- 山陰中央新報(10/28, 10/29、有料記事で冒頭のみ確認): 「松江発の Ruby、PHP 同様に脆弱性排除できず、AI 発展で高リスク、迅速な対応必要」「過去にも発見、対処。迅速対応へ体制づくり重要」。PHP の重大脆弱性を受けた注意喚起記事で、具体的な CVE や版の記載は確認できていない。
- PHP(10/21 公表): CVE-2026-109618 / CVE-2026-109619(通称 PHP2Shell)。認証なし RCE、CVSS 4.0 で 9.2。原因はリクエスト処理のメモリ管理(OOM 時の初期化中断、解放後に残る内部状態)。影響は mod_php, PHP-FPM, php-cgi, FrankenPHP, LiteSpeed。修正版 8.5.12 / 8.4.27 / 8.3.36 / 8.2.35。正規表現とは無関係。
- Ruby(10/23 公表、公式: https://www.ruby-lang.org/en/news/2026/10/23/regexp-fixes-for-gitlab-cves/):
  正規表現エンジン Onigmo のコンパイル時メモリ破壊。GitLab が CVE を割り当てた 4 件。
  | 欠陥 | CVE | 4.0系 | 3.4系 | 3.3系 |
  | 選択の解析失敗後の二重解放 | CVE-2026-89078 (9.9) | 4.0.0 | 3.4.12 | 3.3.13 |
  | パターンサイズの整数オーバーフロー | CVE-2026-93577 (9.9), CVE-2026-97229 (10.0) | 4.0.8 | 3.4.12 | 3.3.13 |
  | 繰り返しによる内部 ID のオーバーフロー | CVE-2026-110264 (10.0) | 4.0.9 | 3.4.12 | 3.3.13 |
  - 条件: 攻撃者が制御できる文字列から正規表現を作る場合のみ(Regexp.new / Regexp.union / Regexp.compile / /#{input}/)。固定の正規表現だけなら影響なし。
  - Regexp.timeout とパターン長制限は防御にならない(公式明記)。
  - Ruby 3.2 以前は 2026-03-31 で EOL、修正なし。
  - Ruby 側は自前の CVE を申請していない。GitLab の CVE 番号で追跡するよう案内。
  - CVE-2026-97229 は Rapid7 の PoC が公開済み。Alpine Linux の GitLab が 10/20-21 に攻撃を受け、環境を全面再構築(https://alpinelinux.org/posts/GitLab-security-incident-CVE-2026-97229.html)。
- 8月の resolv gem の脆弱性(CVE-2026-80212 / CVE-2026-80213、https://www.ruby-lang.org/en/news/2026/08/27/multiple-vulnerabilities-in-resolv/)も未対応の可能性がある。

### この端末(macOS, Apple Silicon)の状況
| 場所 | バージョン | 状態 |
| rbenv(グローバル、~/.ruby-version) | 3.4.7 | 上の 3 件とも未修正 |
| rbenv | 3.2.2, 3.2.4 | EOL、修正版なし |
| macOS 付属 /usr/bin/ruby | 2.6.10 | Apple 管理 |
- 3.4.7 同梱の resolv は 0.6.2(default gem)。3.4 系の修正版番号は未確認。
- gem list には rails 8.x 系、aws-sdk 系など多数の gem が入っている(開発用途)。
- カレントの HealthCare リポジトリ(Swift / SwiftUI の iOS アプリ、XcodeGen 使用)には Gemfile / Podfile / fastlane がなく Ruby 依存なし。XcodeGen は Homebrew のバイナリ。
- ~/dev 配下で Ruby を使うのは ~/dev/jekyll/yomishirube-doc(Jekyll の静的サイト)だけ。外部からの入力を受けるサーバーは動かしていない(想定)。

## 検討してほしいこと
1. 上の情報に誤り・古い点・抜けがないか(特に: 3.4 系の resolv 修正版、他に 2026 年に出た Ruby 本体・default gem・bundled gem の脆弱性で 3.4.7 に未適用のもの、Rails 8.x 側で同時期に出た脆弱性)。
2. この端末で現実的に取るべき対策の優先順位と具体案。例: rbenv に 3.4.12 を導入してグローバルを切り替える / 3.2 系を削除する / Jekyll プロジェクトの .ruby-version と Gemfile.lock の扱い / gem の更新(bundler-audit 等の利用可否)/ Homebrew の ruby-build 更新が必要か。
3. 「やらなくてよいこと」も明記してほしい(開発端末で外部入力を受けないなら過剰対応になるもの)。
4. 山陰中央新報の記事が言う「AI 発展で高リスク」「迅速対応の体制づくり」について、個人開発者として現実的に取り入れられる習慣があれば提案してほしい(例: 公式 security アナウンスの購読、定期的なバージョン確認の仕組み)。
5. 今後 Ruby を使うプロジェクトで Regexp を外部入力から作っていないか確認する方法(grep パターンなど)。

## 出力形式
- 見出しごとに箇条書き。断定できないことは「未確認」と書く。
- 検索で裏取りした項目には出典 URL を付ける。
- 最後に「推奨する手順(順番つき)」と「人間に判断してもらう点」をまとめる。


## Codex の回答(原文)

調査日: 2026-10-30。Web検索を実施し、Ruby・Rails・GitLab・Alpine Linux・Rapid7の一次情報を確認しました。ファイル変更はしていません。

## 結論

- 優先度「高」: rbenv のグローバル Ruby 3.4.7 は、正規表現の4 CVEに加えて、`resolv`・`zlib`・デフォルトの `erb` も脆弱な版です。Ruby 3.4.12への更新で、確認できた2026年のRuby 3.4系対象問題をまとめて解消できます。
- 優先度「高」: 現在の `ruby-build` は `20251225` で、3.4.12の定義がありません。先にHomebrewで `ruby-build` を更新する必要があります。
- 優先度「中」: Jekyllプロジェクトは [.ruby-version](/Users/tsuyoshi/dev/jekyll/yomishirube-doc/.ruby-version:1) が3.4.7固定です。グローバル変更だけでは不十分で、ここも3.4.12へ更新する必要があります。
- 優先度「中」: Rails 8.xの古い版が3.4.7のgem領域に複数あります。現在のプロジェクトからは使われていませんが、Rails 8.1.3も2026年7月のActive Storage脆弱性の影響範囲です。
- HealthCareリポジトリにはRuby依存がないため、HealthCare自体への修正は不要です。

## 情報の訂正・補足

- 正規表現問題

  - Ruby 3.4.12、3.3.13、4.0.9が4件すべての修正版です。外部入力から正規表現をコンパイルする場合に到達し、`Regexp.timeout` や単純な長さ制限では防げません。[Ruby公式](https://www.ruby-lang.org/en/news/2026/10/23/regexp-fixes-for-gitlab-cves/)
  - CVE-2026-89078とCVE-2026-93577の9.9は、GitLabが示す **CVSS 3.1** の値です。CVSS 4.0ではありません。[GitLab公式](https://docs.gitlab.com/releases/patches/patch-release-gitlab-19-4-1-released/)
  - Alpine Linuxで起きたのは「侵害成功が確認された事件」ではなく、実際の悪用試行があり、成功を排除できなかったためGitLabインスタンスを再構築した事件です。Alpine全環境の全面再構築ではありません。[Alpine Linux公式](https://alpinelinux.org/posts/GitLab-security-incident-CVE-2026-97229.html)
  - Rapid7は実行可能なエンドツーエンドPoCを公開・検証しています。[Rapid7](https://www.rapid7.com/blog/post/ra-gitlab-ci-cd-regex-integer-overflow-technical-analysis-cve-2026-97229/)

- `resolv`

  - 3.4系の修正版は **0.7.2** です。Ruby 3.4.12にも0.7.2が入っています。[Ruby公式アドバイザリ](https://www.ruby-lang.org/en/news/2026/08/27/multiple-vulnerabilities-in-resolv/)、[Ruby 3.4.12ソース](https://raw.githubusercontent.com/ruby/ruby/v3_4_12/lib/resolv.rb)
  - 現在の3.4.7は `resolv 0.6.2` で、影響範囲 `0.4.0〜0.7.1` に該当します。
  - ただし、影響するのは `Resolv`、`resolv-replace`、またはそれを使う依存ライブラリです。通常の `Net::HTTP`/`TCPSocket` の名前解決は直接の影響対象ではありません。

- 2026年の追加のRuby/default gem脆弱性

  - **CVE-2026-27820 / zlib**: 現在の `zlib 3.2.1` は影響範囲 `3.2.2以下`。修正版は3.2.3で、Ruby 3.4.12に3.2.3が含まれます。[Ruby公式](https://www.ruby-lang.org/en/news/2026/03/05/buffer-overflow-zlib-cve-2026-27820/)、[3.4.12ソース](https://raw.githubusercontent.com/ruby/ruby/v3_4_12/ext/zlib/zlib.c)
  - **CVE-2026-41316 / erb**: `Marshal.load` に信頼できないデータを渡し、ERBとActiveSupportがロードされている場合のRCEです。3.4.7のデフォルト `erb 4.0.4` は未修正ですが、端末には修正版 `erb 6.0.4` も追加インストールされています。どちらが選択されるかはbundleやgem activation次第なので、デフォルト版も直る3.4.12への更新が確実です。[Ruby公式](https://www.ruby-lang.org/en/news/2026/04/21/erb-cve-2026-41316/)、[3.4.12ソース](https://raw.githubusercontent.com/ruby/ruby/v3_4_12/lib/erb/version.rb)
  - **CVE-2026-46727 / getaddrinfo**: Ruby 4.0.0〜4.0.4のみで、Ruby 3.4以前は影響なしです。[Ruby公式](https://www.ruby-lang.org/en/news/2026/05/20/getaddrinfo-cve-2026-46727/)
  - Ruby公式の2026年Known Issuesで確認できる範囲では以上です。[Ruby Security](https://www.ruby-lang.org/en/security/)
  - RubyGems全体を含む完全な網羅性は未確認です。Ruby Advisory Databaseは継続更新されるため、各プロジェクトの `Gemfile.lock` に対して別途監査が必要です。

- Ruby 3.2のEOL日

  - 背景情報の「2026-03-31」と公式ページには1日の差があります。現在の公式表示は **2026-04-01 EOL** です。実務上はいずれにしてもEOLです。[Ruby Maintenance Branches](https://www.ruby-lang.org/en/downloads/branches/)

## Rails 8.xの状況

- 2026年3月にはAction Pack、Action View、Active Support、Active Storageについて多数の脆弱性が公表されています。主な修正版境界は以下です。

  - Rails 8.1系: 8.1.2.1
  - Rails 8.0系: 8.0.4.1
  - Rails 7.2系: 7.2.3.1
  - 内容はXSS、ReDoS/DoS、Active Storageのパストラバーサル、glob injection、Range処理などです。[Rails Security Announcements](https://discuss.rubyonrails.org/c/security-announcements/9)

- 2026年7月の **CVE-2026-66066** は、libvipsによるActive Storage画像処理から任意ファイル読み取り、秘密情報漏えい、条件次第でRCEにつながる重大問題です。

  - 8.1系修正版: 8.1.3.1
  - 8.0系修正版: 8.0.5.1
  - 7.2系修正版: 7.2.3.2
  - 端末の `activestorage 8.1.3`、8.1.1、8.0.4はいずれも影響範囲です。[Rails公式アナウンス](https://discuss.rubyonrails.org/t/cve-2026-66066-possible-arbitrary-file-read-and-remote-code-execution-in-active-storage-variant-processing/91432)

- `rails-html-sanitizer`

  - 1.7.1未満に、SVGの `<use>` 等を独自許可している場合のXSSがあります。デフォルト設定は影響しません。
  - 端末には修正版1.7.1と、未修正版1.7.0/1.6.2が併存しています。[Rails公式アナウンス](https://discuss.rubyonrails.org/t/ghsa-cj75-f6xr-r4g7-possible-xss-vulnerability-with-certain-configurations-of-rails-html-sanitizer/91359)

- 2026-10-29にはTrilogyのSQL injectionも公表されていますが、この端末に `trilogy` gemは見つかりませんでした。[Rails公式フォーラム](https://discuss.rubyonrails.org/t/ghsa-744p-w4gc-m3gh-sql-injection-through-trilogy-escape-with-multibyte-encodings/91797)

- これらのRails gemは3.4.7固有のgem領域にあります。Railsサーバーを動かしておらず、HealthCare/JekyllのbundleにもRailsがないため、現時点の実害可能性は低いです。ただし `rails` コマンドを直接使うと最新インストール版8.1.3が選ばれる可能性があります。

## Jekyllプロジェクト

- [.ruby-version](/Users/tsuyoshi/dev/jekyll/yomishirube-doc/.ruby-version:1) は3.4.7です。
- [Gemfile.lock](/Users/tsuyoshi/dev/jekyll/yomishirube-doc/Gemfile.lock:309) はBundler 4.0.14で生成されています。Ruby更新後も同じBundlerを入れて使うのが安全です。
- `Gemfile.lock` にはRails、Active Storage、`resolv`、`zlib`、`erb` は記録されていません。後三者はRubyのデフォルトgemなので、ロックファイルだけでは管理されません。
- 独自Rubyコードについて、`Regexp.new`、`Regexp.compile`、`Regexp.union`、補間された正規表現、`Marshal.load`、`Resolv` の明示利用は見つかりませんでした。
- `vendor/bundle` 内の全依存ソースについてのデータフロー監査は未確認です。
- `bundler-audit 0.9.3` はインストール済みですが、ローカルのアドバイザリDBがなく、今回は「書き換えない」という条件と読み取り専用環境のため `--update` を実行していません。監査結果は未確認です。
- `bundler-audit` は `Gemfile.lock` 内のgemを検査するツールです。Ruby本体や、ロックされていないデフォルトgemの確認を完全には代替しません。[bundler-audit公式](https://github.com/rubysec/bundler-audit)

## 現実的な対策

- Ruby 3.4.12を採用するのが最小変更です。Ruby 4.0へのメジャー更新は不要です。
- 現在の `ruby-build 20251225` は古く、Homebrew上の現行は `20261023` です。3.4.12を入れる前に更新が必要です。
- 新しいRubyには3.4.7の通常gem領域が引き継がれないため、必要なgemだけを再導入できます。Railsを使っていないなら再インストールしない方が管理対象を減らせます。
- Jekyllでは、Rubyだけを先に更新し、最初は `bundle update` をしないことを推奨します。

  - `.ruby-version` を3.4.12へ変更
  - Bundler 4.0.14を新しいRubyへインストール
  - `bundle check`
  - 必要な場合だけ `bundle install`
  - `bundle exec jekyll build`
  - `bundle-audit check --update`
  - 監査で指摘されたgemだけを個別更新

- `Gemfile.lock` は、Rubyパッチ更新だけを理由に全面更新する必要はありません。Bundlerが意図せず書き換えた場合は、差分を確認してから採用してください。
- Ruby 3.2.2/3.2.4はEOLです。`~/dev` 内では参照する `.ruby-version` は見つかりませんでしたが、ホーム全体・過去スクリプト・CI設定は未確認です。確認後に削除するのが妥当です。
- 3.4.7も、Jekyll移行と動作確認後に削除すれば、古いRails gem群もまとめて除去できます。

## やらなくてよいこと

- HealthCareリポジトリのSwiftコード、`project.yml`、Xcode設定を変更する必要はありません。
- macOSの `/usr/bin/ruby` を手動で削除・置換する必要はありません。Apple管理対象なので、macOSアップデートに任せ、開発ではrbenv Rubyを使います。
- ローカル開発端末を侵害済みとみなして全面再構築する必要はありません。今回確認した範囲では、脆弱なRubyで外部向けサービスを動かした証拠はありません。
- WAF、IDS、正規表現の全面禁止などの運用は不要です。
- `Regexp.timeout` や入力長制限を今回のメモリ破壊への対策として追加する必要はありません。公式に不十分とされています。
- 使っていないRails gemを、古いRuby環境の中で一つずつ更新する必要はありません。3.4.7環境ごと退役させる方が単純です。
- Ruby 3.4.12を使うなら、CVE対応だけのためにJekyllのGemfileへ `resolv`、`zlib`、`erb` を追加固定する必要はありません。
- `bundle update` による全依存の一括更新は、今回のRuby本体対策とは分離した方が安全です。

## 正規表現を外部入力から作っていないか確認する方法

- まず、明示的なコンパイル箇所を検索します。

```sh
rg -n --glob '*.rb' --glob '*.rake' --glob 'Rakefile' \
  'Regexp\.(new|compile|union)' .
```

- 補間された正規表現候補を検索します。誤検出・見逃しはあるため、目視確認が必要です。

```sh
rg -n --glob '*.rb' '#\{' .
rg -n --glob '*.rb' '(%r.|/.*)#\{' .
```

- 文字列から暗黙に正規表現化される可能性がある呼び出しも確認します。

```sh
rg -n --glob '*.rb' \
  '\.(match|match\?|scan|split|sub|gsub)\(' .
```

- 外部入力の入口を検索し、上記のsinkまで値が流れていないか追跡します。

```sh
rg -n --glob '*.rb' \
  '(params\[|request\.|ARGV|STDIN|ENV\[|YAML\.|JSON\.|File\.read|front.?matter)' .
```

- 判定上の注意:

  - 問題なのは単に `Regexp.new` があることではなく、その引数にHTTP入力、CLI引数、環境変数、外部ファイル、投稿内容などが流れることです。
  - `Regexp.escape(input)` を使って「文字列として検索」する設計と、利用者に正規表現そのものを入力させる設計は分けて扱います。
  - 正規表現自体を利用者に指定させる必要がある場合でも、今回の欠陥については入力検証だけに依存せず、修正版Rubyが必須です。
  - grepは候補抽出にすぎず、変数を経由するデータフローは目視または静的解析が必要です。

## 「AI発展で高リスク」への評価と習慣

- 山陰中央新報の有料記事本文は未確認のため、「AIが今回の攻撃を直接可能にした」という趣旨かどうかは未確認です。
- 一次情報で確認できる事実は、修正公開後まもなく実用PoCが出て、AlpineのGitLabに実際の悪用試行があったことです。AI関与そのものは確認できません。
- 個人開発者には、AI対策というより「公開から悪用までが短い前提」の運用が現実的です。

  - [Ruby News RSS](https://www.ruby-lang.org/en/feeds/news.rss)を購読する。
  - [Rails Security Announcements](https://discuss.rubyonrails.org/c/security-announcements/9)を購読する。Rails公式もこれを最善の通知経路と案内しています。[Rails Security Policy](https://rubyonrails.org/security)
  - 月1回、またはプロジェクトを再開するときに `ruby -v`、`.ruby-version`、`bundle-audit check --update` を確認する。
  - 外部公開サービスではCritical/RCEを通常更新日まで待たず、原則24〜48時間以内に評価する。
  - Ruby本体、Bundler、`Gemfile.lock`、実際の実行環境を別々の資産として管理する。
  - GitHub等に置くプロジェクトでは、可能ならDependabot/Renovateを週次で有効化する。ただしRuby本体の更新は `.ruby-version` 用の設定が別途必要です。
  - 更新後に `ruby -v` とdefault gem版を実行環境で再確認する。Alpine事件では、GitLabだけ更新して基盤Rubyのパッチが入らなかったことが問題になりました。

## 推奨する手順（順番つき）

1. `brew update` と `brew upgrade ruby-build` を行い、`ruby-build 20261023` 以降にする。
2. `rbenv install 3.4.12` を実行する。
3. `rbenv global 3.4.12`、`rbenv rehash` を実行し、`ruby -v` で確認する。
4. 次を確認し、期待値が `resolv 0.7.2`、`zlib 3.2.3`、`erb 4.0.4.1` 以上であることを確認する。

```sh
ruby -e 'puts %w[resolv zlib erb].map { |n|
  "#{n} #{Gem::Specification.find_by_name(n).version}"
}'
```

5. 新しいRubyへBundler 4.0.14を入れる。
6. Jekyllの `.ruby-version` を3.4.12へ変更する。
7. Jekyllで `bundle check`、必要なら `bundle install`、続いて `bundle exec jekyll build` を実行する。
8. Jekyllで `bundle-audit check --update` を実行し、結果を個別評価する。
9. Jekyllの独自コードに対して上記の正規表現grepを実行する。現時点では該当なしですが、外部コンテンツの流入経路も確認する。
10. 問題がなければ3.4.7を退役させる。3.2.2/3.2.4も他の場所から参照されていないことを確認後に削除する。
11. Ruby公式RSSとRails Security Announcementsを購読し、月次の依存確認を予定化する。

## 人間に判断してもらう点

- EOLのRuby 3.2系と3.4.7を完全削除するか、過去案件用に一時保持するか。
- グローバルにRailsを残す必要があるか。不要なら新しい3.4.12へは再インストールしないことを推奨します。
- Jekyllの入力が自分で管理する文書だけか、外部PR・ダウンロードデータなど信頼できない内容もローカルまたはCIでビルドするか。後者なら脅威度が上がります。
- Dependabot/Renovateなどを導入するか、月次の手動 `bundler-audit` で運用するか。
- `.ruby-version` 更新とJekyllビルド検証を、別の小さな作業単位として実施・コミットするか。
