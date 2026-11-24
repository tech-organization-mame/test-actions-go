#!/usr/bin/env bash
# 入口の判定。AIを起動する前に実行し、投稿の対象かどうかと、宛先を決める。
set -eu
ev() { jq -r "$1 // empty" "$GITHUB_EVENT_PATH"; }
repo=$GITHUB_REPOSITORY; branch=${DEFAULT_BRANCH:-main}
event=$(ev .workflow_run.event); attempt=$(ev .workflow_run.run_attempt); sha=$(ev .workflow_run.head_sha)
# 実行した人：初回は actor、再実行は triggering_actor
who=actor; [ "$attempt" = 1 ] || who=triggering_actor
bot='(.type == "Bot") or ((.login // "") | endswith("[bot]"))'
runner_is_bot=$(jq -r ".workflow_run.$who | $bot" "$GITHUB_EVENT_PATH")

state=out_of_scope route=out_of_scope pr=""
if [ "$(ev .workflow_run.head_repository.full_name)" != "$repo" ] || [ "$runner_is_bot" = true ]; then
  :  # forkと、botによる実行は、対象外
elif [ "$event" = pull_request ] && [ "$(ev '.workflow_run.pull_requests | length')" = 1 ]; then
  n=$(ev '.workflow_run.pull_requests[0].number')
  # botが作ったPRは、対象外
  [ "$(gh api "repos/$repo/pulls/$n" --jq ".user | $bot")" = false ] && state=post_target route=pr pr=$n
elif [ "$event" = push ] && [ "$(ev .workflow_run.head_branch)" = "$branch" ]; then
  # マージ済みのPRに紐づく、デフォルトブランチのpushだけが対象（直接pushは対象外）
  [ "$(gh api "repos/$repo/commits/$sha/pulls" --jq "any(.[]; .merged_at != null and .base.ref == \"$branch\")")" = true ] && state=post_target route=merge
fi

mkdir -p triage
jq -n --arg repo "$repo" --arg state "$state" --arg route "$route" --arg pr "$pr" --arg sha "$sha" --arg event "$event" \
  --argjson run "$(ev .workflow_run.id)" --argjson attempt "$attempt" --arg mention "$(ev ".workflow_run.$who.login")" \
  '{repository: $repo, event: $event, state: $state, route: $route, pr_number: ($pr | tonumber? // null), head_sha: $sha,
    run_id: $run, run_attempt: $attempt, mention: (if $mention == "" then null else $mention end)}' > triage/context.json
echo "state=$state" >> "${GITHUB_OUTPUT:-/dev/null}"
