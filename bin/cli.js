#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');

const SKILL_NAME = 'lexiloom-hybrid-search';
const PACKAGE_ROOT = path.resolve(__dirname, '..');
const SOURCE_DIR = path.join(PACKAGE_ROOT, 'skills', SKILL_NAME);
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
  gemini: {
    label: 'Gemini CLI',
    project: (cwd) => path.join(cwd, '.gemini', 'skills'),
    global: () => path.join(HOME, '.gemini', 'skills'),
  },
  antigravity: {
    label: 'Antigravity',
    project: (cwd) => path.join(cwd, '.agents', 'skills'),
    global: () => path.join(HOME, '.gemini', 'antigravity', 'skills'),
  },
  pi: {
    label: 'Pi',
    project: (cwd) => path.join(cwd, '.pi', 'skills'),
    global: () => path.join(HOME, '.pi', 'agent', 'skills'),
  },
};

function usage() {
  console.log(`LexiLoom Hybrid Search Skill installer\n\nUsage:\n  npx lexiloom-hybrid-search [options]\n\nOptions:\n  -g, --global             Install globally for all supported agents\n  --scope project|global   Install scope (default: interactive)\n  --agent <list>           Agent names, comma-separated: codex,claude,gemini,antigravity,pi\n  --uninstall              Remove the Skill from selected targets\n  --yes                    Do not ask for confirmation (requires --scope and --agent)\n  -h, --help               Show this help\n\nExamples:\n  npx lexiloom-hybrid-search\n  npx lexiloom-hybrid-search -g\n  npx lexiloom-hybrid-search --scope project --agent codex,claude\n  npx lexiloom-hybrid-search --scope global --agent pi --yes`);
}

function parseArgs(argv) {
  const opts = { scope: '', agent: '', uninstall: false, yes: false, help: false, legacyGlobal: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--scope' || arg === '--agent') {
      const value = argv[++i];
      if (!value) throw new Error(`缺少 ${arg} 参数`);
      opts[arg.slice(2)] = value;
    } else if (arg === '-g' || arg === '--global') {
      opts.scope = 'global';
      opts.legacyGlobal = true;
    } else if (arg === '--uninstall') opts.uninstall = true;
    else if (arg === '--yes' || arg === '-y') opts.yes = true;
    else if (arg === '--help' || arg === '-h') opts.help = true;
    else throw new Error(`未知参数：${arg}`);
  }
  if (opts.scope && !['project', 'global'].includes(opts.scope)) throw new Error('--scope 只能是 project 或 global');
  return opts;
}

function parseAgents(value) {
  const names = [...new Set(value.split(',').map(x => x.trim().toLowerCase()).filter(Boolean))];
  const unknown = names.filter(name => !AGENTS[name]);
  if (!names.length || unknown.length) throw new Error(`Agent 参数无效。可选值：${Object.keys(AGENTS).join(', ')}${unknown.length ? `；未知值：${unknown.join(', ')}` : ''}`);
  return names;
}

async function ask(rl, question, fallback) {
  const answer = (await rl.question(`${question}${fallback ? ` [${fallback}]` : ''}: `)).trim();
  return answer || fallback;
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

function installTo(target) {
  if (!fs.existsSync(path.join(SOURCE_DIR, 'SKILL.md'))) throw new Error(`安装包缺少 Skill 源文件：${SOURCE_DIR}`);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  safeReplaceDirectory(target);
  fs.cpSync(SOURCE_DIR, target, { recursive: true, dereference: false });
  for (const file of ['setup.sh', 'search_code.sh', 'search_knowledge.sh']) {
    const p = path.join(target, 'scripts', file);
    if (fs.existsSync(p)) fs.chmodSync(p, 0o755);
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
  if (!fs.existsSync(SOURCE_DIR)) throw new Error(`找不到待安装的 Skill 文件：${SOURCE_DIR}`);

  const interactive = !opts.legacyGlobal && !opts.yes && (!opts.scope || !opts.agent);
  const rl = interactive ? readline.createInterface({ input, output }) : null;
  try {
    const scope = opts.scope || await ask(rl, '安装范围：1) 当前项目  2) 当前用户全局', '1').then(v => ({ '1': 'project', '2': 'global', project: 'project', global: 'global' }[v] || ''));
    if (!['project', 'global'].includes(scope)) throw new Error('安装范围无效，请选择 1 或 2，或使用 --scope project|global');

    let agents;
    if (opts.agent) agents = parseAgents(opts.agent);
    else if (opts.legacyGlobal) agents = Object.keys(AGENTS);
    else {
      console.log('\n可选 Agent：');
      Object.entries(AGENTS).forEach(([key, value], i) => console.log(`  ${i + 1}) ${value.label} (${key})`));
      const raw = await ask(rl, '输入 Agent 名称，多个用逗号分隔', 'codex');
      agents = parseAgents(raw.split(',').map(x => /^\d+$/.test(x.trim()) ? Object.keys(AGENTS)[Number(x.trim()) - 1] : x.trim()).join(','));
    }

    const cwd = process.cwd();
    const targets = [...new Set(agents.map(name => {
      const base = scope === 'project' ? AGENTS[name].project(cwd) : AGENTS[name].global();
      return path.join(base, SKILL_NAME);
    }))];

    console.log(`\n操作：${opts.uninstall ? '卸载' : '安装 / 更新'}`);
    console.log(`范围：${scope === 'project' ? `当前项目 (${cwd})` : `当前用户 (${HOME})`}`);
    targets.forEach(target => console.log(`  ${opts.uninstall ? '删除' : '目标'}：${target}`));
    if (!opts.yes && rl) {
      const confirm = await ask(rl, '确认继续？(y/N)', 'N');
      if (!/^y(es)?$/i.test(confirm)) { console.log('已取消。'); return; }
    }

    let failures = 0;
    for (const target of targets) {
      try {
        if (opts.uninstall) {
          const result = uninstallFrom(target);
          console.log(result === 'removed' ? `✓ 已卸载：${target}` : `- 未安装，跳过：${target}`);
        } else {
          installTo(target);
          console.log(`✓ 已安装：${target}`);
        }
      } catch (error) {
        failures++;
        console.error(`✗ ${error.message}`);
      }
    }
    if (failures) process.exitCode = 1;
    else if (!opts.uninstall) {
      console.log('\n下一步：进入目标代码仓库，执行：');
      console.log(`  bash "${targets[0]}/scripts/setup.sh"`);
      console.log('配置服务地址与工作空间后，即可让 Agent 使用该 Skill。');
    }
  } finally {
    if (rl) rl.close();
  }
}

main().catch(error => { console.error(`错误：${error.message}`); process.exitCode = 1; });
