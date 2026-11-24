#!/usr/bin/env bash
# 全ケースを実行する。使い方: bash tests/run.sh [名前の部分一致]
# 記事版：ARTICLE=1 SCRIPTS_DIR=article CORE=1 bash tests/run.sh
# 失敗が1件でもあれば、終了コード1。
set -u
T_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$T_DIR/.." && pwd)
export T_DIR REPO_ROOT
chmod +x "$T_DIR/stubs/gh" 2>/dev/null || true

command -v jq > /dev/null || { echo "jq が必要" >&2; exit 2; }

filter=${1:-}
pass=0
failn=0
failed=()

for f in "$T_DIR"/cases/*.sh; do
  for name in $(grep -oE '^t_[A-Za-z0-9_]+' "$f"); do
    if [ -n "$filter" ] && [[ $name != *"$filter"* ]]; then continue; fi
    # CORE=1：中核のテスト（tests/core.txt）だけ。記事版のコードの確認に使う
    if [ -n "${CORE:-}" ] && ! grep -qx "${name%%__*}" "$T_DIR/core.txt"; then continue; fi
    work=$(mktemp -d)
    out=$(
      (
        export WORK="$work"
        cd "$work" || exit 1
        # shellcheck disable=SC1090
        source "$T_DIR/lib/common.sh"
        source "$f"
        setup_case
        "$name"
        check_no_unsupported
      ) 2>&1
    )
    rc=$?
    if [ "$rc" -eq 0 ]; then
      pass=$((pass + 1))
      echo "PASS  $name"
    else
      failn=$((failn + 1))
      failed+=("$name")
      echo "FAIL  $name"
      printf '%s\n' "$out" | sed 's/^/        /'
    fi
    rm -rf "$work"
  done
done

echo
echo "合計 $((pass + failn)) 件: 成功 $pass、失敗 $failn"
if [ "$failn" -gt 0 ]; then
  printf '失敗: %s\n' "${failed[@]}"
  exit 1
fi
exit 0
