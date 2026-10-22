#!/usr/bin/env bash
# ==============================================================================
# LexiLoom 项目级知识库工作空间绑定引导向导 (Setup Script)
# 作用：引导用户一键将当前代码仓库与指定的 LexiLoom 工作空间建立关联并持久化
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

echo "================================================================="
echo "  🚀 LexiLoom 代码仓库 & 知识库混合检索 - 一键初始化向导"
echo "  （此配置在当前仓库仅需执行一次，团队成员可共享工作空间绑定）"
echo "================================================================="
echo ""

CONFIG_DIR="${PROJECT_ROOT}/.lexiloom"
CONFIG_FILE="${CONFIG_DIR}/config.json"
ENV_FILE="${PROJECT_ROOT}/.lexiloom.env"

# 1. 询问/确认 LexiLoom 后端服务地址
DEFAULT_URL="http://localhost:8080"
if [[ -f "${CONFIG_FILE}" ]]; then
  EXISTING_URL=$(grep -o '"serverUrl": *"[^"]*"' "${CONFIG_FILE}" | cut -d'"' -f4 || true)
  if [[ -n "${EXISTING_URL}" ]]; then
    DEFAULT_URL="${EXISTING_URL}"
  fi
fi

read -r -p "👉 请输入 LexiLoom 服务端地址 [默认: ${DEFAULT_URL}]: " INPUT_URL
SERVER_URL="${INPUT_URL:-${DEFAULT_URL}}"
SERVER_URL="${SERVER_URL%/}" # 移除末尾斜杠

# 2. 检查或输入 API Key
API_KEY="${LEXILOOM_API_KEY:-}"
if [[ -f "${ENV_FILE}" ]]; then
  EXISTING_KEY=$(grep -E "^LEXILOOM_API_KEY=" "${ENV_FILE}" | cut -d'=' -f2- || true)
  if [[ -n "${EXISTING_KEY}" ]]; then
    API_KEY="${EXISTING_KEY}"
  fi
fi

if [[ -z "${API_KEY}" ]]; then
  echo ""
  echo "🔑 请配置访问密钥 (API Key)："
  echo "   可前往 LexiLoom Web 端「管理员中心 / 全局设置 → API 密钥」获取 (如 lx_live_xxx)"
  read -r -s -p "👉 请粘贴你的 API Key: " INPUT_KEY
  echo ""
  API_KEY="${INPUT_KEY:-}"
fi

if [[ -z "${API_KEY}" ]]; then
  echo "❌ 错误: API Key 不能为空！" >&2
  exit 1
fi

# 3. 探活并获取可用工作空间列表
echo ""
echo "⏳ 正在连接服务端拉取可用工作空间..."
HTTP_STATUS=0
WORKSPACES_RESP=""

# 尝试调用轻量工作空间查询端点
WORKSPACES_RESP=$(curl -s -w "\n%{http_code}" -X GET "${SERVER_URL}/api/ai/mcp/workspaces" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Accept: application/json" || true)

HTTP_CODE=$(echo "${WORKSPACES_RESP}" | tail -n1)
BODY_JSON=$(echo "${WORKSPACES_RESP}" | sed '$d')

SELECTED_WS_ID=""
SELECTED_WS_NAME="默认工作空间"

if [[ "${HTTP_CODE}" == "200" ]] && command -v jq >/dev/null 2>&1; then
  echo "✅ 成功获取工作空间列表："
  echo ""
  echo "${BODY_JSON}" | jq -r '.[] | "  [\(.id)] \(.name) (\(.description // "无描述"))"'
  echo ""
  read -r -p "👉 请输入要绑定到当前代码工程的工作空间 ID [例如 1]: " SELECTED_WS_ID
  SELECTED_WS_NAME=$(echo "${BODY_JSON}" | jq -r ".[] | select(.id == ${SELECTED_WS_ID}) | .name" 2>/dev/null || echo "工作空间-${SELECTED_WS_ID}")
else
  # 降级模式：若后端端点尚未就绪或未安装 jq，支持手动输入
  echo "ℹ️  提示: 未能自动列出工作空间 (HTTP ${HTTP_CODE})，进入手动指定模式。"
  read -r -p "👉 请直接输入你要绑定的工作空间 ID [例如 1]: " SELECTED_WS_ID
fi

if [[ -z "${SELECTED_WS_ID}" ]]; then
  SELECTED_WS_ID="1"
fi

# 4. 创建 .lexiloom 配置目录与文件
mkdir -p "${CONFIG_DIR}"

cat > "${CONFIG_FILE}" <<EOF
{
  "version": "1.0.0",
  "serverUrl": "${SERVER_URL}",
  "workspace": {
    "id": ${SELECTED_WS_ID},
    "name": "${SELECTED_WS_NAME}"
  },
  "search": {
    "useWorkspaceDefaults": true,
    "codeScope": [
      "src/main/java",
      "src/main/resources"
    ],
    "excludePatterns": [
      "**/target/**",
      "**/.git/**",
      "**/node_modules/**"
    ]
  }
}
EOF

# 写入本地密钥（禁止入库）
cat > "${ENV_FILE}" <<EOF
# LexiLoom Local API Credentials (DO NOT COMMIT TO GIT)
LEXILOOM_API_KEY=${API_KEY}
EOF

# 5. 防御性检查 .gitignore
GITIGNORE="${PROJECT_ROOT}/.gitignore"
if [[ -f "${GITIGNORE}" ]]; then
  if ! grep -q "^\.lexiloom\.env" "${GITIGNORE}"; then
    echo "" >> "${GITIGNORE}"
    echo "# LexiLoom 本地私密凭证" >> "${GITIGNORE}"
    echo ".lexiloom.env" >> "${GITIGNORE}"
    echo "✅ 已自动向 .gitignore 追加入库保护规则: .lexiloom.env"
  fi
fi

echo ""
echo "================================================================="
echo "🎉 初始化完成！"
echo "  📁 项目配置已生成: .lexiloom/config.json (可安全提交到 Git 团队共享)"
echo "  🔒 私有凭证已生成: .lexiloom.env (已自动添加到 .gitignore 保护)"
echo "  🎯 已绑定工作空间: ID=${SELECTED_WS_ID} (${SELECTED_WS_NAME})"
echo "================================================================="
