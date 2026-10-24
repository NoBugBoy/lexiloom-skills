#!/usr/bin/env bash
# Search local source code without treating the query as a regular expression.
set -euo pipefail

usage() { echo "用法: $0 <关键词> [扩展名，例如 java|xml|sql]" >&2; }
if (( $# > 2 )); then
  usage
  exit 2
fi
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

command -v head >/dev/null 2>&1 || { echo "错误：需要 head 命令限制检索输出。" >&2; exit 2; }
command -v mktemp >/dev/null 2>&1 || { echo "错误：需要 mktemp 命令保存检索结果。" >&2; exit 2; }

# Do not pipe the search command directly into head.  With pipefail, head can
# close the pipe early and make rg/grep report SIGPIPE; with nounset, reading
# PIPESTATUS[0] is also unsafe when the special array is not populated.
if ! TMP_OUTPUT="$(mktemp)"; then
  echo "错误：无法创建临时文件保存检索结果。请检查临时目录权限。" >&2
  exit 1
fi
trap 'rm -f -- "$TMP_OUTPUT"' EXIT

if command -v rg >/dev/null 2>&1; then
  args=(--line-number --context 2 --ignore-case --fixed-strings --hidden
    -g '!**/.git/**' -g '!**/target/**' -g '!**/build/**' -g '!**/dist/**'
    -g '!**/node_modules/**' -g '!**/.idea/**' -g '!**/.venv/**' -g '!**/vendor/**'
    -g '!**/.lexiloom.env' -g '!**/.lexiloom/**' -g '!**/*.min.js' -g '!**/*.map')
  [[ -z "$EXT_FILTER" ]] || args+=( -g "*.${EXT_FILTER}" )
  if rg "${args[@]}" -- "$KEYWORD" . >"$TMP_OUTPUT"; then
    status=0
  else
    status=$?
  fi
  case "$status" in
    0) head -n 160 "$TMP_OUTPUT" ;;
    1) echo "未找到匹配内容（关键词：$KEYWORD）。"; exit 0 ;;
    *) echo "代码检索执行失败（rg exit=$status）。请检查目录权限或检索参数。" >&2; exit "$status" ;;
  esac
else
  # grep fallback: search common source directories only; fixed-string mode avoids regex surprises.
  command -v grep >/dev/null 2>&1 || { echo "错误：rg 和 grep 均不可用，无法执行代码检索。" >&2; exit 2; }
  search_paths=()
  for d in src app lib packages; do [[ ! -d "$d" ]] || search_paths+=("$d"); done
  [[ ${#search_paths[@]} -gt 0 ]] || search_paths=(.)
  # -r avoids following symlinked directories; -I skips binary blobs that are
  # not useful as source-code evidence.
  grep_args=(-rInF -I --exclude-dir=.git --exclude-dir=target --exclude-dir=build --exclude-dir=dist
    --exclude-dir=node_modules --exclude-dir=.idea --exclude-dir=.venv --exclude-dir=.lexiloom
    --exclude=.lexiloom.env --exclude='*.min.js' --exclude='*.map')
  [[ -z "$EXT_FILTER" ]] || grep_args+=(--include="*.${EXT_FILTER}")
  if grep "${grep_args[@]}" -- "$KEYWORD" "${search_paths[@]}" >"$TMP_OUTPUT"; then
    status=0
  else
    status=$?
  fi
  case "$status" in
    0) head -n 160 "$TMP_OUTPUT" ;;
    1) echo "未找到匹配内容（关键词：$KEYWORD）。"; exit 0 ;;
    *) echo "代码检索执行失败（grep exit=$status）。" >&2; exit "$status" ;;
  esac
fi
