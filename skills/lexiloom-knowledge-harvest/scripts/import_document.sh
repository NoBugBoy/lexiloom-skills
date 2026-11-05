#!/usr/bin/env bash
# Import a structured or verified document into LexiLoom via POST /api/v1/openapi/documents/import.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

FILE_PATH=""
OPT_TITLE=""
OPT_CATEGORY_ID=""
OPT_CATEGORY_NAME=""
OPT_WORKSPACE_ID=""
OPT_TIMEOUT=180

usage() {
  cat <<'EOF'
用法:
  bash import_document.sh <文件路径> [选项]

支持的文件类型:
  .pdf, .docx, .doc, .xlsx, .xls, .pptx, .ppt, .txt, .md, .csv, .tsv, .html, .htm, .json

选项:
  --title <标题>              指定知识库文档标题（默认使用文件名）
  --category-id <ID>          指定归属分类 ID
  --category-name <分类名>    指定归属分类名称
  --workspace-id <ID>         覆盖项目绑定的工作空间 ID
  --timeout <秒数>            自定义请求超时时间（默认 180 秒）
  -h, --help                  显示帮助信息

示例:
  # 导入提炼好的 Markdown 知识文档
  bash import_document.sh "docs/customer_issue_sop.md" --title "客户支付超时排查指南与解决方案"

  # 导入测试用例表格并指定分类
  bash import_document.sh "testcases/payment_regression.xlsx" --category-name "测试用例"
EOF
  exit 0
}

# Parse positional argument and flags
while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      ;;
    --title)
      OPT_TITLE="${2:-}"
      shift 2 || { echo "错误：--title 缺少参数值。" >&2; exit 2; }
      ;;
    --category-id)
      OPT_CATEGORY_ID="${2:-}"
      shift 2 || { echo "错误：--category-id 缺少参数值。" >&2; exit 2; }
      ;;
    --category-name)
      OPT_CATEGORY_NAME="${2:-}"
      shift 2 || { echo "错误：--category-name 缺少参数值。" >&2; exit 2; }
      ;;
    --workspace-id)
      OPT_WORKSPACE_ID="${2:-}"
      shift 2 || { echo "错误：--workspace-id 缺少参数值。" >&2; exit 2; }
      ;;
    --timeout)
      OPT_TIMEOUT="${2:-}"
      shift 2 || { echo "错误：--timeout 缺少参数值。" >&2; exit 2; }
      [[ "$OPT_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "错误：--timeout 必须为正整数。" >&2; exit 2; }
      ;;
    -*)
      echo "错误：未知选项 $1（使用 -h 或 --help 查看用法）" >&2
      exit 2
      ;;
    *)
      if [[ -z "$FILE_PATH" ]]; then
        FILE_PATH="$1"
        shift
      else
        echo "错误：多余的位置参数 $1" >&2
        exit 2
      fi
      ;;
  esac
done

[[ -n "$FILE_PATH" ]] || {
  echo "错误：必须指定待导入的文件路径。" >&2
  echo "用法: $0 <文件路径> [--title <标题>] [--category-id <id>] [--category-name <name>]" >&2
  exit 2
}

[[ -f "$FILE_PATH" ]] || {
  echo "错误：指定的文件不存在或不是普通文件: $FILE_PATH" >&2
  exit 2
}

FILE_SIZE="$(wc -c < "$FILE_PATH" | tr -d ' ')"
if (( FILE_SIZE == 0 )); then
  echo "错误：待导入文件为空（0 字节），拒绝导入。" >&2
  exit 2
fi

# Resolve canonical absolute path and file metadata
FILE_DIR="$(cd "$(dirname "$FILE_PATH")" && pwd)"
FILENAME="$(basename "$FILE_PATH")"
FILE_ABS_PATH="${FILE_DIR}/${FILENAME}"

EXT="${FILENAME##*.}"
EXT_LOWER="$(echo "$EXT" | tr '[:upper:]' '[:lower:]')"

SUPPORTED_EXTS="^(pdf|docx|doc|xlsx|xls|pptx|ppt|txt|md|csv|tsv|html|htm|json)$"
if [[ ! "$EXT_LOWER" =~ $SUPPORTED_EXTS ]]; then
  echo "错误：不支持的文件类型 (.$EXT)。" >&2
  echo "支持的格式包含: .pdf, .docx, .doc, .xlsx, .xls, .pptx, .ppt, .txt, .md, .csv, .tsv, .html, .htm, .json" >&2
  echo "对于零散碎片内容，建议整理、提炼并合并为一个高质量的 .md 文件后再执行导入。" >&2
  exit 2
fi

# Map MIME type
get_mime_type() {
  case "$1" in
    pdf)   echo "application/pdf" ;;
    docx)  echo "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ;;
    doc)   echo "application/msword" ;;
    xlsx)  echo "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ;;
    xls)   echo "application/vnd.ms-excel" ;;
    pptx)  echo "application/vnd.openxmlformats-officedocument.presentationml.presentation" ;;
    ppt)   echo "application/vnd.ms-powerpoint" ;;
    txt)   echo "text/plain" ;;
    md)    echo "text/markdown" ;;
    csv)   echo "text/csv" ;;
    tsv)   echo "text/tab-separated-values" ;;
    html)  echo "text/html" ;;
    htm)   echo "text/html" ;;
    json)  echo "application/json" ;;
    *)     echo "application/octet-stream" ;;
  esac
}
MIME_TYPE="$(get_mime_type "$EXT_LOWER")"

# Project environment and workspace resolution
PROJECT_ROOT="$(find_project_root "$SCRIPT_DIR")" || {
  echo "错误：无法定位项目根目录。请在目标仓库内运行。" >&2
  exit 2
}
CONFIG_FILE="$PROJECT_ROOT/.lexiloom/config.json"
ENV_FILE="$PROJECT_ROOT/.lexiloom.env"

command -v python3 >/dev/null 2>&1 || { echo "错误：需要 Python 3 解析配置与响应。" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "错误：需要 curl。" >&2; exit 2; }

CONFIG_VALUES="$(load_lexiloom_config "$CONFIG_FILE")" || exit $?
IFS=$'\t' read -r SERVER_URL CONFIG_WORKSPACE_ID WORKSPACE_NAME <<< "$CONFIG_VALUES"

WORKSPACE_ID="${OPT_WORKSPACE_ID:-$CONFIG_WORKSPACE_ID}"
[[ "$WORKSPACE_ID" =~ ^[1-9][0-9]*$ ]] || {
  echo "错误：workspaceId 必须是正整数（当前: $WORKSPACE_ID）。" >&2
  exit 2
}

API_KEY="$(load_api_key "$ENV_FILE")"
[[ -n "$API_KEY" ]] || {
  echo "错误：未读取到 API Key。请设置 LEXILOOM_API_KEY 环境变量或运行 scripts/setup.sh 配置 .lexiloom.env。" >&2
  exit 2
}

DEFAULT_TITLE="${FILENAME%.*}"
FINAL_TITLE="${OPT_TITLE:-$DEFAULT_TITLE}"

# Build form arguments with robust escaping for filenames containing spaces/special characters
FORM_ARGS=(
  -F "file=@\"${FILE_ABS_PATH}\";type=${MIME_TYPE};filename=\"${FILENAME}\""
  -F "workspaceId=${WORKSPACE_ID}"
)

if [[ -n "$FINAL_TITLE" ]]; then
  FORM_ARGS+=(-F "title=${FINAL_TITLE}")
fi
if [[ -n "$OPT_CATEGORY_ID" ]]; then
  FORM_ARGS+=(-F "categoryId=${OPT_CATEGORY_ID}")
fi
if [[ -n "$OPT_CATEGORY_NAME" ]]; then
  FORM_ARGS+=(-F "categoryName=${OPT_CATEGORY_NAME}")
fi

TMP_BODY="$(mktemp)"
trap 'rm -f "$TMP_BODY"' EXIT

echo "🚀 正在向 LexiLoom 发起文档导入..."
echo "  - 目标空间: ${WORKSPACE_NAME:-工作空间} (ID: ${WORKSPACE_ID})"
echo "  - 文档标题: ${FINAL_TITLE}"
echo "  - 文件路径: ${FILE_ABS_PATH} (${FILE_SIZE} 字节, ${MIME_TYPE})"
[[ -z "$OPT_CATEGORY_NAME" ]] || echo "  - 目标分类: ${OPT_CATEGORY_NAME}"

set +e
# Dual-binding: provide workspaceId in query params and form-data for universal server adapter compatibility
HTTP_CODE="$(lexiloom_curl_upload "$TMP_BODY" "$API_KEY" 10 "$OPT_TIMEOUT" \
  "$SERVER_URL/api/v1/openapi/documents/import?workspaceId=${WORKSPACE_ID}" \
  "${FORM_ARGS[@]}")"
CURL_STATUS=$?
set -e

if (( CURL_STATUS != 0 )); then
  echo "文档导入请求失败：网络连接错误或上传超时（curl exit=$CURL_STATUS）。请检查服务地址与网络连接。" >&2
  exit 1
fi

case "$HTTP_CODE" in
  200|201)
    echo "✓ 文档导入成功（HTTP $HTTP_CODE）！"
    python3 - "$TMP_BODY" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    print('服务端返回非标准 JSON 响应。')
    sys.exit(0)

doc_id = '未知'
title = '已提交'
status = 'PROCESSING'
chunks = None
category = None
msg = None

if isinstance(data, dict):
    msg = data.get('message') or data.get('msg')
    # Check if data payload is scalar ID (e.g. {code: 200, data: 12345})
    raw_data = data.get('data')
    if isinstance(raw_data, (int, str)) and 'id' not in data:
        doc_id = str(raw_data)
        title = data.get('title') or title
        status = data.get('status') or status
    elif isinstance(raw_data, dict):
        payload = raw_data
        doc_id = payload.get('id') or payload.get('documentId') or doc_id
        title = payload.get('title') or payload.get('name') or title
        status = payload.get('status') or status
        chunks = payload.get('totalChunks') or payload.get('chunkCount') or payload.get('chunksCount') or payload.get('sliceCount')
        category = payload.get('categoryName') or payload.get('category')
        msg = payload.get('message') or payload.get('msg') or msg
    else:
        doc_id = data.get('id') or data.get('documentId') or doc_id
        title = data.get('title') or data.get('name') or title
        status = data.get('status') or status
        chunks = data.get('totalChunks') or data.get('chunkCount') or data.get('chunksCount') or data.get('sliceCount')
        category = data.get('categoryName') or data.get('category')

print(f"  - 文档 ID: {doc_id}")
print(f"  - 文档标题: {title}")
print(f"  - 当前状态: {status}")
if category:
    print(f"  - 归属分类: {category}")
if chunks is not None:
    print(f"  - 切片数量: {chunks}")
if msg and msg.lower() not in ('success', 'ok'):
    print(f"  - 服务端信息: {msg}")
PY
    ;;
  400)
    DETAIL="$(extract_problem_detail "$TMP_BODY")"
    echo "文档导入参数错误（HTTP 400）${DETAIL:+：$DETAIL}。" >&2
    echo "请确认工作空间 ID 正确，且文件格式有效。" >&2
    exit 1
    ;;
  401|403)
    DETAIL="$(extract_problem_detail "$TMP_BODY")"
    if [[ -n "$DETAIL" ]]; then
      echo "文档导入鉴权失败（HTTP $HTTP_CODE）：$DETAIL" >&2
    else
      echo "文档导入鉴权失败（HTTP $HTTP_CODE）。请检查 API Key 是否具有文档导入与写入权限（doc:import / doc:write），以及对应工作空间的授权。" >&2
    fi
    exit 1
    ;;
  404)
    echo "文档导入接口未找到（HTTP 404）。请确认后端已部署 POST /api/v1/openapi/documents/import。" >&2
    exit 1
    ;;
  413)
    echo "上传文件过大（HTTP 413 Payload Too Large）。请检查文件大小或调大后端上传限制。" >&2
    exit 1
    ;;
  429)
    echo "请求过于频繁（HTTP 429 Too Many Requests），请稍后重试。" >&2
    exit 1
    ;;
  5*)
    DETAIL="$(extract_problem_detail "$TMP_BODY")"
    echo "知识库服务暂时异常（HTTP $HTTP_CODE）${DETAIL:+：$DETAIL}。请检查后端服务日志。" >&2
    exit 1
    ;;
  *)
    echo "文档导入失败（HTTP $HTTP_CODE）。响应正文已隐藏，避免意外泄露敏感信息。" >&2
    exit 1
    ;;
esac
