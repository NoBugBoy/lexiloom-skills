#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const args = process.argv.slice(2);
const isHelp = args.includes('--help') || args.includes('-h');
const isOnlyInstall = args.includes('--only-install');
const isOnlySetup = args.includes('--only-setup');
const isGlobal = args.includes('-g') || args.includes('--global');

if (isHelp) {
  console.log(`
LexiLoom Skills 一键安装与配置管理器

用法:
  npx github:NoBugBoy/lexiloom-skills [选项]
  (或发布后: npx lexiloom-skills [选项])

选项:
  -g, --global       安装至用户全局 Agent 目录 (~/.gemini, ~/.claude, ~/.codex)
  --only-install     仅安装技能文件，跳过交互式初始化向导
  --only-setup       跳过安装，直接运行当前工程的初始化绑定向导
  -h, --help         显示帮助信息
`);
  process.exit(0);
}

console.log('=================================================================');
console.log('  🧠 LexiLoom AI Agent Skills 一键安装与初始化向导');
console.log('=================================================================');

const projectRoot = process.cwd();
const localSkillSource = path.join(__dirname, '..', 'lexiloom-hybrid-search');

// ==========================================
// 第一阶段：安装技能 (Install Skills)
// ==========================================
if (!isOnlySetup) {
  console.log('\n📦 [1/2] 正在安装 LexiLoom Skills...');

  let installSuccess = false;

  // 1. 尝试使用 skills CLI 标准安装
  try {
    const skillsCmd = isGlobal
      ? ['skills', 'add', 'NoBugBoy/lexiloom-skills', '-g', '--all']
      : ['skills', 'add', 'NoBugBoy/lexiloom-skills', '--all'];

    const res = spawnSync('npx', ['--yes', ...skillsCmd], {
      stdio: 'inherit',
      cwd: projectRoot,
    });

    if (res.status === 0) {
      installSuccess = true;
    }
  } catch (err) {
    // skills CLI 失败，转入内置兜底
  }

  // 2. 兜底策略：使用包内置的技能文件直接挂载
  if (!installSuccess && fs.existsSync(localSkillSource)) {
    console.log('ℹ️  使用内置技能模板直接挂载至工程...');
    try {
      const targetSkillDir = isGlobal
        ? path.join(process.env.HOME || '', '.gemini', 'config', 'skills', 'lexiloom-hybrid-search')
        : path.join(projectRoot, '.agents', 'skills', 'lexiloom-hybrid-search');

      fs.mkdirSync(path.dirname(targetSkillDir), { recursive: true });
      fs.cpSync(localSkillSource, targetSkillDir, { recursive: true });

      // 为主流 Agent 创建软链接 (非全局模式)
      if (!isGlobal) {
        const linkTargets = [
          path.join(projectRoot, '.claude', 'skills', 'lexiloom-hybrid-search'),
          path.join(projectRoot, '.codex', 'skills', 'lexiloom-hybrid-search'),
        ];
        for (const linkPath of linkTargets) {
          try {
            fs.mkdirSync(path.dirname(linkPath), { recursive: true });
            if (!fs.existsSync(linkPath)) {
              fs.symlinkSync(targetSkillDir, linkPath, 'dir');
            }
          } catch (e) {}
        }
      }

      installSuccess = true;
      console.log(`✅ 技能已成功挂载至: ${targetSkillDir}`);
    } catch (err) {
      console.error(`❌ 兜底安装失败: ${err.message}`);
    }
  }

  // 确保脚本具有执行权限
  const installedScriptDir = isGlobal
    ? path.join(process.env.HOME || '', '.gemini', 'config', 'skills', 'lexiloom-hybrid-search', 'scripts')
    : path.join(projectRoot, '.agents', 'skills', 'lexiloom-hybrid-search', 'scripts');

  if (fs.existsSync(installedScriptDir)) {
    try {
      const files = fs.readdirSync(installedScriptDir);
      for (const file of files) {
        if (file.endsWith('.sh')) {
          fs.chmodSync(path.join(installedScriptDir, file), 0o755);
        }
      }
    } catch (e) {}
  }
}

// ==========================================
// 第二阶段：初始化向导 (Setup Wizard)
// ==========================================
if (isOnlyInstall) {
  console.log('\n🎉 技能安装完成！已按要求跳过初始化向导。');
  process.exit(0);
}

console.log('\n🚀 [2/2] 正在启动工程工作空间绑定向导...');

// 寻找 setup.sh 的位置
let setupScriptPath = path.join(
  projectRoot,
  '.agents',
  'skills',
  'lexiloom-hybrid-search',
  'scripts',
  'setup.sh'
);

if (!fs.existsSync(setupScriptPath)) {
  setupScriptPath = path.join(localSkillSource, 'scripts', 'setup.sh');
}

if (!fs.existsSync(setupScriptPath)) {
  console.error('❌ 未找到 setup.sh 引导脚本，请检查技能安装完整性。');
  process.exit(1);
}

try {
  fs.chmodSync(setupScriptPath, 0o755);
  const setupProcess = spawnSync('bash', [setupScriptPath], {
    stdio: 'inherit',
    cwd: projectRoot,
  });
  process.exit(setupProcess.status || 0);
} catch (err) {
  console.error(`❌ 执行初始化脚本失败: ${err.message}`);
  process.exit(1);
}
