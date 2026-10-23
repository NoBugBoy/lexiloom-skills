#!/usr/bin/env bash
# Configure the repository-to-workspace binding for LexiLoom.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_root() {
  local dir="$PWD"
  while :; do
    if [[ -d "$dir/.git" || -f "$dir/.git" || -f "$dir/pom.xml" || -f "$dir/package.json" || -f "$dir/pyproject.toml" || -d "$dir/.lexiloom" ]]; then printf '%s\n' "$dir"; return 0; fi
    [[ "$dir" == "/" ]] && break; dir="$(dirname "$dir")"
  done
  local candidate="$(cd "$SCRIPT_DIR/../../../../" 2>/dev/null && pwd || true)"
  if [[ -n "$candidate" && ( -d "$candidate/.git" || -f "$candidate/pom.xml" || -f "$candidate/package.json" ) ]]; then printf '%s\n' "$candidate"; return 0; fi
  return 1
}
PROJECT_ROOT="$(find_root)" || { echo "错误：无法定位项目根目录。请在目标仓库内运行此脚本。" >&2; exit 2; }
CONFIG_DIR="$PROJECT_ROOT/.lexiloom"
CONFIG_FILE="$CONFIG_DIR/config.json"
ENV_FILE="$PROJECT_ROOT/.lexiloom.env"
command -v python3 >/dev/null 2>&1 || { echo "错误：setup 需要 Python 3 用于安全地读写 JSON。" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "错误：setup 需要 curl。" >&2; exit 2; }

DEFAULT_URL="http://localhost:8080"
if [[ -f "$CONFIG_FILE" ]]; then
  existing="$(python3 - "$CONFIG_FILE" <<'PY'
import json,sys
try:
 c=json.load(open(sys.argv[1],encoding='utf-8')); print(c.get('serverUrl',''))
except Exception: pass
PY
)"
  [[ -z "$existing" ]] || DEFAULT_URL="$existing"
fi
read -r -p "LexiLoom 服务端地址 [${DEFAULT_URL}]: " INPUT_URL
SERVER_URL="${INPUT_URL:-$DEFAULT_URL}"
SERVER_URL="${SERVER_URL%/}"
python3 - "$SERVER_URL" <<'PY'
import sys, urllib.parse
u=urllib.parse.urlparse(sys.argv[1])
if u.scheme not in ('http','https') or not u.netloc or u.username or u.password:
 print('错误：服务地址必须是有效的 http(s) URL，且不能包含用户名或密码。',file=sys.stderr); sys.exit(2)
PY

# Environment variable has precedence over the local env file.
API_KEY="${LEXILOOM_API_KEY:-}"
if [[ -z "$API_KEY" && -f "$ENV_FILE" ]]; then
  API_KEY="$(python3 - "$ENV_FILE" <<'PY'
import sys
for line in open(sys.argv[1],encoding='utf-8'):
 line=line.strip()
 if line.startswith('LEXILOOM_API_KEY='):
  print(line.split('=',1)[1]); break
PY
)"
fi
if [[ -z "$API_KEY" ]]; then
  echo "请输入当前 MVP 使用的 LexiLoom API Key（输入内容不会显示）。"
  read -r -s -p "API Key: " API_KEY; echo
fi
[[ -n "$API_KEY" ]] || { echo "错误：API Key 不能为空。" >&2; exit 2; }

TMP_BODY="$(mktemp)"; trap 'rm -f "$TMP_BODY"' EXIT
set +e
HTTP_CODE="$(curl --silent --show-error --connect-timeout 5 --max-time 20 \
  --output "$TMP_BODY" --write-out '%{http_code}' \
  "$SERVER_URL/api/ai/mcp/workspaces" \
  --header "Authorization: Bearer $API_KEY" --header 'Accept: application/json')"
CURL_STATUS=$?
set -e
if (( CURL_STATUS != 0 )); then echo "连接失败或超时。请检查服务地址和网络；未写入配置。" >&2; exit 1; fi
case "$HTTP_CODE" in
  200) ;;
  401|403) echo "鉴权失败（HTTP $HTTP_CODE）。请检查 API Key；未写入配置。" >&2; exit 1 ;;
  404) echo "工作空间发现接口不存在（HTTP 404）。请先部署 /api/ai/mcp/workspaces；未写入配置。" >&2; exit 1 ;;
  *) echo "读取工作空间失败（HTTP $HTTP_CODE）。未写入配置。" >&2; exit 1 ;;
esac

python3 - "$TMP_BODY" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1],encoding='utf-8'))
 if isinstance(d,dict) and isinstance(d.get('data'),list): d=d['data']
 if not isinstance(d,list): raise ValueError('响应应为工作空间数组')
 for w in d:
  if not isinstance(w,dict) or isinstance(w.get('id'),bool) or not str(w.get('id','')).isdigit() or int(w['id'])<=0 or not w.get('name'):
   raise ValueError('工作空间项缺少有效的正整数 id 或 name')
 if not d: raise ValueError('当前凭证没有可用工作空间')
except Exception as e:
 print('工作空间响应无效：'+str(e),file=sys.stderr); sys.exit(2)
for w in d: print(f"[{w['id']}] {w['name']}" + (f" — {w['description']}" if w.get('description') else ''))
PY

# Read valid IDs and select one explicitly; never silently bind to ID=1.
read -r -p "请输入要绑定的工作空间 ID（必须来自上方列表）: " WORKSPACE_ID
WORKSPACE_NAME="$(python3 - "$TMP_BODY" "$WORKSPACE_ID" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1],encoding='utf-8'))
 if isinstance(d,dict) and isinstance(d.get('data'),list): d=d['data']
 for w in d:
  if str(w.get('id'))==sys.argv[2]: print(w.get('name','')); sys.exit(0)
except Exception: pass
sys.exit(1)
PY
)" || { echo "错误：选择的 ID 不在服务端返回的工作空间列表中。未写入配置。" >&2; exit 2; }

mkdir -p "$CONFIG_DIR"
python3 - "$CONFIG_FILE" "$SERVER_URL" "$WORKSPACE_ID" "$WORKSPACE_NAME" <<'PY'
import json,sys,os
path,url,wid,name=sys.argv[1:]
config={
 'version':'1.0.0','serverUrl':url,
 'workspace':{'id':int(wid),'name':name},
 'search':{'useWorkspaceDefaults':True,'codeScope':['src/main/java','src/main/resources'],
           'excludePatterns':['**/target/**','**/.git/**','**/node_modules/**','**/build/**']}
}
tmp=path+'.tmp'
with open(tmp,'w',encoding='utf-8') as f: json.dump(config,f,ensure_ascii=False,indent=2); f.write('\n')
os.replace(tmp,path)
PY

# Credentials stay local; make sure ignore rules exist even if .gitignore did not.
GITIGNORE="$PROJECT_ROOT/.gitignore"
touch "$GITIGNORE"
if ! grep -Fxq '.lexiloom.env' "$GITIGNORE"; then printf '\n# LexiLoom local credentials (do not commit)\n.lexiloom.env\n' >> "$GITIGNORE"; fi
umask 077
printf '# Local LexiLoom credentials; do not commit.\nLEXILOOM_API_KEY=%s\n' "$API_KEY" > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "初始化完成。"
echo "项目配置：.lexiloom/config.json（可提交；请确认其中不包含秘密）"
echo "本地凭证：.lexiloom.env（权限已设为 600，并加入 .gitignore）"
echo "绑定工作空间：${WORKSPACE_NAME}（ID: ${WORKSPACE_ID}）"
