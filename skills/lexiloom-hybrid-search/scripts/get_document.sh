#!/usr/bin/env bash
# Fetch and print one LexiLoom document's full detail response.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

DOCUMENT_ID="${1:-}"
MAX_CHARS="${2:-30000}"
[[ "$DOCUMENT_ID" =~ ^[1-9][0-9]*$ ]] || {
  echo "用法: $0 <正整数 documentId> [最大字符数，默认 30000，传 0 表示不截断]" >&2
  exit 2
}
[[ "$MAX_CHARS" =~ ^[0-9]+$ ]] || {
  echo "错误：最大字符数必须是非负整数（传 0 表示不截断）。" >&2
  exit 2
}

PROJECT_ROOT="$(find_project_root "$SCRIPT_DIR")" || {
  echo "错误：无法定位项目根目录。请在目标仓库内运行。" >&2
  exit 2
}
CONFIG_FILE="$PROJECT_ROOT/.lexiloom/config.json"
ENV_FILE="$PROJECT_ROOT/.lexiloom.env"

command -v python3 >/dev/null 2>&1 || { echo "错误：需要 Python 3 解析 JSON 配置和详情。" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "错误：需要 curl。" >&2; exit 2; }

CONFIG_VALUES="$(load_lexiloom_config "$CONFIG_FILE")" || exit $?
IFS=$'\t' read -r SERVER_URL _ _ <<< "$CONFIG_VALUES"

API_KEY="$(load_api_key "$ENV_FILE")"
[[ -n "$API_KEY" ]] || {
  echo "错误：未读取到 API Key。请设置 LEXILOOM_API_KEY 环境变量或运行 scripts/setup.sh 配置 .lexiloom.env。" >&2
  exit 2
}

TMP_BODY="$(mktemp)"
trap 'rm -f "$TMP_BODY"' EXIT

set +e
HTTP_CODE="$(lexiloom_curl_get "$TMP_BODY" "$API_KEY" 5 30 \
  "$SERVER_URL/api/v1/openapi/documents/$DOCUMENT_ID")"
CURL_STATUS=$?
set -e

if (( CURL_STATUS != 0 )); then
  echo "文档详情请求失败：网络错误或请求超时（curl exit=$CURL_STATUS）。请检查服务地址和网络。" >&2
  exit 1
fi

case "$HTTP_CODE" in
  200) ;;
  400)
    echo "文档详情请求参数错误（HTTP 400）。请确认 documentId 是正整数。" >&2
    exit 1 ;;
  401|403)
    DETAIL="$(extract_problem_detail "$TMP_BODY")"
    if [[ -n "$DETAIL" ]]; then
      echo "文档详情请求失败（HTTP $HTTP_CODE）：$DETAIL" >&2
    elif [[ "$HTTP_CODE" == 401 ]]; then
      echo "文档详情鉴权失败（HTTP 401）。请检查 API Key。" >&2
    else
      echo "无权读取文档（HTTP 403）。请确认当前凭证具有 doc:read 权限及该文档访问权限。" >&2
    fi
    exit 1 ;;
  404)
    echo "文档详情请求返回 HTTP 404：文档可能不存在，也可能是详情端点未部署或路径不匹配。" >&2
    exit 1 ;;
  429)
    echo "请求过于频繁（HTTP 429），请稍后重试。" >&2
    exit 1 ;;
  5*)
    echo "知识库服务暂时异常（HTTP $HTTP_CODE），请检查后端日志。" >&2
    exit 1 ;;
  *)
    echo "文档详情请求失败（HTTP $HTTP_CODE）。响应正文已隐藏，避免意外泄露敏感信息。" >&2
    exit 1 ;;
esac

python3 - "$TMP_BODY" "$DOCUMENT_ID" "$MAX_CHARS" <<'PY'
import json, sys

path, requested_id, max_chars_raw = sys.argv[1:]
max_chars = int(max_chars_raw)
try:
    with open(path, encoding='utf-8') as f:
        doc = json.load(f)
except Exception:
    print('错误：服务端返回的不是有效 JSON。', file=sys.stderr)
    sys.exit(1)

if isinstance(doc, dict) and 'content' not in doc and isinstance(doc.get('data'), dict):
    doc = doc['data']

if not isinstance(doc, dict):
    print('错误：文档详情响应应为 JSON 对象。', file=sys.stderr)
    sys.exit(1)
if 'content' not in doc:
    print('错误：详情响应缺少 content 字段，无法作为完整正文使用。', file=sys.stderr)
    sys.exit(1)
if str(doc.get('id', '')) != requested_id:
    print('错误：详情响应的 id 与请求的 documentId 不一致。', file=sys.stderr)
    sys.exit(1)

print('文档详情（字段值按服务端响应展示）')
for key in ('id', 'title', 'workspaceId', 'categoryName', 'status', 'version', 'createTime', 'updateTime'):
    print(f'{key}: {json.dumps(doc.get(key), ensure_ascii=False)}')
print('\n--- Markdown 正文 content 开始 ---\n')
content = doc.get('content')
if content is None:
    print('[content 为 null]')
elif isinstance(content, str):
    if max_chars > 0 and len(content) > max_chars:
        snippet = content[:max_chars]
        print(snippet, end='' if snippet.endswith('\n') else '\n')
        print(f'\n[提示：文档全文共 {len(content)} 字符，已截断展示前 {max_chars} 字符。如需不截断全文，请执行 get_document.sh {requested_id} 0]')
    else:
        print(content, end='' if content.endswith('\n') else '\n')
else:
    print(json.dumps(content, ensure_ascii=False))
print('\n--- Markdown 正文 content 结束 ---')
PY
