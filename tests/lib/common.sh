#!/usr/bin/env bash
# テストの共通関数。tests/run.sh が、ケースごとのサブシェルで source する。
# 失敗は fail（stderr に出して exit 1）。ケースはサブシェルで動くので、終了してよい。

RUN_ID=123456789
MERGE_RUN_ID=123456790
PR_NUM=7
FP_B=$(printf 'b%.0s' $(seq 64))
FP_C=$(printf 'c%.0s' $(seq 64))
BOT=github-actions[bot]

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "${3:-assert_eq}: expected [$2] got [$1]"; }
assert_ne() { [ "$1" != "$2" ] || fail "${3:-assert_ne}: unexpected [$1]"; }
assert_contains() {
  case "$1" in *"$2"*) ;; *) fail "${3:-contains}: [$2] not found in:
$1" ;; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) fail "${3:-not_contains}: [$2] found in:
$1" ;; esac
}

setup_case() {
  export TRIAGE_DIR="$WORK/triage" EVIDENCE_DIR="$WORK/evidence" STUB_STATE="$WORK/stub-state"
  export GITHUB_REPOSITORY=tech-organization-mame/test-actions-go DEFAULT_BRANCH=main
  export CONTROL_SHA=89abcdef0123456789abcdef0123456789abcdef
  export GITHUB_STEP_SUMMARY="$WORK/step-summary.md" GITHUB_OUTPUT="$WORK/github-output.txt"
  export PATH="$T_DIR/stubs:$PATH"
  mkdir -p "$TRIAGE_DIR" "$EVIDENCE_DIR" "$STUB_STATE"
  : > "$GITHUB_STEP_SUMMARY"
  : > "$GITHUB_OUTPUT"
  use_log
}
check_no_unsupported() {
  [ ! -f "$STUB_STATE/unsupported" ] || fail "契約外の gh 呼び出し: $(cat "$STUB_STATE/unsupported")"
}
reset_state() { rm -rf "$STUB_STATE"; mkdir -p "$STUB_STATE"; }

# ---- 固定データの配置 ----
use_log() { cp "$T_DIR/fixtures/post/log.txt" "$EVIDENCE_DIR/log.txt"; }
# ctx_from <fixtures相対パス> [jqフィルタ]
ctx_from() { jq "${2:-.}" "$T_DIR/fixtures/$1" > "$TRIAGE_DIR/context.json"; }
res_from() { jq "${2:-.}" "$T_DIR/fixtures/$1" > "$TRIAGE_DIR/result.json"; }
event_from() { jq "${2:-.}" "$T_DIR/fixtures/$1" > "$WORK/event.json"; export GITHUB_EVENT_PATH="$WORK/event.json"; }
# stub_api <APIパス> <fixtures相対パス>
stub_api() {
  local p=${1#/}
  mkdir -p "$STUB_STATE/api"
  cp "$T_DIR/fixtures/$2" "$STUB_STATE/api/${p//\//__}.json"
}
marker() { printf '<!-- triage:run-%s-attempt-%s -->' "$1" "$2"; }
# seed_comment <対象番号> <id> <作成者> <本文> [issue_urlの番号]
seed_comment() {
  local n=$1 id=$2 login=$3 body=$4 inum=${5:-$1}
  local f="$STUB_STATE/comments/$n.json"
  mkdir -p "$STUB_STATE/comments"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --argjson id "$id" --arg l "$login" --arg b "$body" \
     --arg u "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$inum" \
     '. + [{id:$id,user:{login:$l,type:(if ($l|endswith("[bot]")) then "Bot" else "User" end)},body:$b,issue_url:$u}]' \
     "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
# seed_issue <番号> <open|closed> <作成者> <本文> [タイトル]
seed_issue() {
  local f="$STUB_STATE/issues.json"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --argjson n "$1" --arg s "$2" --arg l "$3" --arg b "$4" --arg t "${5:-mainのCIが失敗しています（自動）}" \
     '. + [{number:$n,state:$s,title:$t,body:$b,user:{login:$l,type:"Bot"}}]' \
     "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
comment_count() { jq 'length' "$STUB_STATE/comments/$1.json" 2>/dev/null || echo 0; }
issue_count() { jq 'length' "$STUB_STATE/issues.json" 2>/dev/null || echo 0; }

# ---- 書き込みの検査 ----
writes_file() { echo "$STUB_STATE/writes.jsonl"; }
writes_count() {
  local f; f=$(writes_file)
  if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi
}
assert_writes() {
  local n; n=$(writes_count)
  [ "$n" = "$1" ] || fail "書き込みは $1 回のはずが $n 回: $(cat "$(writes_file)" 2>/dev/null)"
}
# write_field <N番目> <jqパス>
write_field() { sed -n "${1}p" "$(writes_file)" | jq -r "$2"; }
write_body() { write_field "$1" '.fields.body'; }

# ---- 文面の検査 ----
first_line() { printf '%s\n' "$1" | head -n 1; }
last_line() { printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | tail -n 1; }
# 先頭のマーカー行と、HTMLコメント行を除いた本文
non_marker() { printf '%s\n' "$1" | sed '1d' | grep -v '^<!--' || true; }
count_char() { printf '%s' "$1" | tr -cd "$2" | wc -c | tr -d ' '; }
count_marker_lines() { printf '%s\n' "$1" | grep -c '<!-- triage:' || true; }
assert_no_html() {
  local nm; nm=$(non_marker "$1")
  # テンプレート（デフォルトブランチのファイル）が書く折り畳みのタグは、許す（D-15）
  nm=$(printf '%s
' "$nm" | sed -E 's#</?(details|summary)>##g')
  if printf '%s\n' "$nm" | grep -Eq '<[A-Za-z/!]'; then fail "HTMLが残っている:
$nm"; fi
}

# ---- スクリプトの実行 ----
run_gate() { bash "$REPO_ROOT/scripts/gate.sh" > "$WORK/gate.out" 2>&1; GATE_RC=$?; }
run_post() { bash "$REPO_ROOT/scripts/post.sh" > "$WORK/post.out" 2>&1; POST_RC=$?; }
ctx() { jq -r "$1" "$TRIAGE_DIR/context.json"; }
assert_ctx_valid() {
  [ -f "$TRIAGE_DIR/context.json" ] || fail "context.json が書かれていない: $(cat "$WORK/gate.out" 2>/dev/null)"
  jq -e -f "$T_DIR/lib/context_valid.jq" "$TRIAGE_DIR/context.json" > /dev/null \
    || fail "context.json が context.schema.json に合わない: $(cat "$TRIAGE_DIR/context.json")"
}
