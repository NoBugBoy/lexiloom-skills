#!/usr/bin/env bash
# Search local source code without treating the query as a regular expression.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

usage() {
  echo "用法: $0 <关键词> [扩展名，支持单个或多个如 java 或 java|xml|sql]" >&2
}

if (( $# > 2 )); then
  usage
  exit 2
fi

KEYWORD="${1:-}"
EXT_FILTER="${2:-}"
[[ -n "$KEYWORD" ]] || { usage; exit 2; }

# Allow single extension (java) or pipe/comma-separated extensions (java|xml|sql or java,xml)
if [[ -n "$EXT_FILTER" && ! "$EXT_FILTER" =~ ^[A-Za-z0-9_-]+([|,][A-Za-z0-9_-]+)*$ ]]; then
  echo "错误：扩展名只允许字母、数字、下划线和连字符，多个扩展名可用 | 或 , 分隔（如 java|xml|sql）。" >&2
  exit 2
fi

PROJECT_ROOT="$(find_project_root "$SCRIPT_DIR")" || {
  echo "错误：无法定位项目根目录，请在目标仓库中运行。" >&2
  exit 2
}
cd "$PROJECT_ROOT"

command -v head >/dev/null 2>&1 || { echo "错误：需要 head 命令限制检索输出。" >&2; exit 2; }
command -v wc >/dev/null 2>&1 || { echo "错误：需要 wc 命令统计检索输出。" >&2; exit 2; }
command -v mktemp >/dev/null 2>&1 || { echo "错误：需要 mktemp 命令保存检索结果。" >&2; exit 2; }

if ! TMP_OUTPUT="$(mktemp)"; then
  echo "错误：无法创建临时文件保存检索结果。请检查临时目录权限。" >&2
  exit 1
fi
trap 'rm -f -- "$TMP_OUTPUT"' EXIT

MAX_LINES=160

# Split extensions into array if provided
exts=()
if [[ -n "$EXT_FILTER" ]]; then
  IFS='|,' read -r -a exts <<< "$EXT_FILTER"
fi

# Load custom excludePatterns from .lexiloom/config.json if available
custom_excludes=()
CONFIG_FILE="$PROJECT_ROOT/.lexiloom/config.json"
if [[ -f "$CONFIG_FILE" ]] && command -v python3 >/dev/null 2>&1; then
  while IFS= read -r pat; do
    [[ -z "$pat" ]] || custom_excludes+=("$pat")
  done < <(python3 - "$CONFIG_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        c = json.load(f)
    pats = (c.get('search') or {}).get('excludePatterns') or []
    if isinstance(pats, list):
        for p in pats:
            if isinstance(p, str) and p.strip():
                print(p.strip())
except Exception:
    pass
PY
  )
fi

print_results() {
  local total_lines
  total_lines="$(wc -l < "$TMP_OUTPUT" | tr -d ' ')"
  head -n "$MAX_LINES" "$TMP_OUTPUT"
  if (( total_lines > MAX_LINES )); then
    echo ""
    echo "[提示] 代码检索共输出 ${total_lines} 行，以上仅展示前 ${MAX_LINES} 行。请使用更精确的符号名或指定文件扩展名缩小范围。"
  fi
}

if command -v rg >/dev/null 2>&1; then
  args=(--line-number --context 2 --ignore-case --fixed-strings --hidden --max-count 50
    -g '!**/.git/**' -g '!**/target/**' -g '!**/build/**' -g '!**/dist/**'
    -g '!**/node_modules/**' -g '!**/.idea/**' -g '!**/.venv/**' -g '!**/vendor/**'
    -g '!**/.lexiloom.env' -g '!**/.lexiloom/**' -g '!**/*.min.js' -g '!**/*.map')
  if (( ${#custom_excludes[@]} > 0 )); then
    for pat in "${custom_excludes[@]}"; do
      args+=( -g "!${pat#!}" )
    done
  fi
  if (( ${#exts[@]} > 0 )); then
    for ext in "${exts[@]}"; do
      args+=( -g "*.${ext}" )
    done
  fi
  if rg "${args[@]}" -- "$KEYWORD" . >"$TMP_OUTPUT"; then
    status=0
  else
    status=$?
  fi
  case "$status" in
    0) print_results ;;
    1) echo "未找到匹配内容（关键词：$KEYWORD）。"; exit 0 ;;
    *) echo "代码检索执行失败（rg exit=$status）。请检查目录权限或检索参数。" >&2; exit "$status" ;;
  esac
else
  # grep fallback: search common source directories only; fixed-string mode avoids regex surprises.
  command -v grep >/dev/null 2>&1 || { echo "错误：rg 和 grep 均不可用，无法执行代码检索。" >&2; exit 2; }
  search_paths=()
  for d in src app lib packages cmd pkg internal; do
    [[ ! -d "$d" ]] || search_paths+=("$d")
  done
  [[ ${#search_paths[@]} -gt 0 ]] || search_paths=(.)
  grep_args=(-rInF -I -m 50
    --exclude-dir=.git --exclude-dir=target --exclude-dir=build --exclude-dir=dist
    --exclude-dir=node_modules --exclude-dir=.idea --exclude-dir=.venv --exclude-dir=.lexiloom
    --exclude=.lexiloom.env --exclude='*.min.js' --exclude='*.map')
  if (( ${#exts[@]} > 0 )); then
    for ext in "${exts[@]}"; do
      grep_args+=(--include="*.${ext}")
    done
  fi
  if grep "${grep_args[@]}" -- "$KEYWORD" "${search_paths[@]}" >"$TMP_OUTPUT"; then
    status=0
  else
    status=$?
  fi
  case "$status" in
    0) print_results ;;
    1) echo "未找到匹配内容（关键词：$KEYWORD）。"; exit 0 ;;
    *) echo "代码检索执行失败（grep exit=$status）。" >&2; exit "$status" ;;
  esac
fi
