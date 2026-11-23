#!/usr/bin/env bash
# 準備：失敗した実行のログを取り、行ID（L<番号>）を付けて evidence/log.txt に置く。AIを使わない。
# あわせて、行IDから、ActionsのログのURLの部品（ジョブID、ステップ番号、ステップ内の行）を引く表を、
# $TRIAGE_DIR/linkmap.json に置く。AIが読む evidence/ には置かない（投稿スクリプトだけが使う）。
set -euo pipefail
EVIDENCE_DIR=${EVIDENCE_DIR:-evidence}
TRIAGE_DIR=${TRIAGE_DIR:-triage}
RUN_ID=$(jq -r .run_id "$TRIAGE_DIR/context.json")
ATTEMPT=$(jq -r '.run_attempt // 1' "$TRIAGE_DIR/context.json")
mkdir -p "$EVIDENCE_DIR"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# 先頭200行（ジョブ名、ステップ名、本文の3列）。以降の加工は、行数を変えない
gh run view "$RUN_ID" --log-failed 2>/dev/null | sed 's/\r$//' | head -n 200 > "$WORK/raw" || true

# 取り除くもの：ジョブ名とステップ名の列、BOM、タイムスタンプ、ANSIの色コード（ESC形式と、^[ 形式）
cut -f3- "$WORK/raw" \
  | sed -E $'s/^\xef\xbb\xbf//; s/^[0-9T:.Z-]+ //; s/\x1b\[[0-9;]*[A-Za-z]//g' \
  | sed -E 's/\^\[\[[0-9;]*[A-Za-z]//g' \
  | awk '{ printf "L%d: %s\n", NR, $0 }' > "$EVIDENCE_DIR/log.txt"

# 行ID → ジョブID、ステップ番号、ステップ内の行（失敗しても、リンクなしで続ける）
echo '{}' > "$TRIAGE_DIR/linkmap.json"
if gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${RUN_ID}/attempts/${ATTEMPT}/jobs" --paginate 2>/dev/null \
     | jq -s '[.[].jobs[]]' > "$WORK/jobs.json" 2>/dev/null; then
  cut -f1,2 "$WORK/raw" | awk -F'\t' '{ k = $1 "\t" $2; c[k]++; printf "%d\t%s\t%s\t%d\n", NR, $1, $2, c[k] }' \
    | jq -Rn --slurpfile jobs "$WORK/jobs.json" '
        [inputs | split("\t")] | map(
          . as [$n, $job, $step, $k]
          | ($jobs[0] | map(select(.name == $job)) | first // null) as $j
          | ($j.steps // [] | map(select(.name == $step)) | first // null) as $s
          | select($j != null and $s != null)
          | {key: ("L" + $n), value: {job: $j.id, step: $s.number, line: ($k | tonumber)}}
        ) | from_entries' > "$WORK/linkmap.json" 2>/dev/null && cp "$WORK/linkmap.json" "$TRIAGE_DIR/linkmap.json" || true
fi

# PRの差分（PR経路のみ。大きすぎる場合は、先頭だけ）
PR=$(jq -r '.pr_number // empty' "$TRIAGE_DIR/context.json")
if [ -n "$PR" ]; then
  gh api -H "Accept: application/vnd.github.diff" "repos/${GITHUB_REPOSITORY}/pulls/$PR" 2>/dev/null | head -c 20000 > "$EVIDENCE_DIR/diff.patch" || true
fi
