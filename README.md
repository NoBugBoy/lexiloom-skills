# LexiLoom Agent Skills 扩展库

通过 `npx` 将 LexiLoom 知识库系统的 Agent Skills 安装到市面主流编码 Agent（Codex、Claude Code、Cursor、Windsurf、GitHub Copilot、Gemini CLI、Antigravity、Cline、Roo Code、OpenCode、Trae、Goose、Pi 等）中。安装器负责复制/更新/卸载 Skill 文件，并引导完成目标代码仓库与 LexiLoom 工作空间的绑定配置。

## 快速安装

```bash
npx lexiloom-hybrid-search
# 或使用别名：
npx lexiloom-skills
```

按交互提示选择安装范围（当前项目或当前用户全局）和目标 Agent；安装完成后会自动启动工作空间绑定向导。也支持非交互式命令与多技能扩展管理：

```bash
# 查看所有可用 Skills 与支持的 Agent 列表
npx lexiloom-hybrid-search --list

# 当前项目安装到 Codex、Claude Code 和 Cursor
npx lexiloom-hybrid-search --scope project --agent codex,claude,cursor --yes

# 当前用户全局安装到指定 Agent（仅安装技能，跳过当前目录绑定向导）
npx lexiloom-hybrid-search --scope global --agent claude --only-install --yes

# 安装到所有支持的 Agent 的全局目录
npx lexiloom-hybrid-search -g --only-install

# 只安装指定技能（扩展库包含多个技能时可按名称筛选，默认 all）
npx lexiloom-hybrid-search --scope project --agent codex --skill lexiloom-hybrid-search --only-install --yes

# 已安装后，单独在当前项目启动工作空间绑定向导
npx lexiloom-hybrid-search --only-setup

# 卸载指定目标
npx lexiloom-hybrid-search --scope project --agent codex --uninstall --yes
```

此外，本仓库目录结构遵循标准 Agent Skills 规范（`skills/<skill-name>/SKILL.md`），同样兼容社区通用技能安装器（如 `npx skills add <owner>/<repo>`）。

## 支持的编码 Agent 与安装目录

支持传入 `--agent <name1,name2>` 或 `--agent all`：

| Agent 参数 | Agent 名称 | 当前项目级目录 | 当前用户全局目录 |
|---|---|---|---|
| `codex` | OpenAI Codex | `.agents/skills/<skill>` | `~/.agents/skills/<skill>` |
| `claude` | Claude Code | `.claude/skills/<skill>` | `~/.claude/skills/<skill>` |
| `cursor` | Cursor | `.cursor/skills/<skill>` | `~/.cursor/skills/<skill>` |
| `windsurf` | Windsurf | `.windsurf/skills/<skill>` | `~/.codeium/windsurf/skills/<skill>` |
| `copilot` | GitHub Copilot | `.github/skills/<skill>` | `~/.copilot/skills/<skill>` |
| `gemini` | Gemini CLI | `.gemini/skills/<skill>` | `~/.gemini/skills/<skill>` |
| `antigravity` | Antigravity | `.agents/skills/<skill>` | `~/.gemini/config/skills/<skill>` |
| `cline` | Cline | `.cline/skills/<skill>` | `~/.cline/skills/<skill>` |
| `roo` | Roo Code | `.roo/skills/<skill>` | `~/.roo/skills/<skill>` |
| `opencode` | OpenCode | `.opencode/skills/<skill>` | `~/.config/opencode/skills/<skill>` |
| `trae` | Trae | `.trae/skills/<skill>` | `~/.trae/skills/<skill>` |
| `goose` | Goose | `.goose/skills/<skill>` | `~/.config/goose/skills/<skill>` |
| `pi` | Pi | `.pi/skills/<skill>` | `~/.pi/agent/skills/<skill>` |

部分 Agent 的项目级目录遵循通用 `.agents/skills` 标准而重合（如 Codex 与 Antigravity），安装器会自动对重复路径去重。

## 配置 LexiLoom 工作空间绑定

默认安装流程会在安装完成后自动运行 `setup.sh`（若在非代码仓库目录执行全局安装，或处于无 TTY 的非交互环境，会自动跳过并提示）。也可以在**目标代码仓库根目录（或子目录）**单独运行：

```bash
# 交互式向导
npx lexiloom-hybrid-search --only-setup

# 或直接调用脚本（支持交互式或传参/环境变量非交互式配置）
bash .agents/skills/lexiloom-hybrid-search/scripts/setup.sh \
  --url http://localhost:8080 \
  --workspace-id 1
```

`setup.sh` 会请求 `/api/v1/openapi/workspaces`，校验所选工作空间 ID 是否存在于服务端实际返回列表中（绝不在失败时猜测或静默绑定默认 ID）。配置完成后生成：

- `.lexiloom/config.json`：服务地址、绑定的工作空间信息及代码检索排除规则，确认无敏感信息后可提交版本库。
- `.lexiloom.env`：本地 API Key（权限自动设为 `600`，并自动确保写入 `.gitignore`）。

运行时 `LEXILOOM_API_KEY` 环境变量优先级高于 `.lexiloom.env`。

## 运行要求

- **Node.js 18+**：运行 `npx` 安装器。
- **Bash、Python 3、curl**：运行配置向导与知识库检索脚本。
- **ripgrep (`rg`)**（推荐，可选）：加速本地代码搜索；未安装时自动降级为 `grep`。

## 安全与边界说明

- **进程参数防泄露**：检索脚本通过 `curl --config -` 从标准输入传递 `Authorization` 请求头，避免 API Key 暴露在系统进程列表（`ps aux`）中。
- **安全覆盖保护**：更新或卸载时仅操作包含 `SKILL.md` 的有效技能目录，且拒绝跟随或删除软链接目录，防止误删用户数据。
- **多模块/Monorepo 根目录定位**：脚本按 `.lexiloom` → `.git` → 构建描述文件（`pom.xml`/`package.json` 等）的优先级多轮向上查找，确保在子模块目录执行时仍能准确定位仓库根配置。

## 常见问题

- **401 / 403**：`401` 为凭证缺失或无效；`403` 为 API Key 缺少对应 scope（`kb:read`、`kb:search`、`doc:read`）、工作空间白名单限制或文档权限不足。脚本会优先展示后端 ProblemDetail 返回的具体原因。
- **404**：请确认后端已部署 `/api/v1/openapi/workspaces`、`/api/v1/openapi/knowledge/search` 及 `/api/v1/openapi/documents/{id}`。
- **Agent 未识别 Skill**：确认目标目录符合对应 Agent 当前版本的 Skills 目录约定，并在安装后刷新或重启 Agent 会话。
