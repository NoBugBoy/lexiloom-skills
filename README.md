# LexiLoom Skills 🧠

LexiLoom 官方 AI Agent 技能库（Agent Skills），用于赋能现代 AI 编程助手（如 Antigravity、Claude Code、Cursor、Codex 等），实现本地代码库与 LexiLoom 知识库的深度协同。

---

## 📦 技能列表 (Available Skills)

| Skill 名称 | 描述 | 核心脚本 / 资源 |
| :--- | :--- | :--- |
| **[`lexiloom-hybrid-search`](./lexiloom-hybrid-search/SKILL.md)** | 本地代码与 LexiLoom 知识库多路混合检索与交叉验证技能，精准回答代码实现与业务设计文档差异。 | `setup.sh`, `search_code.sh`, `search_knowledge.sh` |

---

## ⚡️ 安装指南 (Installation)

推荐使用现代 AI Agent 开放技能管理器 **Skills CLI** (`npx skills`) 进行一键安装：

### 1. 为当前工程安装 (Project-Level)

在你的代码工程根目录下执行：

```bash
# 交互式选择安装目标 Agent (Cursor, Claude Code, Antigravity 等)
npx skills add NoBugBoy/lexiloom-skills

# 或静默安装所有技能至所有受支持的 Agent
npx skills add NoBugBoy/lexiloom-skills --all
```

### 2. 全局安装 (Global-Level)

如果你希望在当前开发机的所有工程中均可激活该技能：

```bash
npx skills add NoBugBoy/lexiloom-skills -g
```

### 3. 指定单一技能安装

```bash
npx skills add NoBugBoy/lexiloom-skills --skill lexiloom-hybrid-search
```

---

## 🛠️ 初始化与绑定 (Configuration)

安装完成后，在目标代码工程根目录运行初始化向导，绑定 LexiLoom 后端地址与工作空间：

```bash
bash .agents/skills/lexiloom-hybrid-search/scripts/setup.sh
```

向导将自动生成：
- `.lexiloom/config.json`：工作空间关联配置（可安全提交至团队 Git 共享）
- `.lexiloom.env`：本地私密 API Key（已自动被 `.gitignore` 规则保护）

---

## 🤖 兼容支持的主流 Agent

- [x] **Google Antigravity** (`.agents/skills/` / `~/.gemini/config/skills/`)
- [x] **Claude Code** (`.claude/skills/` / `~/.claude/skills/`)
- [x] **Cursor**
- [x] **OpenAI Codex** (`.codex/skills/` / `~/.codex/skills/`)
- [x] 以及所有遵循 [skills.sh](https://skills.sh) 规范的 AI Coding Agent
