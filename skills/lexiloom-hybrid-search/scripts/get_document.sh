#!/usr/bin/env bash
# Fetch and print one LexiLoom document's full detail response.
set -euo pipefail

DOCUMENT_ID="${1:-}"
[[ "$DOCUMENT_ID" =~ ^[1-9][0-9]*$ ]] || { echo "用法: $0 <正整数 documentId>" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_root() {
  local dir="$PWD"
  while :; do
    if [[ -f "$dir/.lexiloom/config.json" || -d "$dir/.git" || -f "$dir/.git" || -f "$dir/pom.xml" || -f "$dir/package.json" || -f "$dir/pyproject.toml" ]]; then printf '%s\n' "$dir"; return 0; fi
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  local candidate="$(cd "$SCRIPT_DIR/../../../../" 2>/dev/null && pwd || true)"
  if [[ -n "$candidate" && -f "$candidate/.lexiloom/config.json" ]]; then printf '%s\n' "$candidate"; return 0; fi
  return 1
}
PROJECT_ROOT="$(find_root)" || { echo "错误：无法定位项目根目录。请在目标仓库内运行。" >&2; exit 2; }
CONFIG_FILE="$PROJECT_ROOT/.lexiloom/config.json"
ENV_FILE="$PROJECT_ROOT/.lexiloom.env"
[[ -f "$CONFIG_FILE" ]] || { echo "错误：缺少 .lexiloom/config.json。请先运行 scripts/setup.sh。" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "错误：需要 Python 3 解析 JSON 配置和详情。" >&2; exit 2; }

SERVER_URL="$(python3 - "$CONFIG_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f: config=json.load(f)
    url=config.get('serverUrl')
    if not isinstance(url,str) or not url.strip(): raise ValueError('serverUrl 缺失')
    if not url.startswith(('http://','https://')): raise ValueError('serverUrl 必须以 http:// 或 https:// 开头')
    print(url.rstrip('/'))
except Exception as e:
    print('配置错误：'+str(e), file=sys.stderr); sys.exit(2)
PY
)" || exit $?

API_KEY="${LEXILOOM_API_KEY:-}"
if [[ -z "$API_KEY" && -f "$ENV_FILE" ]]; then
  API_KEY="$(python3 - "$ENV_FILE" <<'PY'
import sys
for line in open(sys.argv[1], encoding='utf-8'):
    line=line.strip()
    if line.startswith('LEXILOOM_API_KEY='):
        print(line.split('=',1)[1]); break
PY
)"
fi
[[ -n "$API_KEY" ]] || { echo "错误：未读取到 API Key。请设置 LEXILOOM_API_KEY 或配置 .lexiloom.env。" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "错误：需要 curl。" >&2; exit 2; }

TMP_BODY="$(mktemp)"
trap 'rm -f "$TMP_BODY"' EXIT
set +e
HTTP_CODE="$(curl --silent --show-error --get \
  --connect-timeout 5 --max-time 30 \
  --output "$TMP_BODY" --write-out '%{http_code}' \
  "$SERVER_URL/api/v1/openapi/documents/$DOCUMENT_ID" \
  --header "Authorization: Bearer $API_KEY" \
  --header 'Accept: application/json')"
CURL_STATUS=$?
set -e
if (( CURL_STATUS != 0 )); then
  echo "文档详情请求失败：网络错误或请求超时（curl exit=$CURL_STATUS）。请检查服务地址和网络。" >&2; exit 1
fi
case "$HTTP_CODE" in
  200) ;;
  400) echo "文档详情请求参数错误（HTTP 400）。请确认 documentId 是正整数。" >&2; exit 1 ;;
  401|403)
    DETAIL="$(python3 - "$TMP_BODY" <<'PY'
import json, re, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f: detail=json.load(f).get('detail', '')
    if isinstance(detail, str):
        detail=re.sub(r'[\x00-\x1f\x7f]+', ' ', detail).strip()[:300]
        print(detail)
except Exception:
    pass
PY
)"
    if [[ -n "$DETAIL" ]]; then
      echo "文档详情请求失败（HTTP $HTTP_CODE）：$DETAIL" >&2
    elif [[ "$HTTP_CODE" == 401 ]]; then
      echo "文档详情鉴权失败（HTTP 401）。请检查 API Key。" >&2
    else
      echo "无权读取文档（HTTP 403）。请确认当前凭证对该文档具有读取权限。" >&2
    fi
    exit 1 ;;
  404) echo "文档详情请求返回 HTTP 404：文档可能不存在，也可能是详情端点未部署或路径不匹配。" >&2; exit 1 ;;
  429) echo "请求过于频繁（HTTP 429），请稍后重试。" >&2; exit 1 ;;
  5*) echo "知识库服务暂时异常（HTTP $HTTP_CODE），请检查后端日志。" >&2; exit 1 ;;
  *) echo "文档详情请求失败（HTTP $HTTP_CODE）。响应正文已隐藏，避免意外泄露敏感信息。" >&2; exit 1 ;;
esac

python3 - "$TMP_BODY" "$DOCUMENT_ID" <<'PY'
import json, sys
path, requested_id = sys.argv[1:]
try:
    with open(path, encoding='utf-8') as f: doc=json.load(f)
except Exception:
    print('错误：服务端返回的不是有效 JSON。', file=sys.stderr); sys.exit(1)
if not isinstance(doc, dict):
    print('错误：文档详情响应应为 JSON 对象。', file=sys.stderr); sys.exit(1)
if 'content' not in doc:
    print('错误：详情响应缺少 content 字段，无法作为完整正文使用。', file=sys.stderr); sys.exit(1)
if str(doc.get('id', '')) != requested_id:
    print('错误：详情响应的 id 与请求的 documentId 不一致。', file=sys.stderr); sys.exit(1)
print('文档详情（字段值按服务端响应展示）')
for key in ('id', 'title', 'workspaceId', 'categoryName', 'status', 'version', 'createTime', 'updateTime'):
    print(f'{key}: {json.dumps(doc.get(key), ensure_ascii=False)}')
print('\n--- Markdown 正文 content 开始 ---\n')
content=doc.get('content')
if content is None:
    print('[content 为 null]')
elif isinstance(content, str):
    print(content, end='' if content.endswith('\n') else '\n')
else:
    print(json.dumps(content, ensure_ascii=False))
print('\n--- Markdown 正文 content 结束 ---')
PY
