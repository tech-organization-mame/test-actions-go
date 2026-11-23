# スクリプトの契約（テスト担当が決めた）

実装者は、この契約に従う。「仕様」は `docs/` と `schemas/`。仕様に書かれていない点は、テスト担当が決めた。決めた点は **［決定］** と書く。仕様の曖昧さは `tests/NOTES.md` に列挙した。

実行：`bash tests/run.sh [名前の部分一致]`。全件成功なら終了コード0、失敗があれば1。テストは `scripts/gate.sh` と `scripts/post.sh` を `bash <パス>` で呼ぶ（実行ビットは不要）。作業ディレクトリは、ケースごとの一時ディレクトリ。

## 1. gh スタブ（tests/stubs/gh）
- **［決定］** 2つのスクリプトが呼んでよい gh は、`gh api` だけ。`gh pr ...`、`gh issue ...`、`gh run ...` などは、スタブが「契約外」として記録し（`unsupported`）、終了コード99で失敗する。契約外の呼び出しがあると、そのケースは失敗する。
- 受け付ける形：
  - `gh api [-X|--method M] [-f|-F|--raw-field|--field key=value]... [--paginate] [-q|--jq 式] [-H|--header 値] <パス>`
  - `--method=POST` や `-fkey=value` のような連結形は不可（必ず分ける）。`--input` は不可。
  - `-F key=@ファイル` は、ファイルの内容を値にする。`-f` は、値をそのまま使う。
  - `-X` がなければ、フィールドがあるとPOST、なければGET（本物の gh と同じ）。
  - パスの先頭の `/` は、省いてもよい。
- 応答（GET）：
  - `repos/<repo>/issues/<N>/comments` → `$STUB_STATE/comments/<N>.json`（配列。なければ `[]`）。PRのコメントもIssueのコメントも同じ。要素：`{id, user:{login,type}, body, issue_url}`
  - `repos/<repo>/issues[?state=open|closed|all&...]` → `$STUB_STATE/issues.json`（配列）を `state` で絞る（既定は open）。
    - 要素：`{number, state, title, body, user:{login,type}}`。
    - **PRは含まれない**（`pull_request` は付かない）。
  - ほかのパス → `$STUB_STATE/api/<パスの / を __ に置換>.json`。なければ、404相当（標準エラーにメッセージ、終了コード1）
- 書き込み（成功すると `$STUB_STATE/writes.jsonl` に1行追記。形：`{method, path, fields}`）：
  - `POST repos/<repo>/issues/<N>/comments`（`-f body=...`）：コメントを追加。作成者は `github-actions[bot]`（環境変数 `STUB_ACTOR` で変更可）。`id` は1000から連番
  - `PATCH repos/<repo>/issues/comments/<id>`（`-f body=...`）：本文を更新
  - `POST repos/<repo>/issues`（`-f title=... -f body=...`）：Issueを追加（番号は100から連番、state は open）
  - これ以外の書き込み（`DELETE`、Issueのクローズ、ラベル、PRの作成など）は、契約外
- 失敗の注入：`STUB_FAIL_READS=1`（すべてのGETが失敗）、`STUB_FAIL_WRITES=1`（すべての書き込みが失敗。記録もされない）

## 2. scripts/gate.sh
### 2.1 入力
| 種類 | 名前 | 内容 |
|---|---|---|
| 環境変数 | `GITHUB_EVENT_PATH` | **［決定］** Actions のイベントペイロード（`{"workflow_run": {...}}`）のファイル。使う項目：`workflow_run.id`、`run_attempt`、`event`、`head_branch`、`head_sha`、`head_repository.full_name`、`pull_requests[].number`、`actor.login`、`triggering_actor.login` |
| 環境変数 | `GITHUB_REPOSITORY` | 対象のリポジトリ（`owner/name`）。`head_repository.full_name` と比べて、fork を除く |
| 環境変数 | `DEFAULT_BRANCH` | 既定 `main`。pushの対象ブランチ |
| 環境変数 | `TRIAGE_DIR` | 出力先。既定 `triage` |
| 環境変数 | `CONTROL_SHA` | context の `control_sha` に入れる。未設定なら、40桁のゼロ |
| 環境変数 | `EVIDENCE_DIR` | 既定 `evidence`。`log.txt` があれば、そのSHA-256を `evidence_sha256` に入れる。なければ、空入力のSHA-256 |
| 環境変数 | `GITHUB_OUTPUT` | あれば、`state=<値>` と `route=<値>` を1行ずつ追記する（［決定］） |

### 2.2 gh の呼び出し（`gh api` の読み取りだけ。書き込みは一切しない）
- PRの実行：`gh api repos/<GITHUB_REPOSITORY>/pulls/<N>`。使う項目：`.user.login`、`.user.type`。`.user.type == "Bot"` か、ログインが `[bot]` で終わるなら、botのPR
- mainのpush：`gh api repos/<GITHUB_REPOSITORY>/commits/<head_sha>/pulls`（配列）。使う項目：`.[].merged_at`。`merged_at` が null でない要素が1つ以上あれば、マージ済みPRあり
- 呼び出しの失敗（終了コード非0）は、「対応を確定できない」として扱う

### 2.3 判定（上から順に評価）
| 条件 | route | state |
|---|---|---|
| `event` が `pull_request` でも `push` でもない（cron、手動など） | out_of_scope | out_of_scope |
| `head_repository.full_name` が `GITHUB_REPOSITORY` と違う（fork） | out_of_scope | out_of_scope |
| `pull_request`：`pull_requests` が空（PR特定不能） | out_of_scope | out_of_scope |
| `pull_request`：PRの取得に失敗 | out_of_scope | out_of_scope |
| `pull_request`：PRの作成者がbot | out_of_scope | out_of_scope |
| `pull_request`：上記以外 | pr（`pr_number` は先頭のPR） | post_target |
| `push`：`head_branch` が `DEFAULT_BRANCH` でない | out_of_scope | out_of_scope |
| `push`：コミットのPR取得に失敗、または、マージ済みPRなし（直接push） | out_of_scope | out_of_scope |
| `push`：マージ済みPRあり | merge（`pr_number` は null） | post_target |

- **［決定→D-14で確定］** 対象外の場合、`route` と `state` は、ともに `out_of_scope`（`record_only` は、gate は決めない）。テストも、`out_of_scope` だけを許す。
- **［決定］** gate が決める `state` は、`post_target`、`out_of_scope`、`record_only` のみ。`analysis_failed` は決めない。復旧済みなどによる `record_only` への変更は、この範囲外（準備の後続）
- **［決定］** `same_sha_rerun` は `none`、`fingerprint` は `null` にする（gate は決めない）

### 2.4 出力と終了コード
- `$TRIAGE_DIR/context.json`：**常に**書く（対象外でも）。`schemas/context.schema.json` に合う。
- `mention`：`run_attempt == 1` なら `actor.login`、それ以外は `triggering_actor.login`（design 2.1）。
- **［D-14で確定］** ログインが取れない場合、`mention` の形に合わない場合、実行者が Bot の場合は、`mention` を `null` にする（スキーマは null 可）。
- 終了コード：判定できた場合は、対象外でも **0**。イベントファイルが読めないなど、判定の前の異常だけ、非0。

## 3. scripts/post.sh
### 3.1 入力
| 種類 | 名前 | 内容 |
|---|---|---|
| 環境変数 | `TRIAGE_DIR` | 既定 `triage`。`context.json`、`result.json`（任意）を読む |
| 環境変数 | `EVIDENCE_DIR` | 既定 `evidence`。`log.txt` を読む |
| 環境変数 | `TRIAGE_WORKFLOW_NAME` | ［決定］ テンプレートの `<workflow>`。未設定なら `CI`（context にワークフロー名がないため。NOTES 4） |
| 環境変数 | `GITHUB_STEP_SUMMARY` | あれば、記録を追記してよい（内容はこの範囲ではテストしない） |
| 引数 | なし | |

- 宛先（リポジトリ、PR番号）は、**`context.json` だけ**から決める。`GITHUB_REPOSITORY` や `result.json` は使わない（S-03）。
- `log.txt` の形式：**［決定］** 1行が `L<番号>: <原文>`（行IDの後ろにコロンと空白）。

### 3.2 処理の順序
1. `context.json` を、`context.schema.json` で検証する。読めない、または不正なら、書き込まずに、終了コード非0。
2. `state` が `post_target` 以外なら、書き込みゼロ、終了コード0（結果の有無によらない）。`analysis_failed` の扱いは、未決（NOTES 1）で、テストしない。
3. `result.json` を検証する。通れば、AIの結果で投稿する。次のどれかなら、定型の「調査失敗」を投稿する。
   - ファイルがない、空、JSONとして壊れている
   - `result.schema.json` に違反する。対象は、必須項目、`additionalProperties: false`、`enum`、文字数、件数、行IDの形。`category != unknown` のときに `evidence` が空の場合も違反
   - `evidence` の行IDが、`log.txt` にない（design 5）
4. `network_error` の確認：`category == "network_error"` のとき、`evidence` が指す行を見る。
   - 典型的なメッセージは、`i/o timeout`、`connection reset`、`TLS handshake timeout`（**［決定］** 大文字小文字は区別しない）。
   - いずれかの行が含めば、そのまま投稿する。
   - どの行も含まなければ、`suspected_cause` を「不明」に置き換えて投稿する。定型の「調査失敗」にはしない。
5. 無害化（3.5）して、本文を作る。
6. 投稿先で重複を判定して、書き込む（3.3、3.4）。

### 3.3 route が pr の場合
1. `gh api repos/<repo>/issues/<pr_number>/comments --paginate` で、コメントを読む。
2. **処理済み候補**：次の3つがそろう（R-21、D-12）。
   1. 作成者（`.user.login`）が `github-actions[bot]`
   2. 対象が、context のPR（`.issue_url` があれば、末尾が `/issues/<pr_number>`。ないときは、満たすとみなす）
   3. 本文の**1行目**が、`<!-- triage:run-<R>-attempt-<A>` + ` -->`（完全一致）の形（**［決定］** マーカーは本文の1行目にだけ置く）。`R` と `A` を整数として比べる（前方一致は不可）
3. 書き込み：
   - 候補に、`R == run_id` かつ `A == run_attempt` があれば、**書き込みゼロ**
   - なければ、`R == run_id` かつ `A < run_attempt` の候補から、`A` が最大のものを選ぶ。`PATCH repos/<repo>/issues/comments/<id>`（`-f body=...`）で更新し、新規は作らない
   - なければ、`POST repos/<repo>/issues/<pr_number>/comments`（`-f body=...`）で作成する
   - **［D-16で確定］** 同じrunの、同じattempt、または、より後のattemptの候補があれば、書き込みゼロ（1 → 2 → 1 で、別コメントを作らない）。
4. 通常の投稿と定型の投稿は、同じマーカーを使う。先に書かれた方があれば、もう一方は、書き込みゼロ（R-09）。

### 3.4 route が merge の場合
1. `gh api "repos/<repo>/issues?state=open" --paginate` を読む（**［決定］** `state=open` を指定する）。`pull_request` を持つ要素は除く。
2. **［D-16で確定］** 追記先は、`state == open` で、作成者が `github-actions[bot]`、本文の**2行目**が `<!-- triage-fingerprint:<context.fingerprint> -->` のIssue。複数あれば、番号が最小のもの。第三者のIssueは、追記先にも、抑制の根拠にもならない。
3. 追記先がなければ、`POST repos/<repo>/issues`（`-f title=... -f body=...`）で作成する。
   - `title`：`mainのCIが失敗しています（自動）`（［決定］ 全体がこの文字列。少なくとも含む）
   - `body`：1行目がマーカー、2行目が `<!-- triage-fingerprint:<fingerprint> -->`、3行目以降がテンプレートの本文（見出しの行を除いてよい）
4. 追記先があれば、次の順に確認する。
   - 追記先の `.body` の1行目に、同じ `run_id` と `attempt` のマーカーがあれば、**書き込みゼロ**。
   - `gh api repos/<repo>/issues/<番号>/comments` で、`github-actions[bot]` が書いたコメントの1行目を見る。同じマーカーがあれば、**書き込みゼロ**。
   - どちらもなければ、`POST repos/<repo>/issues/<番号>/comments`（`-f body=...`）で追記する。追記コメントの1行目は、マーカー。
5. `fingerprint` が null の場合は、未定義（NOTES 8）。テストしない。

### 3.5 本文（テンプレート。design 7 に準拠）
```
<!-- triage:run-<run_id>-attempt-<n> -->
## CI失敗の調査結果（自動）

- 対象：`<workflow>`ワークフロー（run #<run_id>、attempt <n>、コミット`<sha7>`）
- 要約：<summary>
- 原因の仮説：<suspected_cause>
- 根拠：
  - <行ID>：<ログの原文から組み立てた引用>
- 次の対応：<next_steps>

※ AIによる推測です。原因を断定するものではありません。
@<mention>
```
- テストが見る点：
  - 1行目が、マーカーと完全に一致する。
  - `## CI失敗の調査結果（自動）` の行がある。
  - `run #<run_id>`、`attempt <n>`、`<sha7>`（`head_sha` の先頭7桁）を含む。
  - `- 要約：<summary>` と `- 原因の仮説：<suspected_cause>` の行がある。
  - `next_steps` の文字列がある。
  - `evidence` の各行IDと、`log.txt` の原文がある。
  - 固定文 `※ AIによる推測です。原因を断定するものではありません。` がある。
  - 末尾の空でない行は、`@<context.mention>` だけ（**［決定］**）。本文の `@` は、この1つだけ。
- 根拠の引用は、`log.txt` の原文から組み立てる（`result.json` に引用はない）。行の並びは `evidence` の順。
- 定型の「調査失敗」の構成：
  - 1行目は、通常と同じマーカー。
  - `## CI失敗の調査結果（自動）` と、通常と同じ `- 対象：...` の行。
  - `- 結果：調査失敗` で始まる行（**［決定］** 「調査失敗」の語を含めばよい）。
  - 末尾は `@<mention>`。`※ AIによる推測です。...` は不要。
  - AIの文面（要約、仮説など）は、一切入れない。
- 無害化（V-01、S-04）。**［決定］** AIの文字列（`summary`、`suspected_cause`、`next_steps`）と、ログから組み立てた引用の**両方**に、次を適用する。
  - `@` は、1文字ずつ削除する（`@foo` → `foo`）
  - 画像 `![alt](url)` は、全体を削除する。リンク `[text](url)` は、`text` だけ残す。URL（`http://`、`https://` で始まるもの）は、削除する
  - HTMLタグ（`<` で始まり英字、`/`、`!` が続くもの。コメント `<!-- ... -->` を含む）は、削除する。タグの中身（`<script>` の間のテキスト）を残すかは、実装者が決めてよい
  - 偽のマーカー（`<!-- triage:...-->`）は、HTMLコメントとして削除される。本文に `<!-- triage:` が現れるのは、1行目の1つだけ
  - 文字数の上限は、スキーマの `maxLength` による（超えたら、検証の失敗）。引用の長さの上限は、実装者が決める（テストしない）

### 3.6 stdout
自由。テストは見ない。

### 3.7 失敗時（**［決定］**）
- gh の書き込みが失敗したら、終了コード非0。
- 重複の判定のための読み取りが失敗したら、書き込まずに、終了コード非0（判定できないまま書くと、重複する恐れがあるため）。
- 非0の場合も、すでに成功した書き込みは、取り消さない。

## 4. ケースと仕様IDの対応
`tests/cases/gate.sh`（18件）、`tests/cases/post.sh`（39件）。各ケースの上のコメントに `spec:` で書いてある。要約は、最終報告にある。

## 5. 範囲外（このテストでは見ない）
- 復旧の再確認（R-14、F-09）。
- メンション選択の詳細（R-17）と、ジョブサマリーの内容（R-18）。
- `concurrency`（F-13）と、ハッシュ照合（S-07）。
- 行IDの付与とフィンガープリントの計算（準備のスクリプトの仕事）。
