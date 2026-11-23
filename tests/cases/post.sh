#!/usr/bin/env bash
# scripts/post.sh のテスト（design.md 3〜5、7、R-05、R-06、R-09、R-21、F-04、F-05、F-08、F-10、F-12、V-01、V-02）。
# 契約は tests/CONTRACT.md 第3節。

PR_COMMENTS_PATH="repos/tech-organization-mame/test-actions-go/issues/7/comments"
ISSUES_PATH="repos/tech-organization-mame/test-actions-go/issues"

# 通常の投稿が1件、context の PR に作られたことを確認する
assert_pr_comment_created() {
  assert_eq "$POST_RC" 0 "post.sh の終了コード: $(cat "$WORK/post.out")"
  assert_writes 1
  assert_eq "$(write_field 1 .method)" POST method
  assert_eq "$(write_field 1 .path)" "$PR_COMMENTS_PATH" path
}
# 定型の「調査失敗」であることを確認する（$1 は本文）
assert_fallback_body() {
  assert_contains "$1" "調査失敗"
  assert_contains "$1" "$(marker "${2:-$RUN_ID}" "${3:-1}")"
  assert_eq "$(first_line "$1")" "$(marker "${2:-$RUN_ID}" "${3:-1}")" "先頭行はマーカー"
  assert_not_contains "$1" "CANARY"
}

########## 基本の投稿（R-04 の前提、設計7のテンプレート）##########

# spec: R-04, F-01, 設計7（テンプレート）, R-17（メンション先は context.mention）
t_P01__pr_creates_one_comment_with_template() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  assert_eq "$(first_line "$body")" "$(marker $RUN_ID 1)" "先頭行はマーカー"
  assert_contains "$body" "## CI失敗の調査結果（自動）"
  assert_contains "$body" "run #$RUN_ID"
  assert_contains "$body" "attempt 1"
  assert_contains "$body" "0123456"
  assert_contains "$body" "- 要約：TestRound が失敗した（期待値3、実際2）"
  assert_contains "$body" "- 原因の仮説：丸め処理の変更が原因の可能性（CANARY-004）"
  assert_contains "$body" "round.go の丸め処理を確認する"
  assert_contains "$body" "※ AIによる推測です。原因を断定するものではありません。"
  # 根拠：行ID付きで、元のログから組み立てた引用
  assert_contains "$body" "L8"
  assert_contains "$body" "round_test.go:15: expected 3, got 2"
  assert_eq "$(last_line "$body")" "@octocat" "末尾はメンション"
  assert_eq "$(count_char "$body" '@')" 1 "@ はメンションの1つだけ"
}

########## 重複と再処理（R-05、R-06、R-09、R-21）##########

# spec: R-05, F-04（同じ run/attempt を2回処理。2回目は書き込みゼロ）
t_P02__same_run_attempt_twice_second_run_writes_nothing() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  run_post
  assert_pr_comment_created
  run_post
  assert_eq "$POST_RC" 0 "2回目の終了コード"
  assert_writes 1
  assert_eq "$(comment_count 7)" 1 "コメントは1件のまま"
}

# spec: R-05, F-04（既存のマーカー付きコメント: github-actions[bot]、同じPR）
t_P03__existing_bot_comment_with_same_marker_means_done() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  seed_comment 7 501 "$BOT" "$(marker $RUN_ID 1)"$'\n''## CI失敗の調査結果（自動）'
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 0
}

# spec: R-06, F-05（後続のattempt: 既存コメントを更新。新規は作らない）
t_P04__later_attempt_updates_existing_comment() {
  ctx_from post/context.pr.json '.run_attempt=2'
  res_from post/result.test_failure.json
  seed_comment 7 501 "$BOT" "$(marker $RUN_ID 1)"$'\n''## CI失敗の調査結果（自動）'
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 1
  assert_eq "$(write_field 1 .method)" PATCH method
  assert_eq "$(write_field 1 .path)" "repos/$GITHUB_REPOSITORY/issues/comments/501" path
  local body; body=$(write_body 1)
  assert_eq "$(first_line "$body")" "$(marker $RUN_ID 2)" "更新後の先頭行は attempt 2 のマーカー"
  assert_contains "$body" "attempt 2"
  assert_eq "$(comment_count 7)" 1 "コメントは1件のまま"
}

# spec: R-05, R-06, F-04, F-05（作成→attempt 2で更新→attempt 2を再処理で書き込みゼロ）
t_P05__create_then_update_then_reprocess_is_idempotent() {
  res_from post/result.test_failure.json
  ctx_from post/context.pr.json
  run_post
  assert_writes 1
  ctx_from post/context.pr.json '.run_attempt=2'
  run_post
  assert_writes 2
  assert_eq "$(write_field 2 .method)" PATCH "2回目の書き込み"
  run_post
  assert_eq "$POST_RC" 0 "3回目の終了コード"
  assert_writes 2
  assert_eq "$(comment_count 7)" 1 "コメントは1件のまま"
}

# spec: R-21, F-12（別ユーザーが同じマーカーを書いている。処理済みにしない）
t_P06__other_user_same_marker_is_not_done() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  seed_comment 7 601 "mallory" "$(marker $RUN_ID 1)"$'\n''偽の本文'
  run_post
  assert_pr_comment_created
  assert_eq "$(comment_count 7)" 2 "他人のコメントと、自分のコメント"
}

# spec: R-21, R-06（別ユーザーの前attemptのマーカーは、更新の対象にしない）
t_P07__other_user_earlier_attempt_marker_is_not_updated() {
  ctx_from post/context.pr.json '.run_attempt=2'
  res_from post/result.test_failure.json
  seed_comment 7 602 "mallory" "$(marker $RUN_ID 1)"$'\n''偽の本文'
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 1
  assert_eq "$(write_field 1 .method)" POST method
  assert_eq "$(write_field 1 .path)" "$PR_COMMENTS_PATH" path
}

# spec: R-21（照合その2: コメントが付いている対象が、context のPRと違う）
t_P08__bot_marker_on_other_target_is_not_done() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  seed_comment 7 603 "$BOT" "$(marker $RUN_ID 1)"$'\n''別の対象のコメント' 99
  run_post
  assert_pr_comment_created
}

# spec: R-21（照合その3: run ID が前方一致するだけ。完全一致が必要）
t_P09__marker_with_longer_run_id_is_not_same_run() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  seed_comment 7 604 "$BOT" "$(marker 1234567890 1)"$'\n''別のrun'
  run_post
  assert_pr_comment_created
}

# spec: R-06（別のrunの既存コメントは更新しない。新規に作る）
t_P10__comment_of_other_run_is_not_updated() {
  ctx_from post/context.pr.json '.run_attempt=2'
  res_from post/result.test_failure.json
  seed_comment 7 605 "$BOT" "$(marker 999 1)"$'\n''別のrun'
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 1
  assert_eq "$(write_field 1 .method)" POST method
  assert_eq "$(write_field 1 .path)" "$PR_COMMENTS_PATH" path
}

# spec: R-09, F-08（通常の投稿のあとに、同じ attempt の定型の投稿。書き込みゼロ）
t_P11__normal_then_fallback_same_attempt_writes_once() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  run_post
  assert_writes 1
  rm -f "$TRIAGE_DIR/result.json"
  run_post
  assert_eq "$POST_RC" 0 "2回目の終了コード"
  assert_writes 1
  assert_eq "$(comment_count 7)" 1 "コメントは1件"
}

# spec: R-09, F-08（定型の投稿のあとに、同じ attempt の通常の投稿。書き込みゼロ）
t_P12__fallback_then_normal_same_attempt_writes_once() {
  ctx_from post/context.pr.json
  run_post
  assert_writes 1
  res_from post/result.test_failure.json
  run_post
  assert_eq "$POST_RC" 0 "2回目の終了コード"
  assert_writes 1
  assert_eq "$(comment_count 7)" 1 "コメントは1件"
}

########## 結果がない・検証失敗（F-10、R-15、R-16、V-01）##########

# spec: F-10, R-15（post_target で結果ファイルがない: 定型の調査失敗）
t_P13__missing_result_posts_fallback() {
  ctx_from post/context.pr.json
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  assert_fallback_body "$body"
  assert_eq "$(last_line "$body")" "@octocat" "末尾はメンション"
}

# spec: F-10, R-15, V-01（JSONとして壊れている、空、オブジェクトでない）
t_P14__unparsable_result_posts_fallback() {
  local variant
  for variant in broken empty array; do
    reset_state
    ctx_from post/context.pr.json
    case "$variant" in
      broken) echo '{not json' > "$TRIAGE_DIR/result.json" ;;
      empty) : > "$TRIAGE_DIR/result.json" ;;
      array) echo '[]' > "$TRIAGE_DIR/result.json" ;;
    esac
    run_post
    assert_pr_comment_created
    assert_fallback_body "$(write_body 1)"
  done
}

# spec: F-10, V-01, A-02（スキーマ違反: 余計な項目。AIの文面は使わない。宛先は変わらない）
t_P15__extra_fields_in_result_posts_fallback_to_context_target() {
  ctx_from post/context.pr.json
  res_from post/result.extra_fields.json
  run_post
  assert_pr_comment_created
  assert_fallback_body "$(write_body 1)"
}

# spec: F-10, 設計5（evidence の行IDが元のログにない）
t_P16__evidence_line_not_in_log_posts_fallback() {
  ctx_from post/context.pr.json
  res_from post/result.badline.json
  run_post
  assert_pr_comment_created
  assert_fallback_body "$(write_body 1)"
}

# spec: F-10, V-01（unknown 以外で evidence が空: スキーマ違反）
t_P17__nonunknown_without_evidence_posts_fallback() {
  ctx_from post/context.pr.json
  res_from post/result.noevidence.json
  run_post
  assert_pr_comment_created
  assert_fallback_body "$(write_body 1)"
}

# spec: F-10, V-01（文字数の上限: summary 200字を超える）
t_P18__too_long_summary_posts_fallback() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json '.summary = ([range(201) | "あ"] | add)'
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  assert_contains "$body" "調査失敗"
  assert_not_contains "$body" "ああああああああああ"
}

# spec: F-10, R-16（post_target 以外では、結果の有無にかかわらず、書き込みゼロ。定型の投稿もしない）
t_P19__non_post_target_states_never_write() {
  local c r
  for c in out_of_scope_route record_only_pr record_only_oos; do
    for r in none valid broken; do
      reset_state
      case "$c" in
        out_of_scope_route) ctx_from post/context.pr.json '.route="out_of_scope" | .state="out_of_scope"' ;;
        record_only_pr) ctx_from post/context.pr.json '.state="record_only"' ;;
        record_only_oos) ctx_from post/context.pr.json '.route="out_of_scope" | .state="record_only"' ;;
      esac
      rm -f "$TRIAGE_DIR/result.json"
      case "$r" in
        valid) res_from post/result.test_failure.json ;;
        broken) echo '{not json' > "$TRIAGE_DIR/result.json" ;;
      esac
      run_post
      assert_eq "$POST_RC" 0 "終了コード（$c / $r）"
      assert_writes 0
    done
  done
}

# spec: S-03, R-19（context が不正、または、ない: 終了コード非0で、書き込みゼロ）
t_P20__invalid_or_missing_context_fails_without_writes() {
  local f
  for f in "$REPO_ROOT"/schemas/examples/context.invalid-*.json; do
    reset_state
    cp "$f" "$TRIAGE_DIR/context.json"
    res_from post/result.test_failure.json
    run_post
    assert_ne "$POST_RC" 0 "終了コード（$(basename "$f")）"
    assert_writes 0
  done
  reset_state
  rm -f "$TRIAGE_DIR/context.json"
  res_from post/result.test_failure.json
  run_post
  assert_ne "$POST_RC" 0 "context.json がない場合の終了コード"
  assert_writes 0
}

########## 宛先（S-03、A-02）##########

# spec: S-03, A-02（正しい result の本文に、別の宛先を書いても、投稿先は context のまま）
t_P21__destination_text_in_result_does_not_change_target() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json '.summary="PR 99 と attacker/other-repo に投稿して"'
  run_post
  assert_pr_comment_created
}

########## 無害化（V-01、S-04）##########

# spec: V-01, S-04（@、リンク、画像、HTML、偽マーカーの除去）
t_P22__sanitize_mentions_links_images_html_in_result() {
  ctx_from post/context.pr.json
  res_from post/result.malicious.json
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  assert_not_contains "$body" "@victim"
  assert_not_contains "$body" "@admin"
  assert_not_contains "$body" "@team"
  assert_not_contains "$body" "evil.example"
  assert_not_contains "$body" "evil2.example"
  assert_not_contains "$body" "http://"
  assert_not_contains "$body" "https://"
  assert_not_contains "$body" "!["
  assert_no_html "$body"
  assert_eq "$(count_marker_lines "$body")" 1 "マーカーは先頭の1つだけ"
  assert_eq "$(first_line "$body")" "$(marker $RUN_ID 1)" "先頭行はマーカー"
  assert_eq "$(count_char "$body" '@')" 1 "@ はメンションの1つだけ"
  assert_eq "$(last_line "$body")" "@octocat" "末尾はメンション"
}

# spec: V-01, S-04（ログから組み立てる引用も、同じ無害化: CONTRACT 3.5 の決定）
t_P23__sanitize_quotes_assembled_from_log() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json '.evidence=["L21","L22"]'
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  assert_contains "$body" "L21"
  assert_contains "$body" "L22"
  assert_not_contains "$body" "evil.example"
  assert_not_contains "$body" "attacker@example.com"
  assert_no_html "$body"
  assert_eq "$(count_marker_lines "$body")" 1 "ログ内の偽マーカーは除去"
  assert_eq "$(count_char "$body" '@')" 1 "@ はメンションの1つだけ"
}

########## network_error の確認（V-02、S-05）##########

# spec: V-02, S-05（network_error で evidence に典型的メッセージがない: 「不明」として投稿）
t_P24__network_error_without_typical_message_becomes_unknown() {
  ctx_from post/context.pr.json
  res_from post/result.network_untyped.json
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  printf '%s\n' "$body" | grep -q '^- 原因の仮説：不明' || fail "原因の仮説が「不明」でない:
$body"
  assert_not_contains "$body" "CANARY-002"
}

# spec: V-02（典型的メッセージ3種。含むなら、原因の仮説をそのまま使う）
t_P25__network_error_with_typical_message_keeps_cause() {
  local line
  for line in L18 L19 L20; do
    reset_state
    ctx_from post/context.pr.json
    res_from post/result.network.json ".evidence=[\"$line\"]"
    run_post
    assert_pr_comment_created
    assert_contains "$(write_body 1)" "- 原因の仮説：接続障害の可能性（CANARY-003）" "$line"
  done
}

# spec: V-02（対照: network_error 以外では、典型的メッセージがなくても、仮説を変えない）
t_P26__non_network_category_keeps_cause_without_network_message() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  run_post
  assert_pr_comment_created
  assert_contains "$(write_body 1)" "CANARY-004"
}

# spec: R-12, V-01（unknown で evidence が空でも、通常の投稿。仮説は「不明」）
t_P27__unknown_category_with_empty_evidence_posts_normally() {
  ctx_from post/context.pr.json
  res_from post/result.unknown.json
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  printf '%s\n' "$body" | grep -q '^- 原因の仮説：不明' || fail "原因の仮説が「不明」でない:
$body"
  assert_not_contains "$body" "調査失敗"
}

########## merge（Issue）##########

issue_body() { # run attempt
  printf '%s\n<!-- triage-fingerprint:%s -->\n本文' "$(marker "$1" "$2")" "$FP_B"
}

# spec: 設計3（merge: 同じフィンガープリントのopenなIssueなし → Issueを作成）, F-07
t_P30__merge_creates_issue_when_none_open() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  run_post
  assert_eq "$POST_RC" 0 "終了コード: $(cat "$WORK/post.out")"
  assert_writes 1
  assert_eq "$(write_field 1 .method)" POST method
  assert_eq "$(write_field 1 .path)" "$ISSUES_PATH" path
  assert_contains "$(write_field 1 .fields.title)" "mainのCIが失敗しています（自動）"
  local body; body=$(write_body 1)
  assert_eq "$(first_line "$body")" "$(marker $MERGE_RUN_ID 1)" "1行目はマーカー"
  assert_eq "$(printf '%s\n' "$body" | sed -n 2p)" "<!-- triage-fingerprint:$FP_B -->" "2行目はフィンガープリント"
  assert_contains "$body" "- 要約：TestRound が失敗した（期待値3、実際2）"
  assert_eq "$(last_line "$body")" "@octocat" "末尾はメンション"
}

# spec: 設計3（merge: 同じフィンガープリントのopenなIssueあり、同じマーカーなし → 追記）, R-07
t_P31__merge_appends_to_existing_open_issue() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  seed_issue 50 open "$BOT" "$(issue_body 999 1)"
  run_post
  assert_eq "$POST_RC" 0 "終了コード: $(cat "$WORK/post.out")"
  assert_writes 1
  assert_eq "$(write_field 1 .method)" POST method
  assert_eq "$(write_field 1 .path)" "$ISSUES_PATH/50/comments" path
  assert_eq "$(first_line "$(write_body 1)")" "$(marker $MERGE_RUN_ID 1)" "先頭行はマーカー"
  assert_eq "$(issue_count)" 1 "新しいIssueは作らない"
}

# spec: 設計3, R-05（merge: 作成後に同じ run/attempt を再処理。書き込みゼロ）
t_P32__merge_reprocess_after_create_writes_nothing() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  run_post
  assert_writes 1
  run_post
  assert_eq "$POST_RC" 0 "2回目の終了コード"
  assert_writes 1
  assert_eq "$(issue_count)" 1 "Issueは1件"
}

# spec: 設計3, R-05（merge: 追記後に同じ run/attempt を再処理。書き込みゼロ）
t_P33__merge_reprocess_after_append_writes_nothing() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  seed_issue 50 open "$BOT" "$(issue_body 999 1)"
  run_post
  assert_writes 1
  run_post
  assert_eq "$POST_RC" 0 "2回目の終了コード"
  assert_writes 1
  assert_eq "$(comment_count 50)" 1 "追記は1件"
}

# spec: 設計3（merge: Issue本文に同じマーカーがある。書き込みゼロ）
t_P34__merge_marker_in_issue_body_means_done() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  seed_issue 50 open "$BOT" "$(issue_body $MERGE_RUN_ID 1)"
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 0
}

# spec: 設計3, R-21（merge: 別ユーザーが同じマーカーのコメントを書いている。処理済みにしない）
t_P35__merge_other_user_marker_comment_is_not_done() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  seed_issue 50 open "$BOT" "$(issue_body 999 1)"
  seed_comment 50 701 "mallory" "$(marker $MERGE_RUN_ID 1)"$'\n''偽の本文'
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 1
  assert_eq "$(write_field 1 .path)" "$ISSUES_PATH/50/comments" path
}

# spec: 設計3（merge: フィンガープリントが違う、または closed の Issue は、追記先にしない）
t_P36__merge_ignores_other_fingerprint_and_closed_issues() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  seed_issue 50 open "$BOT" "$(marker 999 1)"$'\n'"<!-- triage-fingerprint:$FP_C -->"$'\n''別の障害'
  seed_issue 51 closed "$BOT" "$(issue_body 999 1)"
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 1
  assert_eq "$(write_field 1 .path)" "$ISSUES_PATH" path
}

# spec: F-10, R-15, R-16（merge で結果がない: 定型の調査失敗のIssue）
t_P37__merge_missing_result_creates_fallback_issue() {
  ctx_from post/context.merge.json
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 1
  assert_eq "$(write_field 1 .path)" "$ISSUES_PATH" path
  assert_fallback_body "$(write_body 1)" "$MERGE_RUN_ID" 1
  assert_contains "$(write_body 1)" "<!-- triage-fingerprint:$FP_B -->"
}

# spec: R-09, F-08（merge: 通常の投稿のあとに定型の投稿。書き込みゼロ）
t_P38__merge_normal_then_fallback_writes_once() {
  ctx_from post/context.merge.json
  res_from post/result.test_failure.json
  run_post
  assert_writes 1
  rm -f "$TRIAGE_DIR/result.json"
  run_post
  assert_eq "$POST_RC" 0 "2回目の終了コード"
  assert_writes 1
}

# spec: S-03（merge の宛先も context から。結果が不正でも Issue の作成先は同じリポジトリ）
t_P39__merge_target_repository_comes_from_context() {
  ctx_from post/context.merge.json '.repository="tech-organization-mame/other-repo"'
  res_from post/result.extra_fields.json
  run_post
  assert_eq "$POST_RC" 0 "終了コード"
  assert_writes 1
  assert_eq "$(write_field 1 .path)" "repos/tech-organization-mame/other-repo/issues" path
}

########## 失敗時の挙動（CONTRACT 3.7 の決定）##########

# spec: CONTRACT 3.7（書き込みが失敗したら、終了コード非0。黙殺しない）
t_P40__write_failure_exits_nonzero() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  STUB_FAIL_WRITES=1 run_post
  assert_ne "$POST_RC" 0 "書き込み失敗時の終了コード"
}

# spec: CONTRACT 3.7（既存コメントを読めない: 重複を判定できないので、書き込まない。終了コード非0）
t_P41__read_failure_exits_nonzero_without_writes() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  STUB_FAIL_READS=1 run_post
  assert_ne "$POST_RC" 0 "読み取り失敗時の終了コード"
  assert_writes 0
}

########## テンプレート（D-15）##########

# spec: D-15（文面は、テンプレートのファイルで変えられる。折り畳みは、テンプレートが書く）
t_P42__default_pr_template_has_collapsed_evidence() {
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  assert_contains "$body" "<details>"
  assert_contains "$body" "<summary>根拠（ログの引用）</summary>"
  assert_contains "$body" "</details>"
  # 要約、原因の仮説、次の対応は、折り畳みの外（最初の画面）にある
  local before_details; before_details=${body%%<details>*}
  assert_contains "$before_details" "- 要約："
  assert_contains "$before_details" "- 原因の仮説："
  assert_contains "$before_details" "round.go の丸め処理を確認する"
  assert_not_contains "$before_details" "round_test.go:15"
}

# spec: D-15（テンプレートを差し替えると、スクリプトを変えずに、文面が変わる。AIの文字列は、再置換されない）
t_P43__custom_template_changes_format_and_is_not_reexpanded() {
  mkdir -p "$WORK/tpl"
  cat > "$WORK/tpl/pr-comment.md" <<'TPL'
{{marker}}
CUSTOM {{summary}}
{{mention_line}}
TPL
  export TRIAGE_TEMPLATE_DIR="$WORK/tpl"
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json '.summary = "x {{marker}} y"'
  run_post
  assert_pr_comment_created
  local body; body=$(write_body 1)
  assert_contains "$body" "CUSTOM x {{marker}} y"
  assert_eq "$(count_marker_lines "$body")" 1 "マーカーは、1行目の1つだけ"
}

# spec: D-15（未知の変数は、エラー。書き込まない）
t_P44__unknown_template_variable_fails_without_writes() {
  mkdir -p "$WORK/tpl"
  printf '%s
' '{{marker}}' '{{nope}}' > "$WORK/tpl/pr-comment.md"
  export TRIAGE_TEMPLATE_DIR="$WORK/tpl"
  ctx_from post/context.pr.json
  res_from post/result.test_failure.json
  run_post
  assert_ne "$POST_RC" 0 "終了コード"
  assert_writes 0
}

