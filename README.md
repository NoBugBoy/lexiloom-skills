# LexiLoom Agent Skills 扩展库

通过 `npx` 将 LexiLoom 知识库系统的 Agent Skills 安装到市面主流编码 Agent（Codex、Claude Code、Cursor、Windsurf、GitHub Copilot、Gemini CLI、Antigravity、Cline、Roo Code、OpenCode、Trae、Goose、Pi、Qoder、CodeBuddy、Qwen Code、Kimi Code CLI 等）中。安装器负责复制/更新/卸载 Skill 文件，并引导完成目标代码仓库与 LexiLoom 工作空间的绑定配置。

## 推荐安装方式：项目级定向安装（推荐）

为了确保技能与当前代码仓库的知识库工作空间精准绑定，且便于团队通过版本控制协同共享，**强烈推荐进入目标工程根目录，采用项目级（`--scope project`）命令进行明确安装**。

该方式能**百分之百保证**技能安装在当前工程目录内，绝不会误装至本机用户全局：

```bash
# 1. 首先进入你的目标代码仓库根目录
cd /path/to/your/project

# 2. 执行项目级安装（以 Google Antigravity 为例）
npx lexiloom-skills --scope project --agent antigravity --yes

# 亦可同时安装给多个常用 Agent（逗号分隔）
npx lexiloom-skills --scope project --agent antigravity,claude,cursor --yes

# 或者一键为当前项目安装给所有支持的 Agent
npx lexiloom-skills --scope project --agent all --yes
```

> **提示**：若未全局发布到 npm，也可以直接通过 GitHub 源安装：
> ```bash
> npx github:NoBugBoy/lexiloom-skills --scope project --agent antigravity --yes
> ```

---

## 常用命令与 Agent 选项清单

### 1. `--agent` 可选参数一览

在执行 `--agent <name>` 时，可传入以下任意选项（支持多选，用英文逗号分隔；或传 `all` 选择全部）：

| Agent 选项 | 对应工具 / 平台 | 项目级安装路径（`--scope project`，推荐） | 全局安装路径（`--scope global`） |
|---|---|---|---|
| **`antigravity`** | Google Antigravity | `.agents/skills/<skill>` | `~/.gemini/config/skills/<skill>` |
| **`claude`** | Claude Code | `.claude/skills/<skill>` | `~/.claude/skills/<skill>` |
| **`cursor`** | Cursor | `.cursor/skills/<skill>` | `~/.cursor/skills/<skill>` |
| **`codex`** | OpenAI Codex | `.agents/skills/<skill>` | `~/.agents/skills/<skill>` |
| **`windsurf`** | Windsurf | `.windsurf/skills/<skill>` | `~/.codeium/windsurf/skills/<skill>` |
| **`copilot`** | GitHub Copilot | `.github/skills/<skill>` | `~/.copilot/skills/<skill>` |
| **`gemini`** | Gemini CLI | `.gemini/skills/<skill>` | `~/.gemini/skills/<skill>` |
| **`cline`** | Cline | `.cline/skills/<skill>` | `~/.cline/skills/<skill>` |
| **`roo`** | Roo Code | `.roo/skills/<skill>` | `~/.roo/skills/<skill>` |
| **`opencode`** | OpenCode | `.opencode/skills/<skill>` | `~/.config/opencode/skills/<skill>` |
| **`trae`** | Trae | `.trae/skills/<skill>` | `~/.trae/skills/<skill>` |
| **`goose`** | Goose | `.goose/skills/<skill>` | `~/.config/goose/skills/<skill>` |
| **`pi`** | Pi | `.pi/skills/<skill>` | `~/.pi/agent/skills/<skill>` |
| **`qoder`** | Qoder | `.qoder/skills/<skill>` | `~/.qoder/skills/<skill>` |
| **`qoder-cn`** | Qoder CN | `.qoder/skills/<skill>` | `~/.qoder-cn/skills/<skill>` |
| **`codebuddy`** | CodeBuddy | `.codebuddy/skills/<skill>` | `~/.codebuddy/skills/<skill>` |
| **`qwen-code`** | Qwen Code | `.qwen/skills/<skill>` | `~/.qwen/skills/<skill>` |
| **`kimi-code-cli`** | Kimi Code CLI | `.agents/skills/<skill>` | `~/.agents/skills/<skill>` |
| **`all`** | 全部支持的 Agent | 自动安装到上述所有 Agent 的对应目录（自动去重） | 自动安装到上述所有全局目录 |

---

### 2. 其他常用 CLI 命令

```bash
# 查看所有可用 Skills 与支持的 Agent 列表
npx lexiloom-skills --list

# 仅安装技能，跳过自动启动工作空间绑定向导（--only-install）
npx lexiloom-skills --scope project --agent antigravity --only-install --yes

# 仅安装扩展库中的指定 Skill（默认安装全部 skills）
npx lexiloom-skills --scope project --agent antigravity --skill lexiloom-hybrid-search --yes

# 交互式向导安装（按命令行提示逐步选择范围与 Agent）
npx lexiloom-skills

# 单独在当前项目启动/重新配置工作空间绑定向导
npx lexiloom-skills --only-setup

# 卸载指定 Agent 的技能
npx lexiloom-skills --scope project --agent antigravity --uninstall --yes
```

此外，本仓库目录结构遵循标准 Agent Skills 规范（`skills/<skill-name>/SKILL.md`），同样兼容社区通用技能安装器（如 `npx skills add <owner>/<repo>`）。

## 包含的核心 Agent Skills

本库提供面向 LexiLoom 企业级知识库的一体化 Agent Skills 集合：

| Skill 标识 | 技能名称 | 核心能力与适用场景 |
|---|---|---|
| `lexiloom-hybrid-search` | 混合检索与双侧对齐 | 结合本地源码与 LexiLoom 知识库（PRD、架构设计、业务规范）进行多源检索与一致性交叉核对。 |
| `lexiloom-knowledge-harvest` | 知识采集与审查入库 | 对零散碎片知识（群聊记录、需求碎语、测试用例、网页 URL 等）进行智能研判、噪声清洗、敏感脱敏、提炼重塑为结构化文档（纯文本优先 `.md`，涉及图片优先使用 `.pdf` 或 `.docx`，合并文件名推荐中文），并通过 `POST /api/v1/openapi/documents/import` 安全导入知识库。 |
| `lexiloom-workspace-manager` | 空间与凭证动态管理 | 提供**切换工作空间**与**切换 AccessKey**两大核心指令。支持实时查询当前 Key 所见的所有可用空间供用户交互选择，切换 AccessKey 时自动探测凭证有效性并固定强制触发选择空间流程，无须重启 Agent 即刻在当前会话生效。 |

## 配置 LexiLoom 工作空间绑定

默认安装流程会在安装完成后自动运行 `setup.js`（若在非代码仓库目录执行全局安装，或处于无 TTY 的非交互环境，会自动跳过并提示）。也可以在**目标代码仓库根目录（或子目录）**单独运行：

```bash
# 交互式向导
npx lexiloom-hybrid-search --only-setup

# 或直接调用脚本（支持交互式或传参/环境变量非交互式配置，零 Python 依赖）
node .agents/skills/lexiloom-hybrid-search/scripts/setup.js \
  --url http://localhost:8080 \
  --workspace-id 1
```

`setup.js` 会请求 `/api/v1/openapi/workspaces`，校验所选工作空间 ID 是否存在于服务端实际返回列表中（绝不在失败时猜测或静默绑定默认 ID）。配置完成后生成：

- `.lexiloom/config.json`：服务地址、绑定的工作空间信息及代码检索排除规则，确认无敏感信息后可提交版本库。
- `.lexiloom.env`：本地 API Key（权限自动设为 `600`，并自动确保写入 `.gitignore`）。

运行时 `LEXILOOM_API_KEY` 环境变量优先级高于 `.lexiloom.env`。

### 动态切换工作空间与 AccessKey

在日常开发与对话中，可通过新增的 `lexiloom-workspace-manager` 技能直接用自然语言（例如“帮我换个空间”、“切换 accesskey”）触发，或在项目根目录运行管理脚本：

```bash
# 1. 查询当前凭证可见的所有工作空间
node skills/lexiloom-workspace-manager/scripts/manage_workspace.js list-workspaces

# 2. 切换至指定的工作空间（立刻在当前会话生效）
node skills/lexiloom-workspace-manager/scripts/manage_workspace.js set-workspace --workspace-id 2

# 3. 切换 AccessKey（自动探测验证，并立刻强制返回该 Key 可见工作空间供选择）
node skills/lexiloom-workspace-manager/scripts/manage_workspace.js set-api-key --api-key <新Key>
```

---

## 🔌 作为 MCP Server 运行 (Model Context Protocol)

本包内置了**零第三方依赖**的原生 Stdio MCP Server（`npx lexiloom-skills mcp` 或 `npx lexiloom-mcp`），支持同时挂载给 Claude Desktop、Cursor、Windsurf、Cline、Claude Code、Antigravity 等支持 MCP 协议的客户端，与 Agent Skills 协同工作（**Skills 负责分析工作流与对齐规范，MCP 负责结构化工具调用与凭证隔离**）。

### 1. 暴露的 MCP 工具清单

| 工具名称 | 功能说明 | 对应 OpenAPI 权限 |
|---|---|---|
| `search_knowledge` | 知识库多路混合检索与 Cross-Encoder 精排（支持传入 `query`, `topK`, `workspaceId`） | `kb:search` |
| `get_document` | 提取单篇文档完整元数据与 Markdown 正文（支持 `documentId`, `maxChars`） | `doc:read` |
| `import_document` | 将本地提炼好的文档（支持 14 种格式）安全导入指定工作空间 | `doc:write` |
| `list_workspaces` | 查询当前 API Key 可见的所有工作空间列表及当前绑定状态 | `kb:read` |
| `switch_workspace` | 切换并持久化绑定当前工程的默认工作空间（无需重启 MCP 即刻生效） | `kb:read` |

### 2. MCP 鉴权与三级配置解析机制

MCP Server 在本地进程内完成 OpenAPI 鉴权（自动携带 `Authorization: Bearer <Key>` 与 `X-API-Key: <Key>` 请求头，**大模型上下文完全接触不到明文密钥**），按以下三级优先级动态解析凭证与空间配置：

1. **环境变量注入（最高优先级，适合 Claude Desktop 等全局客户端）**：
   - `LEXILOOM_API_KEY`：访问密钥（如 `lx_live_xxx`）
   - `LEXILOOM_URL`（或 `LEXILOOM_SERVER_URL`）：服务端地址（默认 `http://localhost:8080`）
   - `LEXILOOM_WORKSPACE_ID`（可选）：默认工作空间 ID
2. **项目级零配置复用（推荐，与 Skills 完全共享）**：
   - 自动向上查找当前工程根目录下的 `.lexiloom.env` 与 `.lexiloom/config.json`。
   - 若项目已执行过 `npx lexiloom-skills` 初始化绑定，挂载 MCP 时**无需重复配置任何环境变量**；且调用 `switch_workspace` 切换空间后立即生效。
3. **用户全局兜底（`~/.lexiloom/`）**：
   - 当在非代码仓库目录启动且未传环境变量时，自动回退读取 `~/.lexiloom/.lexiloom.env`（或 `~/.lexiloom.env`）与 `~/.lexiloom/config.json`。

### 3. 客户端 MCP 配置示例

**方式 A：在已初始化绑定的代码仓库中使用（零明文密钥配置）**

```json
{
  "mcpServers": {
    "lexiloom": {
      "command": "npx",
      "args": ["-y", "lexiloom-skills", "mcp"]
    }
  }
}
```

**方式 B：在 Claude Desktop / 全局客户端中通过 `env` 显式注入凭证**

```json
{
  "mcpServers": {
    "lexiloom": {
      "command": "npx",
      "args": ["-y", "lexiloom-skills", "mcp"],
      "env": {
        "LEXILOOM_URL": "http://localhost:8080",
        "LEXILOOM_API_KEY": "lx_live_your_api_key_here",
        "LEXILOOM_WORKSPACE_ID": "1"
      }
    }
  }
}
```

## 运行要求

- **Node.js 18+**：支持原生 `fetch`、`FormData` 与 `Blob`。所有技能脚本均采用 **Node.js 原生零依赖**单文件实现，不需要安装任何第三方 npm 包，**不需要 Python 3，不需要 curl**，完全原生支持 macOS、Linux 及 Windows（CMD / PowerShell）。
- **ripgrep (`rg`)**（推荐，可选）：加速本地代码搜索；未安装时自动降级为系统 `grep`。

## 安全与边界说明

- **全平台跨环境一致性**：核心脚本摆脱系统 Shell 与 Python 版本不一致的困扰，统一由 Node.js 运行时执行。
- **进程参数防泄露**：请求通过 HTTP 标头在进程内直接传递 `Authorization` 与 `X-API-Key`，不会暴露在系统进程列表（`ps aux`）中。
- **安全覆盖保护**：更新或卸载时仅操作包含 `SKILL.md` 的有效技能目录，且拒绝跟随或删除软链接目录，防止误删用户数据。
- **多模块/Monorepo 根目录定位**：脚本按 `.lexiloom` → `.git` → 构建描述文件（`pom.xml`/`package.json` 等）的优先级多轮向上查找，确保在子模块目录执行时仍能准确定位仓库根配置。

## 常见问题

- **401 / 403**：`401` 为凭证缺失或无效；`403` 为 API Key 缺少对应 scope（`kb:read`、`kb:search`、`doc:read`）、工作空间白名单限制或文档权限不足。脚本会优先展示后端 ProblemDetail 返回的具体原因。
- **404**：请确认后端已部署 `/api/v1/openapi/workspaces`、`/api/v1/openapi/knowledge/search`、`/api/v1/openapi/documents/{id}` 及 `/api/v1/openapi/documents/import`。
- **Agent 未识别 Skill**：确认目标目录符合对应 Agent 当前版本的 Skills 目录约定，并在安装后刷新或重启 Agent 会话。
