#!/usr/bin/env node
'use strict';

/**
 * 将包级单源共享模块 (lib/common.js) 及核心脚本同步到各 Skill 的 scripts/ 目录，
 * 既消除手动维护三份重复代码的负担，又保证外部社区安装器 (如 `npx skills add`)
 * 直接克隆复制单个 skill 目录时依然 100% 自包含可用。
 */

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const LIB_COMMON = path.join(ROOT, 'lib', 'common.js');
const CANONICAL_SCRIPTS_DIR = path.join(ROOT, 'skills', 'lexiloom-hybrid-search', 'scripts');

const SKILL_TARGETS = [
  {
    name: 'lexiloom-hybrid-search',
    scripts: ['_common.js'],
  },
  {
    name: 'lexiloom-knowledge-harvest',
    scripts: [
      '_common.js',
      'get_document.js',
      'get_document.sh',
      'import_document.js',
      'import_document.sh',
      'manage_workspace.js',
      'search_code.js',
      'search_code.sh',
      'search_knowledge.js',
      'search_knowledge.sh',
      'setup.js',
      'setup.sh',
      'switch_key.sh',
      'switch_workspace.sh',
    ],
  },
  {
    name: 'lexiloom-workspace-manager',
    scripts: [
      '_common.js',
      'manage_workspace.js',
      'switch_key.sh',
      'switch_workspace.sh',
    ],
  },
];

function syncAll() {
  // 1. 先将 lib/common.js 同步至 canonical 目录
  fs.copyFileSync(LIB_COMMON, path.join(CANONICAL_SCRIPTS_DIR, '_common.js'));

  // 2. 将 canonical 脚本分发至其余 skill 目录
  for (const target of SKILL_TARGETS) {
    const targetDir = path.join(ROOT, 'skills', target.name, 'scripts');
    if (!fs.existsSync(targetDir)) continue;
    for (const file of target.scripts) {
      const src = file === '_common.js' ? LIB_COMMON : path.join(CANONICAL_SCRIPTS_DIR, file);
      const dst = path.join(targetDir, file);
      if (fs.existsSync(src) && src !== dst) {
        fs.copyFileSync(src, dst);
      }
    }
  }
  console.log('✓ 已同步 lib/common.js 及共享脚本至全部 skills/*/scripts/ 目录。');
}

if (require.main === module) {
  syncAll();
}

module.exports = { syncAll };
