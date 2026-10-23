# LexiLoom Hybrid Search Skill (npm MVP)

通过 `npx` 将 LexiLoom 混合检索 Skill 安装到支持 Agent Skills 的编码 Agent 中。安装器只负责复制/更新/卸载 Skill 文件；服务端鉴权和工作空间绑定在目标代码仓库中单独配置。

## 快速安装

```bash
npx lexiloom-hybrid-search
```

按提示选择安装范围（当前项目或当前用户全局）和 Agent。也可以使用非交互命令：

```bash
# 当前项目安装到 Codex 和 Claude Code
npx lexiloom-hybrid-search --scope project --agent codex,claude --yes

# 当前用户全局安装到 Codex
npx lexiloom-hybrid-search --scope global --agent codex --yes

# 兼容旧命令：安装到所有支持的 Agent 的全局目录（包括 Pi）
npx lexiloom-hybrid-search -g

# 卸载指定目标
npx lexiloom-hybrid-search --scope project --agent codex --uninstall --yes
```

支持的 Agent 参数：`codex`、`claude`、`gemini`、`antigravity`、`pi`。Pi 目标目录为项目级 `.pi/skills/` 和用户全局 `~/.pi/agent/skills/`。

## 安装目标目录

| Agent | 当前项目 | 当前用户全局 |
|---|---|---|
| Codex | `.agents/skills/lexiloom-hybrid-search` | `~/.agents/skills/lexiloom-hybrid-search` |
| Claude Code | `.claude/skills/lexiloom-hybrid-search` | `~/.claude/skills/lexiloom-hybrid-search` |
| Gemini CLI | `.gemini/skills/lexiloom-hybrid-search` | `~/.gemini/skills/lexiloom-hybrid-search` |
| Antigravity | `.agents/skills/lexiloom-hybrid-search` | `~/.gemini/antigravity/skills/lexiloom-hybrid-search` |
| Pi | `.pi/skills/lexiloom-hybrid-search` | `~/.pi/agent/skills/lexiloom-hybrid-search` |

部分 Agent 的技能目录会重合（例如 Codex 和 Antigravity 的项目级目录）。安装器会对重复目标去重。

## 配置 LexiLoom

安装完成后，在**目标代码仓库根目录**执行安装器提示的命令，例如：

```bash
bash .agents/skills/lexiloom-hybrid-search/scripts/setup.sh
```

`setup.sh` 会请求 `/api/v1/openapi/workspaces`，要求从实际返回的工作空间中选择一个，不会在失败时猜测或默认绑定工作空间 ID。配置写入：

- `.lexiloom/config.json`：服务地址和工作空间信息，可在确认无秘密后提交。
- `.lexiloom.env`：当前 MVP 的本地 API Key，必须加入 `.gitignore`，权限设置为仅当前用户可读写。

`LEXILOOM_API_KEY` 环境变量优先于 `.lexiloom.env`。API Key 管理机制沿用当前 MVP 设计，后续再独立改造。

## 运行要求

- Node.js 18+：运行 npx 安装器。
- Bash、Python 3、curl：运行检索脚本。
- `rg`（可选）：加速本地代码搜索；未安装时可使用 `grep` 降级。

## MVP 边界

- 远程知识检索通过现有 REST API 完成；路径中的 `/mcp/` 不代表接口本身就是 MCP 协议。
- 安装器不自动创建 MCP Server 配置，也不管理 API Key。
- 更新时只替换可识别的 Skill 安装目录；如果目标目录不是带有 `SKILL.md` 的 Skill 目录，安装器会停止而不覆盖。
- 项目级安装会写入目标项目的 Agent Skill 目录。全局安装只影响当前操作系统用户。

## 常见问题

- **401**：凭证缺失、无效或未登录；**403**：检查 API Key 的 scope、工作空间白名单及文档权限。后端返回的具体原因会优先展示。
- **404**：确认后端已实现 `/api/v1/openapi/workspaces` 和 `/api/v1/openapi/knowledge/search`。
- **无法定位项目根目录**：请从目标仓库根目录运行 `setup.sh` 或检索脚本。
- **Agent 未识别 Skill**：确认目标目录是否符合该 Agent 当前版本的 Skills 目录约定，并重启/刷新 Agent。
