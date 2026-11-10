'use strict';

/**
 * LexiLoom MCP Server (Node.js 原生零依赖版 - Stdio JSON-RPC 2.0)
 *
 * 支持特性：
 * - 零第三方 npm 依赖，同时兼容换行分隔 JSON-RPC (MCP 2024-11-05+) 与 Content-Length 帧头格式
 * - 三级凭证与配置解析：
 *   1. MCP 客户端注入的环境变量 (LEXILOOM_API_KEY, LEXILOOM_URL / LEXILOOM_SERVER_URL, LEXILOOM_WORKSPACE_ID)
 *   2. 当前工程根目录的 .lexiloom.env 与 .lexiloom/config.json（与 Skills 零配置无缝共享，动态读取即刻生效）
 *   3. 用户全局 ~/.lexiloom/.lexiloom.env 与 ~/.lexiloom/config.json
 */

const fs = require('node:fs');
const path = require('node:path');
const {
  findProjectRoot,
  sanitizeServerUrl,
  loadConfig,
  saveConfig,
  loadApiKey,
  maskKey,
  extractProblemDetail,
  lexiloomFetch,
} = require('./common.js');

const SERVER_NAME = 'lexiloom-mcp-server';
const SERVER_VERSION = '1.4.0';
const DEFAULT_PROTOCOL_VERSION = '2024-11-05';
const MAX_FILE_SIZE = 100 * 1024 * 1024; // 100 MB

const SUPPORTED_EXTS = new Set([
  'pdf', 'docx', 'doc', 'xlsx', 'xls', 'pptx', 'ppt',
  'txt', 'md', 'csv', 'tsv', 'html', 'htm', 'json',
]);

function getMimeType(ext) {
  switch (ext.toLowerCase()) {
    case 'pdf': return 'application/pdf';
    case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'doc': return 'application/msword';
    case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'xls': return 'application/vnd.ms-excel';
    case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'ppt': return 'application/vnd.ms-powerpoint';
    case 'txt': return 'text/plain';
    case 'md': return 'text/markdown';
    case 'csv': return 'text/csv';
    case 'tsv': return 'text/tab-separated-values';
    case 'html':
    case 'htm': return 'text/html';
    case 'json': return 'application/json';
    default: return 'application/octet-stream';
  }
}

const TOOLS = [
  {
    name: 'search_knowledge',
    description:
      '在 LexiLoom 知识库中执行多路混合检索（BM25 + 向量召回 + Cross-Encoder 语义重排），返回相关文档切片、标题、分类、得分、页码及视觉坐标。【Query 铁律：严禁分词，仅限轻度改写！】query 必须保持完整、通顺的自然语言句子（疑问句或陈述句），绝对禁止将问题拆解为空格分隔的关键词列表，严禁删减任何专有名词（如地名、站点名、机构名、类名等）。若用户提问本身语义清晰，请直接原样传入；仅在含代词指代不明或纯口语寒暄时做轻度改写（补全指代、去除“帮我查下”等无关前缀）。',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: '完整的自然语言检索问题（必填，非空）。【严禁分词！】禁止将句子拆成空格分隔的词组，禁止丢弃地名/机构名等专有名词。仅允许做补全指代或去除寒暄的轻度改写（若原问题清晰请直接原样传入）。正例：“泰安高铁站候车室共享按摩椅的设置比例及其引发的问题和铁路部门的后续反应是什么？”；反例（严禁）：“高铁站 候车室 共享按摩椅 设置比例 铁路部门 整改”。',
        },
        topK: {
          type: 'integer',
          description: '召回切片数量上限，范围 1–20，默认 5',
          minimum: 1,
          maximum: 20,
          default: 5,
        },
        workspaceId: {
          type: 'integer',
          description: '可选：目标工作空间 ID（不传则自动使用当前项目绑定的工作空间）',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'get_document',
    description:
      '获取 LexiLoom 知识库中指定单篇文档的完整元数据（标题、分类、审批状态 status、版本号 version、更新时间 updateTime）及完整 Markdown 正文。当检索切片上下文截断或需通读完整规范时调用。',
    inputSchema: {
      type: 'object',
      properties: {
        documentId: {
          type: 'integer',
          description: '目标文档的主键 ID（正整数）',
        },
        maxChars: {
          type: 'integer',
          description: '正文最大返回字符数（默认 30000，传 0 表示不截断全文）',
          default: 30000,
        },
      },
      required: ['documentId'],
    },
  },
  {
    name: 'import_document',
    description:
      '将本地整理提炼好的文档文件安全导入至 LexiLoom 知识库。支持 .md, .pdf, .docx, .doc, .xlsx, .xls, .pptx, .ppt, .txt, .csv, .tsv, .html, .htm, .json。严禁将未经清洗和脱敏的原始碎语直接导入。',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: {
          type: 'string',
          description: '待导入本地文件的路径（支持相对项目根目录路径或绝对路径）',
        },
        title: {
          type: 'string',
          description: '可选：指定知识库文档标题（默认使用文件名，推荐使用中文语义标题）',
        },
        categoryName: {
          type: 'string',
          description: '可选：归属分类名称（如：产品需求、技术规范、测试用例）',
        },
        categoryId: {
          type: 'integer',
          description: '可选：归属分类 ID',
        },
        workspaceId: {
          type: 'integer',
          description: '可选：覆盖默认绑定的工作空间 ID',
        },
      },
      required: ['filePath'],
    },
  },
  {
    name: 'list_workspaces',
    description:
      '查询当前 API Key 凭证有权访问的所有 LexiLoom 工作空间列表，并展示当前项目的空间绑定与凭证状态（脱敏）。',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'switch_workspace',
    description:
      '切换并绑定当前项目的默认 LexiLoom 工作空间。会向服务端校验该空间访问权限并更新本地 .lexiloom/config.json，后续检索与入库即刻生效。',
    inputSchema: {
      type: 'object',
      properties: {
        workspaceId: {
          type: 'integer',
          description: '要切换绑定的目标工作空间 ID（正整数，可通过 list_workspaces 获取）',
        },
      },
      required: ['workspaceId'],
    },
  },
];

function resolveRuntimeContext(serverOpts, explicitWorkspaceId) {
  const projectRoot = serverOpts.projectRoot
    ? path.resolve(serverOpts.projectRoot)
    : findProjectRoot();

  const apiKey = loadApiKey(projectRoot, serverOpts.apiKey);
  if (!apiKey) {
    throw new Error(
      '未检测到 LexiLoom API Key。请在 MCP 客户端 env 中设置 LEXILOOM_API_KEY，或在项目根目录配置 .lexiloom.env（可执行 npx lexiloom-skills --only-setup）。'
    );
  }

  let config = null;
  let configErr = null;
  try {
    config = loadConfig(projectRoot, {
      serverUrl: serverOpts.url,
      workspaceId: explicitWorkspaceId !== undefined ? explicitWorkspaceId : serverOpts.workspaceId,
    });
  } catch (e) {
    configErr = e;
  }

  // 解析宽松的 serverUrl 供 list_workspaces / switch_workspace / get_document 使用
  let fallbackUrl =
    serverOpts.url ||
    process.env.LEXILOOM_URL ||
    process.env.LEXILOOM_SERVER_URL ||
    '';

  if (!fallbackUrl) {
    const cfgPath = path.join(projectRoot, '.lexiloom', 'config.json');
    if (fs.existsSync(cfgPath)) {
      try {
        const raw = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
        if (raw && raw.serverUrl) fallbackUrl = raw.serverUrl;
      } catch {}
    }
  }

  const serverUrl = config
    ? config.serverUrl
    : sanitizeServerUrl(fallbackUrl || 'http://localhost:8080');

  return {
    projectRoot,
    apiKey,
    serverUrl,
    config,
    configErr,
  };
}

async function handleSearchKnowledge(args, serverOpts) {
  const query = String(args.query || '').trim();
  if (!query) {
    throw new Error('参数错误：query 不能为空。');
  }

  let topK = args.topK !== undefined && args.topK !== null ? Number(args.topK) : 5;
  if (!Number.isInteger(topK) || topK < 1 || topK > 20) {
    throw new Error('参数错误：topK 必须是 1–20 的整数。');
  }

  const ctx = resolveRuntimeContext(serverOpts, args.workspaceId);
  if (!ctx.config) {
    throw new Error(
      `未绑定工作空间 (${ctx.configErr ? ctx.configErr.message : '缺少 workspaceId'})。请先调用 list_workspaces 查看可用空间，再调用 switch_workspace 绑定，或在检索时显式传入 workspaceId。`
    );
  }

  const { serverUrl, apiKey } = ctx;
  const { workspaceId, workspaceName } = ctx.config;
  const searchUrl = `${serverUrl}/api/v1/openapi/knowledge/search`;

  let resp = await lexiloomFetch(searchUrl, {
    method: 'POST',
    apiKey,
    timeoutMs: 30000,
    headers: {
      'Content-Type': 'application/json',
      'X-Call-Source': 'CLI_SKILL',
    },
    body: JSON.stringify({ q: query, workspaceId, topK }),
  });

  if (resp.status === 405 || resp.status === 404) {
    const getParams = new URLSearchParams({
      q: query,
      workspaceId: String(workspaceId),
      topK: String(topK),
    });
    resp = await lexiloomFetch(`${searchUrl}?${getParams.toString()}`, {
      method: 'GET',
      apiKey,
      timeoutMs: 30000,
      headers: { 'X-Call-Source': 'CLI_SKILL' },
    });
  }

  if (!resp.ok) {
    let errBody = '';
    try { errBody = await resp.json(); } catch { try { errBody = await resp.text(); } catch {} }
    const detail = extractProblemDetail(errBody);
    throw new Error(`知识库检索失败 (HTTP ${resp.status})${detail ? `：${detail}` : ''}`);
  }

  const data = await resp.json();
  let results = [];
  let traceId = null;
  let totalMatches = null;

  if (data && typeof data === 'object' && !Array.isArray(data)) {
    results = data.results;
    traceId = data.traceId;
    totalMatches = data.totalMatches;
    if (results === undefined && data.data && typeof data.data === 'object' && !Array.isArray(data.data)) {
      results = data.data.results;
      traceId = traceId || data.data.traceId;
      totalMatches = totalMatches !== undefined ? totalMatches : data.data.totalMatches;
    }
    if (results === undefined && Array.isArray(data.data)) {
      results = data.data;
    }
    if (results === undefined) results = [];
  } else if (Array.isArray(data)) {
    results = data;
    totalMatches = data.length;
  }

  const traceStr = traceId ? ` | 链路 Trace ID: ${traceId}` : '';
  const totalStr = totalMatches !== null && totalMatches !== undefined ? ` (匹配总数: ${totalMatches})` : '';
  const lines = [
    `知识库检索：${workspaceName || '工作空间'}（ID: ${workspaceId}）`,
    `返回 ${results.length} 条切片${totalStr}${traceStr}。\n`,
  ];

  if (results.length === 0) {
    lines.push('未检索到相关切片。建议保持完整自然语言句子做轻度同义改写（严禁拆成空格分词或删减专有名词）、适当增大 topK 或确认相关文档已完成索引。');
  } else {
    results.forEach((item, index) => {
      if (!item || typeof item !== 'object') return;
      const title = item.documentTitle || '无标题';
      const category = item.categoryName || '未分类';
      const docId = item.documentId !== undefined ? item.documentId : '未知';
      const chunk = item.chunkIndex !== undefined ? item.chunkIndex : '未知';
      let meta = `${index + 1}. 文档：《${title}》 [${category}] | 文档 ID: ${docId} | 切片: ${chunk}`;
      if (item.pageNumber !== undefined && item.pageNumber !== null) meta += ` | 页码: ${item.pageNumber}`;
      if (item.score !== undefined && item.score !== null) meta += ` | 得分: ${item.score}`;
      if (item.deepDocCoordinates && item.deepDocCoordinates !== '[]' && item.deepDocCoordinates !== 'null') {
        meta += ` | 视觉坐标: ${item.deepDocCoordinates}`;
      }
      lines.push(meta);

      const cleanContent = String(item.content || '').trim().replace(/\n{3,}/g, '\n\n');
      if (!cleanContent) {
        lines.push('   [空切片正文]');
      } else if (cleanContent.length > 2000) {
        lines.push(cleanContent.slice(0, 2000).split('\n').map((l) => '   ' + l).join('\n'));
        lines.push(`   ... [切片内容已截断，可调用 get_document (documentId: ${docId}) 读取完整文档]`);
      } else {
        lines.push(cleanContent.split('\n').map((l) => '   ' + l).join('\n'));
      }
      lines.push('');
    });
  }

  return lines.join('\n');
}

async function handleGetDocument(args, serverOpts) {
  const docIdNum = Number(args.documentId);
  if (!Number.isInteger(docIdNum) || docIdNum <= 0) {
    throw new Error('参数错误：documentId 必须是正整数。');
  }
  const maxChars = args.maxChars !== undefined && args.maxChars !== null ? Number(args.maxChars) : 30000;
  if (!Number.isInteger(maxChars) || maxChars < 0) {
    throw new Error('参数错误：maxChars 必须是非负整数（0 表示不截断）。');
  }

  const ctx = resolveRuntimeContext(serverOpts);
  const docUrl = `${ctx.serverUrl}/api/v1/openapi/documents/${docIdNum}`;
  const resp = await lexiloomFetch(docUrl, {
    method: 'GET',
    apiKey: ctx.apiKey,
    timeoutMs: 30000,
    headers: { 'X-Call-Source': 'CLI_SKILL' },
  });

  if (!resp.ok) {
    let errBody = '';
    try { errBody = await resp.json(); } catch { try { errBody = await resp.text(); } catch {} }
    const detail = extractProblemDetail(errBody);
    throw new Error(`获取文档详情失败 (HTTP ${resp.status})${detail ? `：${detail}` : ''}`);
  }

  let doc = await resp.json();
  if (doc && typeof doc === 'object' && !('content' in doc) && doc.data && typeof doc.data === 'object') {
    doc = doc.data;
  }
  if (!doc || typeof doc !== 'object' || !('content' in doc)) {
    throw new Error('服务端返回的文档详情缺少 content 字段。');
  }

  const metaKeys = ['id', 'title', 'workspaceId', 'categoryName', 'status', 'version', 'createTime', 'updateTime'];
  const lines = ['文档详情：'];
  for (const key of metaKeys) {
    lines.push(`${key}: ${JSON.stringify(doc[key] !== undefined ? doc[key] : null)}`);
  }
  lines.push('\n--- Markdown 正文 content 开始 ---\n');

  const content = doc.content;
  if (content === null || content === undefined) {
    lines.push('[content 为 null]');
  } else if (typeof content === 'string') {
    if (maxChars > 0 && content.length > maxChars) {
      lines.push(content.slice(0, maxChars));
      lines.push(`\n[提示：文档全文共 ${content.length} 字符，已截断展示前 ${maxChars} 字符。如需全文请传 maxChars: 0]`);
    } else {
      lines.push(content);
    }
  } else {
    lines.push(JSON.stringify(content, null, 2));
  }
  lines.push('\n--- Markdown 正文 content 结束 ---');
  return lines.join('\n');
}

async function handleImportDocument(args, serverOpts) {
  const rawPath = String(args.filePath || '').trim();
  if (!rawPath) {
    throw new Error('参数错误：必须提供 filePath。');
  }

  const ctx = resolveRuntimeContext(serverOpts, args.workspaceId);
  if (!ctx.config) {
    throw new Error(
      '未绑定目标工作空间。请先调用 list_workspaces 与 switch_workspace 绑定空间，或在调用 import_document 时显式传入 workspaceId。'
    );
  }

  const fileAbsPath = path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.projectRoot, rawPath);
  let stat;
  try {
    stat = fs.statSync(fileAbsPath);
  } catch (err) {
    throw new Error(`指定的文件不存在或无法访问: ${rawPath} (${err.message})`);
  }
  if (!stat.isFile()) {
    throw new Error(`指定的路径不是普通文件: ${rawPath}`);
  }
  if (stat.size === 0) {
    throw new Error('待导入文件为空（0 字节），拒绝导入。');
  }
  if (stat.size > MAX_FILE_SIZE) {
    throw new Error(`待导入文件过大 (${(stat.size / (1024 * 1024)).toFixed(1)} MB)，超过 100 MB 上限。`);
  }

  const filename = path.basename(fileAbsPath).replace(/[\x00-\x1f\x7f"/\\?*<>|]/g, '_');
  const ext = path.extname(filename).replace(/^\./, '').toLowerCase();
  if (!SUPPORTED_EXTS.has(ext)) {
    throw new Error(
      `不支持的文件类型 (.${ext})。支持格式: ${[...SUPPORTED_EXTS].map((e) => '.' + e).join(', ')}`
    );
  }

  const mimeType = getMimeType(ext);
  const workspaceId = ctx.config.workspaceId;
  const finalTitle = (args.title || '').trim() || path.basename(filename, path.extname(filename));

  const fileBuffer = fs.readFileSync(fileAbsPath);
  const fileBlob = new Blob([fileBuffer], { type: mimeType });
  const formData = new FormData();
  formData.append('file', fileBlob, filename);
  formData.append('workspaceId', String(workspaceId));
  if (finalTitle) formData.append('title', finalTitle);
  if (args.categoryId) formData.append('categoryId', String(args.categoryId));
  if (args.categoryName) formData.append('categoryName', String(args.categoryName).trim());

  const importUrl = `${ctx.serverUrl}/api/v1/openapi/documents/import?workspaceId=${workspaceId}`;
  const resp = await lexiloomFetch(importUrl, {
    method: 'POST',
    apiKey: ctx.apiKey,
    timeoutMs: 180000,
    headers: { 'X-Call-Source': 'CLI_SKILL' },
    body: formData,
  });

  if (!resp.ok) {
    let errBody = '';
    try { errBody = await resp.json(); } catch { try { errBody = await resp.text(); } catch {} }
    const detail = extractProblemDetail(errBody);
    throw new Error(`文档导入失败 (HTTP ${resp.status})${detail ? `：${detail}` : ''}`);
  }

  let data = {};
  try { data = await resp.json(); } catch {}

  let docId = '未知';
  let title = finalTitle;
  let status = 'PROCESSING';
  let chunks = null;
  let category = args.categoryName || null;

  if (data && typeof data === 'object') {
    const rawData = data.data;
    if (typeof rawData === 'number' || typeof rawData === 'string') {
      docId = String(rawData);
    } else if (rawData && typeof rawData === 'object') {
      docId = rawData.id || rawData.documentId || docId;
      title = rawData.title || rawData.name || title;
      status = rawData.status || status;
      chunks = rawData.totalChunks !== undefined ? rawData.totalChunks : rawData.chunkCount;
      category = rawData.categoryName || rawData.category || category;
    } else {
      docId = data.id || data.documentId || docId;
      title = data.title || data.name || title;
      status = data.status || status;
      chunks = data.totalChunks !== undefined ? data.totalChunks : data.chunkCount;
      category = data.categoryName || data.category || category;
    }
  }

  return JSON.stringify(
    {
      success: true,
      documentId: docId,
      title,
      status,
      categoryName: category,
      totalChunks: chunks,
      workspaceId,
      filePath: fileAbsPath,
    },
    null,
    2
  );
}

async function fetchWorkspacesList(serverUrl, apiKey) {
  const resp = await lexiloomFetch(`${serverUrl}/api/v1/openapi/workspaces`, {
    method: 'GET',
    apiKey,
    timeoutMs: 15000,
    headers: { 'X-Call-Source': 'CLI_SKILL' },
  });

  if (!resp.ok) {
    let errBody = '';
    try { errBody = await resp.json(); } catch { try { errBody = await resp.text(); } catch {} }
    const detail = extractProblemDetail(errBody);
    throw new Error(`获取工作空间列表失败 (HTTP ${resp.status})${detail ? `：${detail}` : ''}`);
  }

  const data = await resp.json();
  const workspaces = data && typeof data === 'object' && Array.isArray(data.data) ? data.data : data;
  if (!Array.isArray(workspaces)) {
    throw new Error('服务端返回的数据格式异常，未包含工作空间列表');
  }
  return workspaces;
}

async function handleListWorkspaces(serverOpts) {
  const ctx = resolveRuntimeContext(serverOpts);
  const workspaces = await fetchWorkspacesList(ctx.serverUrl, ctx.apiKey);
  const currentId = ctx.config ? ctx.config.workspaceId : null;

  const items = workspaces.map((w) => ({
    id: w.id,
    name: (w.name || '').trim(),
    description: (w.description || '').trim(),
    totalDocuments: w.totalDocuments !== undefined && w.totalDocuments !== null ? Number(w.totalDocuments) : null,
    totalChunks: w.totalChunks !== undefined && w.totalChunks !== null ? Number(w.totalChunks) : null,
    is_current: currentId !== null && String(w.id) === String(currentId),
  }));

  return JSON.stringify(
    {
      serverUrl: ctx.serverUrl,
      projectRoot: ctx.projectRoot,
      apiKeyMasked: maskKey(ctx.apiKey),
      currentWorkspace: ctx.config
        ? { id: ctx.config.workspaceId, name: ctx.config.workspaceName }
        : null,
      totalWorkspaces: items.length,
      workspaces: items,
    },
    null,
    2
  );
}

async function handleSwitchWorkspace(args, serverOpts) {
  const targetId = Number(args.workspaceId);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    throw new Error('参数错误：workspaceId 必须是正整数。');
  }

  const ctx = resolveRuntimeContext(serverOpts);
  const workspaces = await fetchWorkspacesList(ctx.serverUrl, ctx.apiKey);
  const matched = workspaces.find((w) => String(w.id) === String(targetId));

  if (!matched) {
    const availIds = workspaces.map((w) => `${w.id} (${w.name})`).join(', ');
    throw new Error(`工作空间 ID [${targetId}] 无效或当前 Key 无权访问。可用空间: ${availIds || '无'}`);
  }

  const wid = Number(matched.id);
  const wname = (matched.name || '').trim();
  const configToSave = (ctx.config && ctx.config.raw) || {
    version: '1.0.0',
    serverUrl: ctx.serverUrl,
    workspace: {},
  };
  configToSave.serverUrl = ctx.serverUrl;
  configToSave.workspace = { id: wid, name: wname };

  saveConfig(ctx.projectRoot, configToSave);
  // 同时更新当前进程内的覆盖值，确保即使设置了环境变量也能在当前会话立即生效
  serverOpts.workspaceId = wid;

  return JSON.stringify(
    {
      success: true,
      message: `已成功切换到工作空间 [${wid}] ${wname}`,
      workspace: { id: wid, name: wname, description: (matched.description || '').trim() },
      configFile: path.join(ctx.projectRoot, '.lexiloom', 'config.json'),
    },
    null,
    2
  );
}

async function callTool(name, args = {}, serverOpts = {}) {
  switch (name) {
    case 'search_knowledge':
      return await handleSearchKnowledge(args, serverOpts);
    case 'get_document':
      return await handleGetDocument(args, serverOpts);
    case 'import_document':
      return await handleImportDocument(args, serverOpts);
    case 'list_workspaces':
      return await handleListWorkspaces(serverOpts);
    case 'switch_workspace':
      return await handleSwitchWorkspace(args, serverOpts);
    default:
      throw new Error(`未知的 MCP 工具: ${name}`);
  }
}

/**
 * 启动 Stdio MCP Server
 */
function startMcpServer(serverOpts = {}) {
  let framingMode = 'line'; // 'line' (默认 MCP 标准) 或 'header' (Content-Length 兼容)

  function sendMessage(msg) {
    const json = JSON.stringify(msg);
    if (framingMode === 'header') {
      const byteLen = Buffer.byteLength(json, 'utf8');
      process.stdout.write(`Content-Length: ${byteLen}\r\n\r\n${json}`);
    } else {
      process.stdout.write(`${json}\n`);
    }
  }

  function sendResult(id, result) {
    sendMessage({ jsonrpc: '2.0', id, result });
  }

  function sendError(id, code, message, data) {
    const error = { code, message };
    if (data !== undefined) error.data = data;
    sendMessage({ jsonrpc: '2.0', id, error });
  }

  async function handleRpcMessage(msg) {
    if (!msg || typeof msg !== 'object') return;
    const { id, method, params } = msg;
    const isNotification = id === undefined || id === null;

    try {
      switch (method) {
        case 'initialize': {
          const clientProto = params && params.protocolVersion;
          sendResult(id, {
            protocolVersion: clientProto || DEFAULT_PROTOCOL_VERSION,
            capabilities: {
              tools: {},
            },
            serverInfo: {
              name: SERVER_NAME,
              version: SERVER_VERSION,
            },
          });
          break;
        }
        case 'notifications/initialized':
        case 'notifications/cancelled':
          break;
        case 'ping':
          if (!isNotification) sendResult(id, {});
          break;
        case 'tools/list':
          sendResult(id, { tools: TOOLS });
          break;
        case 'resources/list':
          sendResult(id, { resources: [] });
          break;
        case 'resources/templates/list':
          sendResult(id, { resourceTemplates: [] });
          break;
        case 'prompts/list':
          sendResult(id, { prompts: [] });
          break;
        case 'tools/call': {
          const toolName = params && params.name;
          const toolArgs = (params && params.arguments) || {};
          try {
            const outputText = await callTool(toolName, toolArgs, serverOpts);
            sendResult(id, {
              content: [{ type: 'text', text: outputText }],
              isError: false,
            });
          } catch (toolErr) {
            sendResult(id, {
              content: [{ type: 'text', text: `错误：${toolErr.message}` }],
              isError: true,
            });
          }
          break;
        }
        default:
          if (!isNotification) {
            sendError(id, -32601, `Method not found: ${method}`);
          }
          break;
      }
    } catch (err) {
      if (!isNotification) {
        sendError(id, -32603, err.message || 'Internal error');
      }
    }
  }

  let buffer = Buffer.alloc(0);
  let inFlight = 0;
  let stdinEnded = false;

  function checkExit() {
    if (stdinEnded && inFlight === 0) {
      process.exit(0);
    }
  }

  function dispatchMessage(parsed) {
    inFlight++;
    Promise.resolve(handleRpcMessage(parsed))
      .catch(() => {})
      .finally(() => {
        inFlight--;
        checkExit();
      });
  }

  process.stdin.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);

    while (buffer.length > 0) {
      // 检查是否以 Content-Length 帧头开头
      const preview = buffer.subarray(0, Math.min(buffer.length, 64)).toString('utf8');
      if (/^Content-Length:/i.test(preview)) {
        framingMode = 'header';
        const headerEnd = buffer.indexOf('\r\n\r\n');
        const altHeaderEnd = buffer.indexOf('\n\n');
        let sepIndex = -1;
        let sepLen = 4;
        if (headerEnd !== -1 && (altHeaderEnd === -1 || headerEnd <= altHeaderEnd)) {
          sepIndex = headerEnd;
          sepLen = 4;
        } else if (altHeaderEnd !== -1) {
          sepIndex = altHeaderEnd;
          sepLen = 2;
        }
        if (sepIndex === -1) break; // 等待完整头部

        const headerStr = buffer.subarray(0, sepIndex).toString('utf8');
        const match = headerStr.match(/Content-Length:\s*(\d+)/i);
        if (!match) {
          buffer = buffer.subarray(sepIndex + sepLen);
          continue;
        }
        const contentLen = parseInt(match[1], 10);
        const totalFrameLen = sepIndex + sepLen + contentLen;
        if (buffer.length < totalFrameLen) break; // 等待完整消息体

        const bodyStr = buffer.subarray(sepIndex + sepLen, totalFrameLen).toString('utf8');
        buffer = buffer.subarray(totalFrameLen);
        try {
          const parsed = JSON.parse(bodyStr);
          dispatchMessage(parsed);
        } catch (e) {
          sendError(null, -32700, `Parse error: ${e.message}`);
        }
      } else {
        const nlIndex = buffer.indexOf('\n');
        if (nlIndex === -1) break;
        const lineStr = buffer.subarray(0, nlIndex).toString('utf8').trim();
        buffer = buffer.subarray(nlIndex + 1);
        if (!lineStr) continue;
        try {
          const parsed = JSON.parse(lineStr);
          dispatchMessage(parsed);
        } catch (e) {
          sendError(null, -32700, `Parse error: ${e.message}`);
        }
      }
    }
  });

  process.stdin.on('end', () => {
    stdinEnded = true;
    checkExit();
  });
}

module.exports = {
  TOOLS,
  callTool,
  startMcpServer,
};
