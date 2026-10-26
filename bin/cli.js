#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');
const { spawnSync } = require('node:child_process');

const PACKAGE_ROOT = path.resolve(__dirname, '..');
const SKILLS_ROOT = path.join(PACKAGE_ROOT, 'skills');
const DEFAULT_SKILL = 'lexiloom-hybrid-search';
const HOME = os.homedir();

const AGENTS = {
  codex: {
    label: 'OpenAI Codex',
    project: (cwd) => path.join(cwd, '.agents', 'skills'),
    global: () => path.join(HOME, '.agents', 'skills'),
  },
  claude: {
    label: 'Claude Code',
    project: (cwd) => path.join(cwd, '.claude', 'skills'),
    global: () => path.join(HOME, '.claude', 'skills'),
  },
  cursor: {
    label: 'Cursor',
    project: (cwd) => path.join(cwd, '.cursor', 'skills'),
    global: () => path.join(HOME, '.cursor', 'skills'),
  },
  windsurf: {
    label: 'Windsurf',
    project: (cwd) => path.join(cwd, '.windsurf', 'skills'),
    global: () => path.join(HOME, '.codeium', 'windsurf', 'skills'),
  },
  copilot: {
    label: 'GitHub Copilot',
    project: (cwd) => path.join(cwd, '.github', 'skills'),
    global: () => path.join(HOME, '.copilot', 'skills'),
  },
  gemini: {
    label: 'Gemini CLI',
    project: (cwd) => path.join(cwd, '.gemini', 'skills'),
    global: () => path.join(HOME, '.gemini', 'skills'),
  },
  antigravity: {
    label: 'Antigravity',
    project: (cwd) => path.join(cwd, '.agents', 'skills'),
    global: () => path.join(HOME, '.gemini', 'config', 'skills'),
  },
  cline: {
    label: 'Cline',
    project: (cwd) => path.join(cwd, '.cline', 'skills'),
    global: () => path.join(HOME, '.cline', 'skills'),
  },
  roo: {
    label: 'Roo Code',
    project: (cwd) => path.join(cwd, '.roo', 'skills'),
    global: () => path.join(HOME, '.roo', 'skills'),
  },
  opencode: {
    label: 'OpenCode',
    project: (cwd) => path.join(cwd, '.opencode', 'skills'),
    global: () => path.join(HOME, '.config', 'opencode', 'skills'),
  },
  trae: {
    label: 'Trae',
    project: (cwd) => path.join(cwd, '.trae', 'skills'),
    global: () => path.join(HOME, '.trae', 'skills'),
  },
  goose: {
    label: 'Goose',
    project: (cwd) => path.join(cwd, '.goose', 'skills'),
    global: () => path.join(HOME, '.config', 'goose', 'skills'),
  },
  pi: {
    label: 'Pi',
    project: (cwd) => path.join(cwd, '.pi', 'skills'),
    global: () => path.join(HOME, '.pi', 'agent', 'skills'),
  },
};

function discoverSkills() {
  if (!fs.existsSync(SKILLS_ROOT)) return new Map();
  const entries = fs.readdirSync(SKILLS_ROOT, { withFileTypes: true });
  const skills = new Map();
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const skillDir = path.join(SKILLS_ROOT, entry.name);
    const skillMd = path.join(skillDir, 'SKILL.md');
    if (!fs.existsSync(skillMd)) continue;
    const content = fs.readFileSync(skillMd, 'utf8');
    let description = '';
    const fmMatch = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    if (fmMatch) {
      const descLine = fmMatch[1].match(/description:\s*(?:>-\s*\r?\n((?:\s+.*\r?\n?)+)|(.+))/);
      if (descLine) {
        description = (descLine[1] || descLine[2] || '').replace(/\s+/g, ' ').trim();
      }
    }
    skills.set(entry.name, {
      name: entry.name,
      dir: skillDir,
      description: description || 'LexiLoom Agent Skill',
    });
  }
  return skills;
}

function usage() {
  const agentKeys = Object.keys(AGENTS).join(', ');
  console.log(`LexiLoom Agent Skills Installer

Usage:
  npx lexiloom-hybrid-search [options]
  npx lexiloom-skills [options]

Options:
  -g, --global             Install globally for all supported agents
  --scope project|global   Install scope (default: interactive)
  --agent <list|all>       Agent names, comma-separated or "all":
                           ${agentKeys}
  --skill <list|all>       Skill names, comma-separated or "all" (default: all)
  --list                   List available skills and supported agents
  --only-install           Install skills without starting workspace setup wizard
  --only-setup             Start workspace setup wizard without installing skills
  --uninstall              Remove skills from selected targets
  -y, --yes                Skip confirmation prompts (requires --scope and --agent, or -g)
  -h, --help               Show this help

Examples:
  npx lexiloom-hybrid-search
  npx lexiloom-hybrid-search --list
  npx lexiloom-hybrid-search -g --only-install
  npx lexiloom-hybrid-search --scope project --agent codex,claude,cursor
  npx lexiloom-hybrid-search --scope global --agent all --only-install --yes
  npx lexiloom-hybrid-search --only-setup
  npx lexiloom-hybrid-search --scope project --agent codex --uninstall --yes`);
}

function parseArgs(argv) {
  const opts = {
    scope: '',
    agent: '',
    skill: '',
    list: false,
    onlyInstall: false,
    onlySetup: false,
    uninstall: false,
    yes: false,
    help: false,
    legacyGlobal: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--scope' || arg === '--agent' || arg === '--skill') {
      const value = argv[++i];
      if (!value || value.startsWith('-')) throw new Error(`缺少 ${arg} 参数值`);
      opts[arg.slice(2)] = value;
    } else if (arg === '-g' || arg === '--global') {
      opts.scope = 'global';
      opts.legacyGlobal = true;
    } else if (arg === '--list' || arg === '-l') opts.list = true;
    else if (arg === '--only-install') opts.onlyInstall = true;
    else if (arg === '--only-setup') opts.onlySetup = true;
    else if (arg === '--uninstall') opts.uninstall = true;
    else if (arg === '--yes' || arg === '-y') opts.yes = true;
    else if (arg === '--help' || arg === '-h') opts.help = true;
    else throw new Error(`未知参数：${arg}（使用 --help 查看帮助）`);
  }
  if (opts.scope && !['project', 'global'].includes(opts.scope)) {
    throw new Error('--scope 只能是 project 或 global');
  }
  if (opts.onlyInstall && opts.onlySetup) {
    throw new Error('--only-install 与 --only-setup 不能同时使用');
  }
  if (opts.onlySetup && opts.uninstall) {
    throw new Error('--only-setup 不能与 --uninstall 同时使用');
  }
  if (opts.yes && !opts.help && !opts.list && !opts.onlySetup && !opts.legacyGlobal && (!opts.scope || !opts.agent)) {
    throw new Error('--yes 非交互模式下必须同时指定 --scope 和 --agent（或使用 -g）');
  }
  return opts;
}

function parseAgents(value) {
  const tokens = value.split(',').map((x) => x.trim().toLowerCase()).filter(Boolean);
  if (tokens.includes('all') || tokens.includes('*')) {
    return Object.keys(AGENTS);
  }
  const names = [...new Set(tokens)];
  const unknown = names.filter((name) => !AGENTS[name]);
  if (!names.length || unknown.length) {
    throw new Error(
      `Agent 参数无效。可选值：all, ${Object.keys(AGENTS).join(', ')}${unknown.length ? `；未知值：${unknown.join(', ')}` : ''}`
    );
  }
  return names;
}

function parseSkills(value, availableSkills) {
  if (!value || value.trim().toLowerCase() === 'all' || value.trim() === '*') {
    return [...availableSkills.keys()];
  }
  const names = [...new Set(value.split(',').map((x) => x.trim()).filter(Boolean))];
  const unknown = names.filter((name) => !availableSkills.has(name));
  if (!names.length || unknown.length) {
    throw new Error(
      `Skill 参数无效。可用技能：${[...availableSkills.keys()].join(', ')}${unknown.length ? `；未知技能：${unknown.join(', ')}` : ''}`
    );
  }
  return names;
}

function printCatalog(availableSkills) {
  console.log('📦 可用 Skills：');
  for (const skill of availableSkills.values()) {
    console.log(`  - ${skill.name}: ${skill.description}`);
  }
  console.log('\n🤖 支持的编码 Agents：');
  for (const [key, agent] of Object.entries(AGENTS)) {
    console.log(`  - ${key.padEnd(12)} ${agent.label.padEnd(16)} 项目级: ${ path.relative(process.cwd(), agent.project(process.cwd())) || '.' } | 全局: ${agent.global()}`);
  }
}

async function ask(rl, question, fallback) {
  const answer = (await rl.question(`${question}${fallback ? ` [${fallback}]` : ''}: `)).trim();
  return answer || fallback;
}

function hasProjectRootMarker(startDir) {
  let dir = path.resolve(startDir);
  const markers = ['.lexiloom', '.git', 'pom.xml', 'package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml', 'build.gradle', 'build.gradle.kts'];
  while (true) {
    if (markers.some((m) => fs.existsSync(path.join(dir, m)))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

function findSetupScript(targets = [], availableSkills = new Map()) {
  const candidates = [
    ...targets.map((target) => path.join(target, 'scripts', 'setup.sh')),
    ...Object.values(AGENTS).map((agent) =>
      path.join(agent.project(process.cwd()), DEFAULT_SKILL, 'scripts', 'setup.sh')
    ),
  ];
  for (const skill of availableSkills.values()) {
    candidates.push(path.join(skill.dir, 'scripts', 'setup.sh'));
  }
  return candidates.find((candidate) => fs.existsSync(candidate));
}

function runSetup(targets, availableSkills) {
  const setupScript = findSetupScript(targets, availableSkills);
  if (!setupScript) throw new Error('未找到 setup.sh 引导脚本，请检查技能安装完整性');
  fs.chmodSync(setupScript, 0o755);
  const result = spawnSync('bash', [setupScript], {
    stdio: 'inherit',
    cwd: process.cwd(),
  });
  if (result.error) throw new Error(`执行初始化脚本失败：${result.error.message}`);
  if (result.status !== 0) {
    const suffix = result.signal ? `（信号：${result.signal}）` : `（退出码：${result.status}）`;
    throw new Error(`初始化脚本执行失败${suffix}`);
  }
}

function safeReplaceDirectory(target) {
  if (!fs.existsSync(target)) return;
  const stat = fs.lstatSync(target);
  if (stat.isSymbolicLink()) throw new Error(`目标是软链接，为避免误删用户数据已停止：${target}`);
  if (!stat.isDirectory()) throw new Error(`目标存在但不是目录：${target}`);
  const marker = path.join(target, 'SKILL.md');
  if (!fs.existsSync(marker)) throw new Error(`目标目录已存在但不是可识别的 Skill 安装，未覆盖：${target}`);
  fs.rmSync(target, { recursive: true, force: true });
}

function installSkillTo(sourceDir, target) {
  if (!fs.existsSync(path.join(sourceDir, 'SKILL.md'))) {
    throw new Error(`安装包缺少 Skill 源文件：${sourceDir}`);
  }
  fs.mkdirSync(path.dirname(target), { recursive: true });
  safeReplaceDirectory(target);
  fs.cpSync(sourceDir, target, { recursive: true, dereference: false });

  const scriptsDir = path.join(target, 'scripts');
  if (fs.existsSync(scriptsDir) && fs.statSync(scriptsDir).isDirectory()) {
    for (const entry of fs.readdirSync(scriptsDir)) {
      if (entry.endsWith('.sh')) {
        const scriptPath = path.join(scriptsDir, entry);
        if (fs.statSync(scriptPath).isFile()) {
          fs.chmodSync(scriptPath, 0o755);
        }
      }
    }
  }
}

function uninstallFrom(target) {
  if (!fs.existsSync(target)) return 'missing';
  const stat = fs.lstatSync(target);
  if (stat.isSymbolicLink()) throw new Error(`目标是软链接，为避免误删用户数据已停止：${target}`);
  if (!stat.isDirectory() || !fs.existsSync(path.join(target, 'SKILL.md'))) {
    throw new Error(`目标目录不是可识别的 Skill 安装，未删除：${target}`);
  }
  fs.rmSync(target, { recursive: true, force: true });
  return 'removed';
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) return usage();

  const availableSkills = discoverSkills();
  if (availableSkills.size === 0) {
    throw new Error(`找不到任何可安装的 Skill 文件：${SKILLS_ROOT}`);
  }

  if (opts.list) {
    printCatalog(availableSkills);
    return;
  }

  if (opts.onlySetup) {
    runSetup([], availableSkills);
    return;
  }

  const interactive = !opts.legacyGlobal && !opts.yes && (!opts.scope || !opts.agent);
  const rl = interactive ? readline.createInterface({ input, output }) : null;
  try {
    const scope =
      opts.scope ||
      (await ask(rl, '安装范围：1) 当前项目  2) 当前用户全局', '1').then(
        (v) => ({ '1': 'project', '2': 'global', project: 'project', global: 'global' }[v] || '')
      ));
    if (!['project', 'global'].includes(scope)) {
      throw new Error('安装范围无效，请选择 1 或 2，或使用 --scope project|global');
    }

    let agents;
    if (opts.agent) {
      agents = parseAgents(opts.agent);
    } else if (opts.legacyGlobal) {
      agents = Object.keys(AGENTS);
    } else {
      const agentKeys = Object.keys(AGENTS);
      console.log('\n可选 Agent（输入编号、名称，多个用逗号分隔，输入 all 选择全部）：');
      Object.entries(AGENTS).forEach(([key, value], i) =>
        console.log(`  ${String(i + 1).padStart(2, ' ')}) ${value.label} (${key})`)
      );
      const raw = await ask(rl, '选择 Agent', 'codex');
      const mapped = raw
        .split(',')
        .map((x) => {
          const token = x.trim();
          if (/^\d+$/.test(token)) {
            const idx = Number(token) - 1;
            if (idx < 0 || idx >= agentKeys.length) {
              throw new Error(`Agent 编号超出范围：${token}（有效范围 1–${agentKeys.length}）`);
            }
            return agentKeys[idx];
          }
          return token;
        })
        .join(',');
      agents = parseAgents(mapped);
    }

    const selectedSkills = parseSkills(opts.skill, availableSkills);
    const cwd = process.cwd();

    // Build deduplicated installation plan: Map<targetPath, skillInfo>
    const plan = new Map();
    for (const skillName of selectedSkills) {
      const skillInfo = availableSkills.get(skillName);
      for (const agentName of agents) {
        const base = scope === 'project' ? AGENTS[agentName].project(cwd) : AGENTS[agentName].global();
        const targetPath = path.join(base, skillName);
        plan.set(targetPath, skillInfo);
      }
    }

    const targets = [...plan.keys()];
    console.log(`\n操作：${opts.uninstall ? '卸载' : '安装 / 更新'}`);
    console.log(`技能：${selectedSkills.join(', ')}`);
    console.log(`范围：${scope === 'project' ? `当前项目 (${cwd})` : `当前用户全局 (${HOME})`}`);
    targets.forEach((target) => console.log(`  ${opts.uninstall ? '删除' : '目标'}：${target}`));

    if (!opts.yes && rl) {
      const confirm = await ask(rl, '确认继续？(y/N)', 'N');
      if (!/^y(es)?$/i.test(confirm)) {
        console.log('已取消。');
        return;
      }
    }

    let failures = 0;
    for (const [target, skillInfo] of plan.entries()) {
      try {
        if (opts.uninstall) {
          const result = uninstallFrom(target);
          console.log(result === 'removed' ? `✓ 已卸载：${target}` : `- 未安装，跳过：${target}`);
        } else {
          installSkillTo(skillInfo.dir, target);
          console.log(`✓ 已安装：${target}`);
        }
      } catch (error) {
        failures++;
        console.error(`✗ ${error.message}`);
      }
    }

    if (failures) {
      process.exitCode = 1;
      return;
    }

    if (opts.uninstall) return;

    if (opts.onlyInstall) {
      console.log('\n技能安装完成，已按要求跳过初始化向导。');
      return;
    }

    // Check if workspace setup wizard can and should run
    const projectRoot = hasProjectRootMarker(cwd);
    const hasNonInteractiveSetupEnv = Boolean(
      process.env.LEXILOOM_SERVER_URL && process.env.LEXILOOM_WORKSPACE_ID && process.env.LEXILOOM_API_KEY
    );

    if (scope === 'global' && !projectRoot) {
      console.log(
        '\n技能已全局安装完成。当前目录不是代码仓库，跳过项目工作空间绑定（后续可在目标代码仓库内执行 `npx lexiloom-hybrid-search --only-setup`）。'
      );
      return;
    }

    if (opts.yes && !input.isTTY && !hasNonInteractiveSetupEnv) {
      console.log(
        '\n技能已安装完成。检测到非交互终端（无 TTY），已跳过交互式工作空间绑定向导（可后续执行 `npx lexiloom-hybrid-search --only-setup`）。'
      );
      return;
    }

    console.log('\n🚀 正在启动工程工作空间绑定向导...');
    // Release stdin from the parent readline interface before handing the
    // terminal to setup.sh; otherwise it can consume the child's prompts.
    if (rl) rl.close();
    runSetup(targets, availableSkills);
  } finally {
    if (rl) rl.close();
  }
}

main().catch((error) => {
  console.error(`错误：${error.message}`);
  process.exitCode = 1;
});
