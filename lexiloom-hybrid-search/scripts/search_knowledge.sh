#!/usr/bin/env bash
# ==============================================================================
# LexiLoom 知识库检索辅助脚本 (search_knowledge.sh)
# 作用：调用 LexiLoom 后端语义检索 API，返回结构化文档切片、标题与相似度得分
# ==============================================================================

set -euo pipefail

QUERY="${1:-}"
if [[ -z "${QUERY}" ]]; then
  echo "❌ 用法: $0 <自然语言检索问题> [可选 topK, 默认 5]" >&2
  exit 1
fi

TOP_K="${2:-5}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

CONFIG_FILE="${PROJECT_ROOT}/.lexiloom/config.json"
ENV_FILE="${PROJECT_ROOT}/.lexiloom.env"

# 1. 检查配置
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "⚠️ 尚未找到项目配置文件 (.lexiloom/config.json)。"
  echo "👉 请先执行绑定脚本: bash ${SCRIPT_DIR}/setup.sh"
  exit 1
fi

SERVER_URL=$(grep -o '"serverUrl": *"[^"]*"' "${CONFIG_FILE}" | cut -d'"' -f4 || echo "http://localhost:8080")
WORKSPACE_ID=$(grep -o '"id": *[0-9]*' "${CONFIG_FILE}" | head -n1 | grep -o '[0-9]*' || echo "1")
WORKSPACE_NAME=$(grep -o '"name": *"[^"]*"' "${CONFIG_FILE}" | head -n1 | cut -d'"' -f4 || echo "工作空间-${WORKSPACE_ID}")

API_KEY="${LEXILOOM_API_KEY:-}"
if [[ -f "${ENV_FILE}" ]]; then
  EXISTING_KEY=$(grep -E "^LEXILOOM_API_KEY=" "${ENV_FILE}" | cut -d'=' -f2- || true)
  if [[ -n "${EXISTING_KEY}" ]]; then
    API_KEY="${EXISTING_KEY}"
  fi
fi

if [[ -z "${API_KEY}" ]]; then
  echo "❌ 错误: 未读取到 API Key。请在 .lexiloom.env 中配置或导出环境变量 LEXILOOM_API_KEY" >&2
  exit 1
fi

echo "📚 [Knowledge Search] 正在检索 LexiLoom 知识库 [空间: ${WORKSPACE_NAME}(ID:${WORKSPACE_ID})]: \"${QUERY}\" ..."

# 2. 发起轻量无头检索请求
# 优先请求 MCP 轻量无头端点，返回标准 JSON 切片列表
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
  "${SERVER_URL}/api/ai/mcp/search" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Accept: application/json" \
  -G \
  --data-urlencode "q=${QUERY}" \
  --data-urlencode "workspaceId=${WORKSPACE_ID}" \
  --data-urlencode "topK=${TOP_K}" || true)

HTTP_CODE=$(echo "${RESPONSE}" | tail -n1)
BODY=$(echo "${RESPONSE}" | sed '$d')

if [[ "${HTTP_CODE}" == "200" ]]; then
  if command -v jq >/dev/null 2>&1; then
    COUNT=$(echo "${BODY}" | jq -r '.results | length' 2>/dev/null || echo "0")
    echo "✅ 成功检索到 ${COUNT} 条相关知识库切片："
    echo ""
    echo "${BODY}" | jq -r '.results[] | "📄 文档: 《\(.documentTitle)》 [相关度得分: \(.score // "N/A")]\n   切片序号: #\(.chunkIndex // 0) | 文档ID: \(.documentId)\n   摘要摘录: \(.content | gsub("\n"; " "))\n----------------------------------------------------------------"'
  else
    echo "✅ 检索成功 (原始 JSON 输出)："
    echo "${BODY}"
  fi
elif [[ "${HTTP_CODE}" == "404" ]]; then
  echo "⚠️ 提示: 后端轻量检索端点 [/api/ai/mcp/search] 尚未就绪 (HTTP 404)。"
  echo "👉 建议先在后端实现该 MCP/Skill 专用无状态检索 API。"
else
  echo "❌ 知识库检索请求失败 (HTTP ${HTTP_CODE}):"
  echo "${BODY}"
  exit 1
fi
