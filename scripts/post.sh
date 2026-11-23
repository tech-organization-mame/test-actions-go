#!/usr/bin/env bash
# 投稿スクリプト（構成③の③。docs/design.md 3〜5、7）。AIの終了後に、通常のステップとして実行する。
# 契約：tests/CONTRACT.md 第3節。宛先は context.json だけから決める。gh は gh api だけを使う。
# 注意：未検証のたたき台。
set -u
set -o pipefail

# Windows の jq は、出力の改行を CRLF にする。-b（--binary）で、変換しない（Linux では、何も変わらない）。
# 本文のデータの CR は、取り除かない（無害化の前に、制御文字として処理する）
jq() { command jq -b "$@"; }

TRIAGE_DIR=${TRIAGE_DIR:-triage}
EVIDENCE_DIR=${EVIDENCE_DIR:-evidence}
WORKFLOW_NAME=${TRIAGE_WORKFLOW_NAME:-CI}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BOT_LOGIN="github-actions[bot]"
CTX="$TRIAGE_DIR/context.json"
RES="$TRIAGE_DIR/result.json"
LOG="$EVIDENCE_DIR/log.txt"

die() { echo "post: $*" >&2; exit 1; }
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; return 0; }

# ---- 1. context の検証 ----
[ -r "$CTX" ] || die "context.json が読めない"
# JSON 文書が、ちょうど1つであること（複数の文書は、検証を通さない）
single_doc() { [ "$(command jq -c . "$1" 2> /dev/null | wc -l | tr -d ' ')" = 1 ]; }
single_doc "$CTX" || die "context.json が、単一のJSON文書でない"
jq -e -f "$HERE/lib/context_valid.jq" "$CTX" > /dev/null 2>&1 || die "context.json が、スキーマに合わない"

cx() { jq -r "$1" "$CTX"; }
STATE=$(cx .state)
if [ "$STATE" != "post_target" ]; then
  summary "triage: 投稿しない（state=$STATE）"
  echo "post: state=$STATE のため、投稿しない"
  exit 0
fi
REPO=$(cx .repository); ROUTE=$(cx .route); RUN_ID=$(cx .run_id); ATTEMPT=$(cx .run_attempt)
SHA7=$(cx '.head_sha[0:7]'); PR=$(cx '.pr_number // empty'); FP=$(cx '.fingerprint // empty')
MENTION=$(cx '.mention // empty')
MARKER="<!-- triage:run-${RUN_ID}-attempt-${ATTEMPT} -->"

# ---- 行ID付きのログ（L<n>: 原文）を、連想配列にする ----
LOGMAP='{}'
if [ -r "$LOG" ]; then
  LOGMAP=$(sed 's/\r$//' "$LOG" | jq -Rn '[inputs | capture("^L(?<n>[0-9]+): (?<t>.*)$")?] | map({key: ("L" + .n), value: .t}) | from_entries')
fi

# ---- 3. result の検証（スキーマ、行IDの存在）----
VALID_RES='
  def nonempty($max): type == "string" and length >= 1 and length <= $max;
  (type == "object")
  and (((keys) - ["category","summary","suspected_cause","evidence","next_steps"]) | length == 0)
  and (["category","summary","suspected_cause","evidence","next_steps"] | all(. as $k | $r | has($k)))
  and (.category | IN("test_failure","build_error","lint","dependency","network_error","config","timeout","unknown"))
  and (.summary | nonempty(200))
  and (.suspected_cause | nonempty(400))
  and (.evidence | type == "array" and length <= 10 and (unique | length) == length
       and all(.[]; type == "string" and test("^L[1-9][0-9]*$")))
  and (.next_steps | type == "array" and length >= 1 and length <= 3 and all(.[]; nonempty(200)))
  and (.category == "unknown" or (.evidence | length) >= 1)
  and (.evidence | all(.[]; . as $id | $map | has($id)))
'
RESULT_OK=0
if [ -s "$RES" ] && single_doc "$RES"; then
  if jq -e --argjson map "$LOGMAP" ". as \$r | $VALID_RES" "$RES" > /dev/null 2>&1; then RESULT_OK=1; fi
fi

# ---- 無害化（AIが書く欄に適用。ログからの引用は、無害化せず、コードブロックに入れる）----
# 方針（D-18）：AIの欄とログの引用は、プレーンテキストとして扱う。リンク、画像、HTML、メンションは作らせない。
# 角括弧を全角にすれば、リンクも画像も（参照形式も）構文として成立しない。#123やコミットSHAの自動リンクは、許容する。
SAN='def san1:
  gsub("[\\x00-\\x1f\\x7f]+"; " ")
  | gsub("<!--[\\s\\S]*?-->"; "")
  | gsub("<[A-Za-z/!][^>]*(>|$)"; "")
  | gsub("https?://[^\\s)>\\]]*"; "")
  | gsub("www\\.[^\\s)>\\]]*"; ""; "i")
  | gsub("@"; "")
  | gsub("[\\[]"; "［") | gsub("[\\]]"; "］");
def san: . as $x | ($x | san1) | if . == $x then . else san end;'

# ---- 本文を作る（テンプレートは、templates/ のファイル。D-15）----
TEMPLATE_DIR=${TRIAGE_TEMPLATE_DIR:-$HERE/../templates}
MENTION_LINE=""
[ -n "$MENTION" ] && MENTION_LINE="@$MENTION"
FPLINE=""
[ -n "$FP" ] && FPLINE="<!-- triage-fingerprint:${FP} -->"

# render <テンプレート名> <変数のJSON>：{{名前}}を、1回の走査で置き換える（挿入した文字列は、再度は置換しない）
render() {
  [ -r "$TEMPLATE_DIR/$1" ] || die "テンプレートが読めない: $1"
  jq -Rrs --argjson v "$2" 'gsub("\\{\\{(?<k>[a-z0-9_]+)\\}\\}"; .k as $k | if ($v | has($k)) then $v[$k] else error("未知の変数: " + $k) end)' "$TEMPLATE_DIR/$1" || die "テンプレートを展開できない: $1"
}
BASE_VARS=$(jq -n --arg marker "$MARKER" --arg wf "$WORKFLOW_NAME" --arg run "$RUN_ID" --arg att "$ATTEMPT" --arg sha7 "$SHA7" --arg mention "$MENTION_LINE" --arg fp "$FPLINE" '{marker: $marker, workflow: $wf, run_id: $run, attempt: $att, sha7: $sha7, mention_line: $mention, fingerprint_line: $fp}')

if [ "$RESULT_OK" = 1 ]; then
  CAT=$(jq -r .category "$RES")
  NETFLAG=ok
  if [ "$CAT" = "network_error" ]; then
    # 典型的なメッセージが、根拠の行にあるか（大文字小文字は区別しない）
    if ! jq -e --argjson map "$LOGMAP" '[.evidence[] | $map[.] | ascii_downcase]
         | any(.[]; test("i/o timeout|connection reset|tls handshake timeout"))' "$RES" > /dev/null 2>&1; then
      NETFLAG=unverified
    fi
  fi
  VARS=$(jq -c --argjson base "$BASE_VARS" --argjson map "$LOGMAP" --arg flag "$NETFLAG" "$SAN"'
    $base + {
      summary: (.summary | san),
      cause: (if $flag == "unverified" then "不明（ネットワークエラーと断定できる根拠が、ログにない）" else (.suspected_cause | san) end),
      next_steps: ([.next_steps[] | "  - " + (. | san)] | join("\n")),
      evidence: (
        [.evidence[] | . + ": " + ($map[.] | gsub("[\\x00-\\x1f\\x7f]+"; " "))] as $ls
        | ([$ls[] | [match("`+"; "g").length] | max // 0] | max // 0) as $m
        | ([range([$m + 1, 3] | max) | "`"] | join("")) as $f
        | $f + "\n" + ($ls | join("\n")) + "\n" + $f)
    }' "$RES") || die "変数を作れない"
  BODY=$(render pr-comment.md "$VARS") || die "本文を作れない"
  ISSUE_BODY=""
  if [ "$ROUTE" = "merge" ]; then ISSUE_BODY=$(render issue.md "$VARS") || die "本文を作れない"; fi
  KIND=result
else
  VARS=$(printf '%s' "$BASE_VARS" | jq -c '. + {reason: "調査の結果が得られない、または、検証に失敗した"}')
  BODY=$(render failed.md "$VARS") || die "本文を作れない"
  ISSUE_BODY=$(printf '%s\n%s\n%s\n' "$MARKER" "$FPLINE" "$(printf '%s\n' "$BODY" | sed '1d')")
  KIND=fallback
fi

# ---- gh api（読み取りは paginate の出力を、1つの配列にまとめる）----
# 各ページが配列であること。そうでなければ、失敗にする
gh_list() { gh api "$@" --paginate | jq -s 'if all(.[]; type == "array") then (add // []) else error("配列でないページ") end'; }
marker_run() { # 本文の1行目が、マーカーの形か。形なら "run attempt" を出す
  printf '%s' "$1" | sed 's/\r$//' | head -n 1 | sed -n 's/^<!-- triage:run-\([0-9][0-9]*\)-attempt-\([0-9][0-9]*\) -->$/\1 \2/p'
}
MARKER_FILTER='[.[] | . as $c | ((.body // "") | split("\n")[0] | sub("\r$"; "")
  | capture("^<!-- triage:run-(?<r>[0-9]+)-attempt-(?<a>[0-9]+) -->$")?) as $m
  | select($m != null) | {id: $c.id, r: ($m.r | tonumber), a: ($m.a | tonumber)}]'
gh_write() { gh api "$@" > /dev/null || die "書き込みに失敗した"; }

if [ "$ROUTE" = "pr" ]; then
  COMMENTS=$(gh_list "repos/$REPO/issues/$PR/comments") || die "コメントを読めない"
  # 処理済み候補：作成者、対象、マーカー（1行目）の3つがそろう
  CANDS=$(printf '%s' "$COMMENTS" | jq -c --arg bot "$BOT_LOGIN" --arg suffix "repos/$REPO/issues/$PR" '
    [.[] | select(.user.login == $bot)
         | select((.issue_url // "") == "" or (.issue_url | endswith($suffix)))
         | {id, body}]') || die "コメントの照合に失敗した"
  # 本文の1行目が、マーカーの形のものだけを取り出す（整数で比べる）
  MATCHES=$(printf '%s' "$CANDS" | jq -c "$MARKER_FILTER") || die "マーカーの照合に失敗した"
  # 同じrunの、同じattempt、または、より後のattemptがあれば、書き込まない（古いattemptの再処理で、別コメントを作らない）
  SAME=$(printf '%s' "$MATCHES" | jq -r --argjson r "$RUN_ID" --argjson a "$ATTEMPT" 'any(.[]; .r == $r and .a >= $a) | if . then "1" else "" end') || die "照合に失敗した"
  UPD_ID=$(printf '%s' "$MATCHES" | jq -r --argjson r "$RUN_ID" --argjson a "$ATTEMPT" '[.[] | select(.r == $r and .a < $a)] | max_by(.a) | .id // empty') || die "照合に失敗した"
  if [ -n "$SAME" ]; then
    summary "triage: 処理済み（run $RUN_ID attempt $ATTEMPT）。書き込まない"
    echo "post: 処理済み"; exit 0
  elif [ -n "$UPD_ID" ]; then
    gh_write -X PATCH "repos/$REPO/issues/comments/$UPD_ID" -f "body=$BODY"
    summary "triage: PR #$PR のコメントを更新（$KIND）"
  else
    gh_write -X POST "repos/$REPO/issues/$PR/comments" -f "body=$BODY"
    summary "triage: PR #$PR にコメントを作成（$KIND）"
  fi
  exit 0
fi

# ---- route = merge：Issue ----
[ -n "$FP" ] || die "merge の投稿には、fingerprint が必要（未定義の扱い。docs/design.md）"
ISSUES=$(gh_list "repos/$REPO/issues?state=open") || die "Issueを読めない"
# 追記先：自動投稿の主体が作ったopenなIssueで、本文の2行目が、フィンガープリントの行（テンプレートと同じ位置）
TARGET=$(printf '%s' "$ISSUES" | jq -c --arg fp "$FPLINE" --arg bot "$BOT_LOGIN" '
  [.[] | select(has("pull_request") | not) | select(.state == "open") | select(.user.login == $bot)
       | select(((.body // "") | split("\n") | map(sub("\r$"; "")) | .[1]) == $fp)]
  | sort_by(.number) | first // empty') || die "Issueの照合に失敗した"
if [ -z "$TARGET" ]; then
  gh_write -X POST "repos/$REPO/issues" -f "title=mainのCIが失敗しています（自動）" -f "body=$ISSUE_BODY"
  summary "triage: Issueを作成（$KIND）"
  exit 0
fi
NUM=$(printf '%s' "$TARGET" | jq -r .number)
read -r r a <<< "$(marker_run "$(printf '%s' "$TARGET" | jq -r '.body // ""')")"
if [ "${r:-}" = "$RUN_ID" ] && [ "${a:-}" = "$ATTEMPT" ]; then
  summary "triage: 処理済み（Issue #$NUM の本文）。書き込まない"; exit 0
fi
ICOMMENTS=$(gh_list "repos/$REPO/issues/$NUM/comments") || die "Issueのコメントを読めない"
DONE=$(printf '%s' "$ICOMMENTS" | jq -c --arg bot "$BOT_LOGIN" '[.[] | select(.user.login == $bot)]' | jq -c "$MARKER_FILTER" | jq -r --argjson r "$RUN_ID" --argjson a "$ATTEMPT" 'any(.[]; .r == $r and .a == $a) | if . then "1" else "" end') || die "照合に失敗した"
if [ -n "$DONE" ]; then
  summary "triage: 処理済み（Issue #$NUM のコメント）。書き込まない"; exit 0
fi
gh_write -X POST "repos/$REPO/issues/$NUM/comments" -f "body=$BODY"
summary "triage: Issue #$NUM に追記（$KIND）"
exit 0
