# LexiLoom Skills 🧠

LexiLoom 官方 AI Agent 技能库（Agent Skills），用于赋能现代 AI 编程助手（如 Antigravity、Claude Code、Cursor、Codex 等），实现本地代码库与 LexiLoom 知识库的深度协同。

---

## 📦 技能列表 (Available Skills)

| Skill 名称 | 描述 | 核心脚本 / 资源 |
| :--- | :--- | :--- |
| **[`lexiloom-hybrid-search`](./lexiloom-hybrid-search/SKILL.md)** | 本地代码与 LexiLoom 知识库多路混合检索与交叉验证技能，精准回答代码实现与业务设计文档差异。 | `setup.sh`, `search_code.sh`, `search_knowledge.sh` |

---

## ⚡️ 极速上手：一键安装并初始化（推荐）

为了省去手动执行后续绑定脚本的步骤，我们提供了一体化的自动化 CLI。在你的代码工程根目录下直接运行：

```bash
npx github:NoBugBoy/lexiloom-skills
```
*(已发布 npm 的环境亦支持直接执行 `npx lexiloom-skills`)*

> [!TIP]
> **该命令会自动执行以下完整闭环：**
> 1. 自动调用 Skills CLI 将技能安装并挂载至项目下的主流 AI Agent；
> 2. 紧接着自动拉起终端交互向导，引导你输入 LexiLoom 服务端地址与 API Key 并选择工作空间；
> 3. 自动生成 `.lexiloom/config.json` 与 `.lexiloom.env`，并自动向 `.gitignore` 追加入库保护规则。

---

## 🛠️ 分步使用指南

如果你偏好传统的两步式管理流程，也可以通过标准命令分步执行：

### 步骤一：通过 Skills CLI 仅安装技能

```bash
# 交互式选择安装目标 Agent (Cursor, Claude Code, Antigravity 等)
npx skills add NoBugBoy/lexiloom-skills

# 或静默安装全部技能至所有受支持的 Agent
npx skills add NoBugBoy/lexiloom-skills --all

# 用户全局安装 (所有工程共用)
npx skills add NoBugBoy/lexiloom-skills -g
```

> [!NOTE]
> 为什么 `npx skills add` 不直接静默执行脚本？  
> 遵循 open standard [skills.sh](https://skills.sh) 规范的安全模型，`skills add` 出于防范恶意代码注入考量，仅复制/软链接技能声明，默认不执行任意安装期 shell 脚本。

### 步骤二：手动运行初始化向导

技能文件安装后，在目标代码工程根目录运行：

```bash
bash .agents/skills/lexiloom-hybrid-search/scripts/setup.sh
```

---

## 🤖 兼容支持的主流 Agent

- [x] **Google Antigravity** (`.agents/skills/` / `~/.gemini/config/skills/`)
- [x] **Claude Code** (`.claude/skills/` / `~/.claude/skills/`)
- [x] **Cursor**
- [x] **OpenAI Codex** (`.codex/skills/` / `~/.codex/skills/`)
- [x] 以及所有遵循 [skills.sh](https://skills.sh) 规范的 AI Coding Agent
