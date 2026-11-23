#!/usr/bin/env bash
# 準備：失敗した実行のログを取り、行ID（L<番号>）を付けて evidence/log.txt に置く。AIを使わない。
set -euo pipefail
EVIDENCE_DIR=${EVIDENCE_DIR:-evidence}
RUN_ID=$(jq -r .run_id "${TRIAGE_DIR:-triage}/context.json")
mkdir -p "$EVIDENCE_DIR"
# 取り除くもの：CR、ジョブ名とステップ名の列、BOM、タイムスタンプ、ANSIの色コード
gh run view "$RUN_ID" --log-failed 2>/dev/null \
  | sed 's/\r$//' | cut -f3- \
  | sed -E $'s/^\xef\xbb\xbf//; s/^[0-9T:.Z-]+ //; s/\x1b\[[0-9;]*[A-Za-z]//g' \
  | sed -E 's/\^\[\[[0-9;]*[A-Za-z]//g' \n  | head -n 200 | awk '{ printf "L%d: %s\n", NR, $0 }' > "$EVIDENCE_DIR/log.txt"
