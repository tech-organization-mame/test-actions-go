#!/usr/bin/env bash
# 準備：失敗した実行のログを取り、行ID（L<番号>）を付けて evidence/log.txt に置く。AIを使わない。
set -euo pipefail
EVIDENCE_DIR=${EVIDENCE_DIR:-evidence}
RUN_ID=$(jq -r .run_id "${TRIAGE_DIR:-triage}/context.json")
mkdir -p "$EVIDENCE_DIR"
gh run view "$RUN_ID" --log-failed 2>/dev/null \
  | sed 's/\r$//' | cut -f3- | sed -E 's/^[0-9T:.Z-]+ //' \
  | head -n 200 | awk '{ printf "L%d: %s\n", NR, $0 }' > "$EVIDENCE_DIR/log.txt"
