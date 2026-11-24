#!/usr/bin/env bash
# 投稿。AIの終了後に、通常のステップとして実行する。宛先は context.json だけから決める。
set -euo pipefail
c() { jq -r "$1" triage/context.json; }
[ "$(c .state)" = post_target ] || exit 0
repo=$(c .repository); route=$(c .route); run=$(c .run_id); att=$(c .run_attempt); pr=$(c '.pr_number // empty')
bot="github-actions[bot]"; marker="<!-- triage:run-$run-attempt-$att -->"
HERE=$(dirname "$0"); T=${TRIAGE_TEMPLATE_DIR:-$HERE/templates}

# 結果の検証：スキーマ（既存のコマンドに任せる）と、根拠の行がログにあること
ok=0
if check-jsonschema --schemafile "$HERE/../schemas/result.schema.json" triage/result.json > /dev/null 2>&1 \
  && jq -e --rawfile log evidence/log.txt '.evidence | all(.[]; . as $id | $log | test("(^|\n)" + $id + ": "))' triage/result.json > /dev/null; then ok=1; fi

# AIが書く欄の無害化：制御文字、HTML、URL、@ を除き、角括弧を全角にする（リンクと画像を作らせない）
san='def san: gsub("[\\x00-\\x1f\\x7f]+"; " ") | gsub("<[^>]*>?"; "") | gsub("https?://\\S*"; "") | gsub("www\\.\\S*"; ""; "i") | gsub("@"; "")
     | gsub("\\["; "［") | gsub("\\]"; "］");'
# テンプレート：{{名前}} を、1回の走査で置き換える
render() { jq -Rrs --argjson v "$2" 'gsub("\\{\\{(?<k>[a-z0-9_]+)\\}\\}"; .k as $k | $v[$k])' "$T/$1"; }
base=$(jq -n --arg wf "${TRIAGE_WORKFLOW_NAME:-CI}" --arg m "$marker" --arg run "$run" --arg att "$att" --arg sha "$(c '.head_sha[0:7]')" \
  --arg url "https://github.com/$repo/actions/runs/$run" --arg who "$(c '.mention // empty | "@" + .')" \
  '{workflow: $wf, marker: $m, run_id: $run, attempt: $att, sha7: $sha, run_url: $url, mention_line: $who}')

if [ "$ok" = 1 ]; then
  [ -r triage/linkmap.json ] || echo '{}' > triage/linkmap.json  # ログの行へのリンクの表（準備スクリプトが作る）
  vars=$(jq -c --argjson base "$base" --rawfile log evidence/log.txt \
    --slurpfile lm triage/linkmap.json "$san"'
    ($log | split("\n") | map(capture("^(?<id>L[0-9]+): (?<t>.*)$")?) | map({key: .id, value: .t}) | from_entries) as $map
    | $base + {summary: (.summary | san), cause: (if .category == "network_error" and ([.evidence[] | $map[.] | ascii_downcase] | any(test("i/o timeout|connection reset|tls handshake timeout")) | not)
          then "不明（ネットワークエラーと断定できる根拠が、ログにない）" else (.suspected_cause | san) end),
        next_steps: ([.next_steps[] | "  - " + san] | join("\n")),
        evidence_links: ("根拠の行：" + ([.evidence[] | . as $id | $lm[0][$id] as $e
          | if $e then "[\($id)](\($base.run_url)/job/\($e.job)#step:\($e.step):\($e.line))" else $id end] | join("、"))),
        # ログの引用は、そのまま、コードブロックに入れる（囲みは、引用中の最長のバッククォート列より長くする）
        evidence: ([.evidence[] | . + ": " + ($map[.] | gsub("[\\x00-\\x1f\\x7f]+"; " "))] as $q
          | ("`" * ([3, ([$q[] | [match("`+"; "g").length] | max // 0] | max) + 1] | max)) as $f
          | "\($f)\n\($q | join("\n"))\n\($f)")}' triage/result.json)
  body=$(render pr-comment.md "$vars"); issue=""
  if [ "$route" = merge ]; then issue=$(render issue.md "$vars"); fi
else
  body=$(render failed.md "$base"); issue=$body
fi

if [ "$route" = pr ]; then
  # 同じrunのコメントが、すでにあるか。同じattemptなら何もせず、前のattemptなら更新する
  found=$(gh api "repos/$repo/issues/$pr/comments" --paginate --jq \
    ".[] | select(.user.login == \"$bot\" and (.body | startswith(\"<!-- triage:run-$run-\"))) | [.id, (.body | startswith(\"$marker\"))] | @tsv" | tail -n 1)
  [ "${found##*$'\t'}" = true ] && exit 0
  if [ -n "$found" ]; then gh api -X PATCH "repos/$repo/issues/comments/${found%%$'\t'*}" -f "body=$body" > /dev/null
  else gh api -X POST "repos/$repo/issues/$pr/comments" -f "body=$body" > /dev/null; fi
else
  # mainの失敗：openなIssue（自動投稿の主体が作ったもの）に追記する。なければ作る
  title="mainのCIが失敗しています（自動）"
  found=$(gh api "repos/$repo/issues?state=open" --paginate --jq \
    ".[] | select(.user.login == \"$bot\" and .title == \"$title\" and (has(\"pull_request\") | not)) | [.number, (.body | startswith(\"$marker\"))] | @tsv" | head -n 1)
  num=${found%%$'\t'*}
  if [ -z "$found" ]; then gh api -X POST "repos/$repo/issues" -f "title=$title" -f "body=$issue" > /dev/null
  elif [ "${found##*$'\t'}" != true ] && [ -z "$(gh api "repos/$repo/issues/$num/comments" --paginate --jq \
      ".[] | select(.user.login == \"$bot\" and (.body | startswith(\"$marker\"))) | .id")" ]; then
    gh api -X POST "repos/$repo/issues/$num/comments" -f "body=$body" > /dev/null
  fi
fi
