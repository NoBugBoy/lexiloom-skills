#!/usr/bin/env node
'use strict';

/**
 * LexiLoom MCP Server CLI Entrypoint
 * 等价于 `npx lexiloom-skills mcp`
 */

const process = require('node:process');
process.argv.splice(2, 0, 'mcp');
require('./cli.js');
