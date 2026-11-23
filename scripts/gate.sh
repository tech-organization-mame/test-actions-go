#!/usr/bin/env bash
# 入口の判定（3構成共通。docs/design.md 2.1、D-10）。Claudeを起動する前に実行する。
# 契約：tests/CONTRACT.md 第2節。書き込みは、context.json と GITHUB_OUTPUT のみ。gh は、gh api の読み取りだけ。
# 注意：未検証のたたき台。
set -u

TRIAGE_DIR=${TRIAGE_DIR:-triage}
EVIDENCE_DIR=${EVIDENCE_DIR:-evidence}
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
CONTROL_SHA=${CONTROL_SHA:-0000000000000000000000000000000000000000}
REPO=${GITHUB_REPOSITORY:-}

die() { echo "gate: $*" >&2; exit 2; }

[ -n "${GITHUB_EVENT_PATH:-}" ] && [ -r "$GITHUB_EVENT_PATH" ] || die "イベントファイルが読めない"
jq -e '.workflow_run' "$GITHUB_EVENT_PATH" > /dev/null 2>&1 || die "workflow_run がない"
[ -n "$REPO" ] || die "GITHUB_REPOSITORY がない"

ev() { jq -r "$1 // empty" "$GITHUB_EVENT_PATH"; }

RUN_ID=$(ev '.workflow_run.id')
RUN_ATTEMPT=$(ev '.workflow_run.run_attempt')
EVENT=$(ev '.workflow_run.event')
HEAD_BRANCH=$(ev '.workflow_run.head_branch')
HEAD_SHA=$(ev '.workflow_run.head_sha')
HEAD_REPO=$(ev '.workflow_run.head_repository.full_name')
PR_COUNT=$(jq -r '(.workflow_run.pull_requests // []) | length' "$GITHUB_EVENT_PATH")
PR_FIRST=$(ev '.workflow_run.pull_requests[0].number')
ACTOR=$(ev '.workflow_run.actor.login')
TRIGGERING=$(ev '.workflow_run.triggering_actor.login')
# 実行者がbotか（種類がBot、またはログインが [bot] で終わる）。初回は actor、再実行は triggering_actor
if [ "${RUN_ATTEMPT:-1}" = "1" ]; then RUNNER_KEY=actor; else RUNNER_KEY=triggering_actor; fi
RUNNER_IS_BOT=$(jq -r --arg k "$RUNNER_KEY" '.workflow_run[$k] | ((.type // "") == "Bot") or ((.login // "") | endswith("[bot]"))' "$GITHUB_EVENT_PATH")

# メンション先：初回は actor、再実行は triggering_actor。取れない、botなど形に合わないときは null
if [ "${RUN_ATTEMPT:-1}" = "1" ]; then MENTION=$ACTOR; else MENTION=$TRIGGERING; fi
if [ "$RUNNER_IS_BOT" = "true" ] || ! printf '%s' "$MENTION" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'; then MENTION=""; fi

ROUTE=out_of_scope
STATE=out_of_scope
PR_NUMBER=""
REASON=""

if [ "$EVENT" != "pull_request" ] && [ "$EVENT" != "push" ]; then
  REASON="対象外のイベント（$EVENT）"
elif [ "$HEAD_REPO" != "$REPO" ]; then
  REASON="forkの実行"
elif [ "$EVENT" = "pull_request" ]; then
  if [ "$PR_COUNT" != "1" ] || [ -z "$PR_FIRST" ]; then
    REASON="PRを一意に特定できない（候補 ${PR_COUNT} 件）"
  elif ! PR_JSON=$(gh api "repos/$REPO/pulls/$PR_FIRST" 2>/dev/null); then
    REASON="PRを取得できない"
  elif ! printf '%s' "$PR_JSON" | jq -e --argjson n "$PR_FIRST" '(.number == $n) and ((.user.login // null) | type == "string")' > /dev/null 2>&1; then
    REASON="PRの応答が不正（番号の不一致、または作成者がない）"
  elif printf '%s' "$PR_JSON" | jq -e '(.user.type == "Bot") or (.user.login | endswith("[bot]"))' > /dev/null; then
    REASON="botが作ったPR"
  elif [ "$RUNNER_IS_BOT" = "true" ]; then
    REASON="botによる実行"
  else
    ROUTE=pr; STATE=post_target; PR_NUMBER=$PR_FIRST
  fi
else
  # push
  if [ "$HEAD_BRANCH" != "$DEFAULT_BRANCH" ]; then
    REASON="デフォルトブランチ以外へのpush"
  elif ! PULLS=$(gh api "repos/$REPO/commits/$HEAD_SHA/pulls" 2>/dev/null); then
    REASON="コミットに紐づくPRを取得できない"
  elif printf '%s' "$PULLS" | jq -e --arg b "$DEFAULT_BRANCH" 'type == "array" and any(.[]; .merged_at != null and .base.ref == $b)' > /dev/null 2>&1; then
    ROUTE=merge; STATE=post_target
  else
    REASON="直接push（マージ済みPRなし）"
  fi
fi

mkdir -p "$TRIAGE_DIR"
if [ -f "$EVIDENCE_DIR/log.txt" ]; then
  EVIDENCE_SHA=$(sha256sum "$EVIDENCE_DIR/log.txt" | cut -d' ' -f1)
else
  EVIDENCE_SHA=$(printf '' | sha256sum | cut -d' ' -f1)
fi

jq -n \
  --arg repo "$REPO" --arg route "$ROUTE" --arg state "$STATE" \
  --argjson run_id "${RUN_ID:-0}" --argjson attempt "${RUN_ATTEMPT:-1}" \
  --arg head_sha "$HEAD_SHA" --arg event "$EVENT" \
  --arg pr "$PR_NUMBER" --arg mention "$MENTION" \
  --arg control "$CONTROL_SHA" --arg evidence "$EVIDENCE_SHA" '
  {
    schema_version: 1,
    repository: $repo,
    route: $route,
    state: $state,
    run_id: $run_id,
    run_attempt: $attempt,
    head_sha: $head_sha,
    event: $event,
    pr_number: (if $pr == "" then null else ($pr | tonumber) end),
    mention: (if $mention == "" then null else $mention end),
    same_sha_rerun: "none",
    fingerprint: null,
    control_sha: $control,
    evidence_sha256: $evidence
  }' > "$TRIAGE_DIR/context.json" || die "context.json を書けない"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "state=$STATE"; echo "route=$ROUTE"; } >> "$GITHUB_OUTPUT"
fi
echo "gate: route=$ROUTE state=$STATE ${REASON:+($REASON)}"
exit 0
