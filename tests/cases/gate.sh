#!/usr/bin/env bash
# scripts/gate.sh のテスト（design.md 2.1、R-19、R-02、F-02、F-14）。契約は tests/CONTRACT.md 第2節。
# イベントは tests/fixtures/events/*.json を、jq のフィルタで変えて作る。

PULLS7="repos/tech-organization-mame/test-actions-go/pulls/7"
PULLS8="repos/tech-organization-mame/test-actions-go/pulls/8"
PUSH_SHA=fedcba9876543210fedcba9876543210fedcba98
COMMIT_PULLS="repos/tech-organization-mame/test-actions-go/commits/$PUSH_SHA/pulls"

# 対象外（out_of_scope。D-14）で、書き込みゼロ、スキーマに合う
assert_not_posted() {
  assert_eq "$GATE_RC" 0 "gate の終了コード"
  assert_ctx_valid
  assert_eq "$(ctx .route)" out_of_scope "route"
  assert_eq "$(ctx .state)" out_of_scope "state（D-14：out_of_scope に統一）"
  assert_writes 0
}

# spec: R-01, R-04（入口）, 2.1, G1
t_G01__pr_failure_same_repo_is_post_target() {
  event_from events/pr.json
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_eq "$GATE_RC" 0 "gate の終了コード"
  assert_ctx_valid
  assert_eq "$(ctx .state)" post_target state
  assert_eq "$(ctx .route)" pr route
  assert_eq "$(ctx .pr_number)" 7 pr_number
  assert_eq "$(ctx .run_id)" 123456789 run_id
  assert_eq "$(ctx .run_attempt)" 1 run_attempt
  assert_eq "$(ctx .head_sha)" 0123456789abcdef0123456789abcdef01234567 head_sha
  assert_eq "$(ctx .event)" pull_request event
  assert_eq "$(ctx .repository)" "$GITHUB_REPOSITORY" repository
  assert_eq "$(ctx .control_sha)" "$CONTROL_SHA" control_sha
  assert_writes 0
}

# spec: 2.1（実行指示した人。初回は actor）
t_G02__mention_first_attempt_is_actor() {
  event_from events/pr.json '.workflow_run.triggering_actor.login="someone-else"'
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_ctx_valid
  assert_eq "$(ctx .state)" post_target state
  assert_eq "$(ctx .mention)" octocat mention
}

# spec: 2.1（再実行は triggering_actor）
t_G03__mention_rerun_is_triggering_actor() {
  event_from events/pr.json '.workflow_run.run_attempt=2 | .workflow_run.triggering_actor.login="rerunner"'
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_ctx_valid
  assert_eq "$(ctx .state)" post_target state
  assert_eq "$(ctx .run_attempt)" 2 run_attempt
  assert_eq "$(ctx .mention)" rerunner mention
}

# spec: F-02, R-02, S-10（forkのPR。実際のペイロードでは pull_requests が空）
t_G04__fork_pr_is_out_of_scope() {
  event_from events/pr.json '.workflow_run.head_repository.full_name="attacker/test-actions-go" | .workflow_run.head_repository.fork=true | .workflow_run.pull_requests=[]'
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_not_posted
}

# spec: F-02, S-10（forkでも pull_requests が入っている場合。fork判定が先）
t_G05__fork_pr_with_pull_requests_listed_is_out_of_scope() {
  event_from events/pr.json '.workflow_run.head_repository.full_name="attacker/test-actions-go" | .workflow_run.head_repository.fork=true'
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_not_posted
}

# spec: F-02, F-14, R-02（botが作ったPR。実行指示した人は人間）
t_G06__bot_authored_pr_is_out_of_scope() {
  event_from events/pr.json '.workflow_run.pull_requests=[{"number":8}]'
  stub_api "$PULLS8" gate/pull_bot.json
  run_gate
  assert_not_posted
}

# spec: F-02, F-14, 2.1（actor が bot でログインに [ ] を含んでも、context はスキーマに合う）
t_G07__bot_actor_on_bot_pr_context_is_schema_valid() {
  event_from events/pr.json '.workflow_run.pull_requests=[{"number":8}] | .workflow_run.actor.login="dependabot[bot]" | .workflow_run.actor.type="Bot" | .workflow_run.triggering_actor.login="dependabot[bot]" | .workflow_run.triggering_actor.type="Bot"'
  stub_api "$PULLS8" gate/pull_bot.json
  run_gate
  assert_not_posted
}

# spec: F-02, R-02（cron）
t_G08__schedule_is_out_of_scope() {
  event_from events/pr.json '.workflow_run.event="schedule" | .workflow_run.pull_requests=[] | .workflow_run.head_branch="main"'
  run_gate
  assert_not_posted
}

# spec: F-02, R-02（手動）
t_G09__workflow_dispatch_is_out_of_scope() {
  event_from events/pr.json '.workflow_run.event="workflow_dispatch" | .workflow_run.pull_requests=[] | .workflow_run.head_branch="main"'
  run_gate
  assert_not_posted
}

# spec: F-14, R-19, 2.1（mainへの直接push。紐づくPRがない）
t_G10__direct_push_to_main_is_not_post_target() {
  event_from events/push_main.json
  stub_api "$COMMIT_PULLS" gate/commit_pulls_empty.json
  run_gate
  assert_not_posted
}

# spec: F-14, R-19（紐づくPRがあるが、マージ済みではない）
t_G11__push_with_unmerged_pr_is_not_post_target() {
  event_from events/push_main.json
  stub_api "$COMMIT_PULLS" gate/commit_pulls_unmerged.json
  run_gate
  assert_not_posted
}

# spec: R-01, R-19, 2.1（マージ済みPR経由のmainの失敗）
t_G12__push_to_main_via_merged_pr_is_post_target_merge() {
  event_from events/push_main.json
  stub_api "$COMMIT_PULLS" gate/commit_pulls_merged.json
  run_gate
  assert_eq "$GATE_RC" 0 "gate の終了コード"
  assert_ctx_valid
  assert_eq "$(ctx .state)" post_target state
  assert_eq "$(ctx .route)" merge route
  assert_eq "$(ctx .pr_number)" null pr_number
  assert_eq "$(ctx .event)" push event
  assert_eq "$(ctx .run_id)" 123456790 run_id
  assert_eq "$(ctx .head_sha)" "$PUSH_SHA" head_sha
  assert_writes 0
}

# spec: F-14, R-19（PR特定不能: pull_requests が空）
t_G13__pr_event_without_pull_requests_is_not_post_target() {
  event_from events/pr.json '.workflow_run.pull_requests=[]'
  run_gate
  assert_not_posted
}

# spec: F-14, R-19（対応を確定できない: PR取得のAPIが失敗）
t_G14__pr_lookup_failure_is_not_post_target() {
  event_from events/pr.json
  # pulls/7 の固定応答を置かない（スタブは 404 相当で失敗する）
  run_gate
  assert_not_posted
}

# spec: F-14, R-19（対応を確定できない: コミットのPR取得が失敗）
t_G15__commit_pulls_lookup_failure_is_not_post_target() {
  event_from events/push_main.json
  run_gate
  assert_not_posted
}

# spec: R-02（そのほかのpush: デフォルトブランチ以外）
t_G16__push_to_other_branch_is_out_of_scope() {
  event_from events/push_main.json '.workflow_run.head_branch="feature/x"'
  stub_api "$COMMIT_PULLS" gate/commit_pulls_merged.json
  run_gate
  assert_not_posted
}

# spec: 2.1（3つのワークフローは state で分岐する。GITHUB_OUTPUT に state と route を書く: CONTRACT 2.4 の決定）
t_G17__github_output_has_state_and_route() {
  event_from events/pr.json
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_eq "$GATE_RC" 0 "gate の終了コード"
  grep -qx 'state=post_target' "$GITHUB_OUTPUT" || fail "GITHUB_OUTPUT に state=post_target がない: $(cat "$GITHUB_OUTPUT")"
  grep -qx 'route=pr' "$GITHUB_OUTPUT" || fail "GITHUB_OUTPUT に route=pr がない: $(cat "$GITHUB_OUTPUT")"
}

# spec: 出力は context.schema.json に合うこと（検証器の自己確認。実装なしでも通る）
t_G00__context_validator_agrees_with_schema_examples() {
  local f
  for f in "$REPO_ROOT"/schemas/examples/context.valid-*.json; do
    jq -e -f "$T_DIR/lib/context_valid.jq" "$f" > /dev/null || fail "valid のはずが不合格: $f"
  done
  for f in "$REPO_ROOT"/schemas/examples/context.invalid-*.json; do
    if jq -e -f "$T_DIR/lib/context_valid.jq" "$f" > /dev/null; then fail "invalid のはずが合格: $f"; fi
  done
}

########## Codexレビューの反映（2026-11-23）##########

# spec: R-19（PR候補が複数なら、一意に確定できない。対象外）
t_G19__multiple_pull_requests_is_out_of_scope() {
  event_from events/pr.json '.workflow_run.pull_requests=[{"number":7},{"number":8}]'
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_not_posted
}

# spec: R-19（PRの応答に作成者がない、または、番号が合わない。対象外）
t_G20__pr_response_without_author_or_with_wrong_number_is_out_of_scope() {
  event_from events/pr.json
  echo '{"number":7,"state":"open"}' > "$WORK/p.json"
  mkdir -p "$STUB_STATE/api"; cp "$WORK/p.json" "$STUB_STATE/api/${PULLS7//\//__}.json"
  run_gate
  assert_not_posted
  reset_state
  echo '{"number":99,"user":{"login":"octocat","type":"User"}}' > "$STUB_STATE/api/${PULLS7//\//__}.json" 2>/dev/null || { mkdir -p "$STUB_STATE/api"; echo '{"number":99,"user":{"login":"octocat","type":"User"}}' > "$STUB_STATE/api/${PULLS7//\//__}.json"; }
  run_gate
  assert_not_posted
}

# spec: R-02（人間が作ったPRでも、実行者がbotなら、対象外）
t_G21__bot_runner_on_human_pr_is_out_of_scope() {
  event_from events/pr.json '.workflow_run.actor.login="some-app[bot]" | .workflow_run.actor.type="Bot"'
  stub_api "$PULLS7" gate/pull_human.json
  run_gate
  assert_not_posted
}

# spec: R-19（マージ済みPRのベースが、デフォルトブランチでない。対象外）
t_G22__merged_pr_to_other_base_is_not_post_target() {
  event_from events/push_main.json
  stub_api "$COMMIT_PULLS" gate/commit_pulls_merged.json
  cp "$STUB_STATE/api/${COMMIT_PULLS//\//__}.json" "$WORK/x.json"
  jq '.[0].base.ref="release"' "$WORK/x.json" > "$STUB_STATE/api/${COMMIT_PULLS//\//__}.json"
  run_gate
  assert_not_posted
}

# spec: design 2.1（メンション先が Bot の種類なら、[bot] が付かなくても、メンションしない）
t_G23__bot_type_runner_without_bot_suffix_is_not_mentioned() {
  event_from events/push_main.json '.workflow_run.actor.login="someapp" | .workflow_run.actor.type="Bot"'
  stub_api "$COMMIT_PULLS" gate/commit_pulls_merged.json
  run_gate
  assert_eq "$GATE_RC" 0 "gate の終了コード"
  assert_ctx_valid
  assert_eq "$(ctx .mention)" null mention
}

