#!/usr/bin/env bash
# Search local source code without treating the query as a regular expression.
set -euo pipefail

usage() { echo "用法: $0 <关键词> [扩展名，例如 java|xml|sql]" >&2; }
KEYWORD="${1:-}"
EXT_FILTER="${2:-}"
[[ -n "$KEYWORD" ]] || { usage; exit 2; }
if [[ -n "$EXT_FILTER" && ! "$EXT_FILTER" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "错误：扩展名只允许字母、数字、下划线和连字符。" >&2; exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_root() {
  local dir="$PWD"
  while :; do
    if [[ -d "$dir/.git" || -f "$dir/.git" || -f "$dir/.lexiloom/config.json" || -f "$dir/pom.xml" || -f "$dir/package.json" || -f "$dir/pyproject.toml" ]]; then
      printf '%s\n' "$dir"; return 0
    fi
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  # Skill layout fallback: <repo>/.agents/skills/<name>/scripts/search_code.sh
  local candidate="$(cd "$SCRIPT_DIR/../../../../" 2>/dev/null && pwd || true)"
  if [[ -n "$candidate" && ( -d "$candidate/.git" || -f "$candidate/pom.xml" || -f "$candidate/package.json" ) ]]; then
    printf '%s\n' "$candidate"; return 0
  fi
  return 1
}
PROJECT_ROOT="$(find_root)" || { echo "错误：无法定位项目根目录，请在目标仓库中运行。" >&2; exit 2; }
cd "$PROJECT_ROOT"

if command -v rg >/dev/null 2>&1; then
  args=(--line-number --context 2 --ignore-case --fixed-strings --hidden
    -g '!**/.git/**' -g '!**/target/**' -g '!**/build/**' -g '!**/dist/**'
    -g '!**/node_modules/**' -g '!**/.idea/**' -g '!**/.venv/**' -g '!**/vendor/**'
    -g '!**/.lexiloom.env' -g '!**/.lexiloom/**' -g '!**/*.min.js' -g '!**/*.map')
  [[ -z "$EXT_FILTER" ]] || args+=( -g "*.${EXT_FILTER}" )
  set +e
  rg "${args[@]}" -- "$KEYWORD" . | head -n 160
  status=${PIPESTATUS[0]}
  set -e
  case "$status" in
    0) ;;
    1) echo "未找到匹配内容（关键词：$KEYWORD）。"; exit 0 ;;
    *) echo "代码检索执行失败（rg exit=$status）。请检查目录权限或检索参数。" >&2; exit "$status" ;;
  esac
else
  # grep fallback: search common source directories only; fixed-string mode avoids regex surprises.
  search_paths=()
  for d in src app lib packages; do [[ ! -d "$d" ]] || search_paths+=("$d"); done
  [[ ${#search_paths[@]} -gt 0 ]] || search_paths=(.)
  grep_args=(-RInF --exclude-dir=.git --exclude-dir=target --exclude-dir=build --exclude-dir=dist
    --exclude-dir=node_modules --exclude-dir=.idea --exclude-dir=.venv --exclude-dir=.lexiloom
    --exclude=.lexiloom.env --exclude='*.min.js' --exclude='*.map')
  [[ -z "$EXT_FILTER" ]] || grep_args+=(--include="*.${EXT_FILTER}")
  set +e
  grep "${grep_args[@]}" -- "$KEYWORD" "${search_paths[@]}" | head -n 160
  status=${PIPESTATUS[0]}
  set -e
  case "$status" in 0) ;; 1) echo "未找到匹配内容（关键词：$KEYWORD）。";; *) echo "代码检索执行失败（grep exit=$status）。" >&2; exit "$status";; esac
fi
