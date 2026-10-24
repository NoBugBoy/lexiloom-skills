#!/usr/bin/env bash
# Query the LexiLoom REST search endpoint and render compact, evidence-oriented results.
set -euo pipefail

QUERY="${1:-}"
TOP_K="${2:-5}"
[[ -n "$QUERY" ]] || { echo "用法: $0 <自然语言检索问题> [topK，默认 5]" >&2; exit 2; }
[[ "$TOP_K" =~ ^[0-9]+$ ]] && (( TOP_K >= 1 && TOP_K <= 20 )) || { echo "错误：topK 必须是 1–20 的整数。" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_root() {
  local dir="$PWD"
  while :; do
    if [[ -f "$dir/.lexiloom/config.json" || -d "$dir/.git" || -f "$dir/.git" || -f "$dir/pom.xml" || -f "$dir/package.json" || -f "$dir/pyproject.toml" ]]; then printf '%s\n' "$dir"; return 0; fi
    [[ "$dir" == "/" ]] && break; dir="$(dirname "$dir")"
  done
  local candidate="$(cd "$SCRIPT_DIR/../../../../" 2>/dev/null && pwd || true)"
  if [[ -n "$candidate" && -f "$candidate/.lexiloom/config.json" ]]; then printf '%s\n' "$candidate"; return 0; fi
  return 1
}
PROJECT_ROOT="$(find_root)" || { echo "错误：无法定位项目根目录。请在目标仓库内运行。" >&2; exit 2; }
CONFIG_FILE="$PROJECT_ROOT/.lexiloom/config.json"
ENV_FILE="$PROJECT_ROOT/.lexiloom.env"
[[ -f "$CONFIG_FILE" ]] || { echo "错误：缺少 .lexiloom/config.json。请先运行 scripts/setup.sh。" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "错误：需要 Python 3 解析 JSON 配置。" >&2; exit 2; }

# Parse config as JSON; do not use grep for JSON or silently invent defaults.
CONFIG_VALUES="$(python3 - "$CONFIG_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f: c=json.load(f)
    url=c.get('serverUrl')
    ws=c.get('workspace') or {}
    wid=ws.get('id')
    name=ws.get('name') or ''
    if not isinstance(url,str) or not url.strip(): raise ValueError('serverUrl 缺失')
    if not url.startswith(('http://','https://')): raise ValueError('serverUrl 必须以 http:// 或 https:// 开头')
    if isinstance(wid,bool) or not isinstance(wid,int) or wid <= 0: raise ValueError('workspace.id 必须是正整数')
    print(url.rstrip('/')+'\t'+str(wid)+'\t'+name.replace('\n',' '))
except Exception as e:
    print('配置错误：'+str(e), file=sys.stderr); sys.exit(2)
PY
)" || exit $?
IFS=$'\t' read -r SERVER_URL WORKSPACE_ID WORKSPACE_NAME <<< "$CONFIG_VALUES"

# Environment variable intentionally takes precedence over the local env file.
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
  "$SERVER_URL/api/v1/openapi/knowledge/search" \
  --header "Authorization: Bearer $API_KEY" \
  --header 'X-Call-Source: CLI_SKILL' \
  --header 'Accept: application/json' \
  --data-urlencode "q=$QUERY" --data-urlencode "workspaceId=$WORKSPACE_ID" --data-urlencode "topK=$TOP_K")"
CURL_STATUS=$?
set -e
if (( CURL_STATUS != 0 )); then
  echo "知识库检索请求失败：网络错误或请求超时（curl exit=$CURL_STATUS）。请检查服务地址和网络。" >&2; exit 1
fi
case "$HTTP_CODE" in
  200) ;;
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
      echo "知识库检索失败（HTTP $HTTP_CODE）：$DETAIL" >&2
    else
      echo "知识库检索鉴权失败（HTTP $HTTP_CODE）。请检查 API Key 与工作空间访问权限。" >&2
    fi
    exit 1 ;;
  404) echo "知识库检索接口不存在（HTTP 404）：请确认后端已部署 /api/v1/openapi/knowledge/search。" >&2; exit 1 ;;
  429) echo "请求过于频繁（HTTP 429），请稍后重试。" >&2; exit 1 ;;
  5*) echo "知识库服务暂时异常（HTTP $HTTP_CODE），请检查后端日志。" >&2; exit 1 ;;
  *) echo "知识库检索请求失败（HTTP $HTTP_CODE）。响应正文已隐藏，避免意外泄露敏感信息。" >&2; exit 1 ;;
esac

python3 - "$TMP_BODY" "$WORKSPACE_ID" "$WORKSPACE_NAME" <<'PY'
import json, sys
path, workspace_id, workspace_name = sys.argv[1:]
try:
    with open(path, encoding='utf-8') as f: data=json.load(f)
except Exception:
    print('错误：服务端返回的不是有效 JSON。', file=sys.stderr); sys.exit(1)
if isinstance(data, dict):
    results=data.get('results')
    if results is None and isinstance(data.get('data'),dict): results=data['data'].get('results')
    if results is None: results=[]
elif isinstance(data,list): results=data
else: results=[]
if not isinstance(results,list):
    print('错误：响应中的 results 字段格式不正确。', file=sys.stderr); sys.exit(1)
print(f'知识库检索：{workspace_name or "未命名工作空间"}（ID: {workspace_id}）')
print(f'返回 {len(results)} 条切片。\n')
if not results:
    print('未检索到相关切片。可尝试换一种问法，或确认相关文档已入库。')
for i,item in enumerate(results,1):
    if not isinstance(item,dict): continue
    title=item.get('documentTitle') or '无标题'
    doc_id=item.get('documentId','未知')
    chunk=item.get('chunkIndex','未知')
    score=item.get('score')
    content=' '.join(str(item.get('content') or '').split())
    print(f'{i}. 文档：《{title}》 | 文档 ID: {doc_id} | 切片: {chunk} | 得分: {score if score is not None else "未提供"}')
    print(f'   {content[:1800]}')
    print()
PY
