# LexiLoom Hybrid Search — MVP API Contract

本文档描述 Skill 当前依赖的 REST API。路径中包含 `/mcp/` 并不代表这些端点本身就是 MCP 协议；MVP 通过 HTTP REST 调用，后续可增加 MCP Adapter 而不必改变检索语义。

## 1. 鉴权（MVP 现状）

- 请求头：`Authorization: Bearer <API_KEY>`；如后端已支持，也可兼容 `X-API-Key`。
- 当前 MVP 暂时沿用已有管理员 API Key 机制。密钥管理、最小权限、过期和轮转策略留待后续阶段，不在本 Skill 中实现。
- 客户端不得将 Key 写入可提交配置、日志或检索输出。项目级 `.lexiloom.env` 应加入 `.gitignore`，文件权限建议为 `600`。
- `LEXILOOM_API_KEY` 环境变量优先于 `.lexiloom.env`。

## 2. 工作空间列表

`GET /api/ai/mcp/workspaces`

用途：初始化时列出当前凭证可访问的工作空间，用户必须选择服务端实际返回的 ID。客户端不得在失败时猜测 ID 或静默使用 `1`。

期望响应：

```json
[
  { "id": 1, "name": "研发空间", "description": "可选描述" }
]
```

若后端使用包装格式 `{ "data": [...] }`，客户端可兼容。返回 `200` 但列表为空时应停止初始化。

## 3. 知识库切片检索

`GET /api/ai/mcp/search`（若后端只实现 POST，则客户端需同步调整）

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---:|---|
| `q` | string | 是 | — | 自然语言查询 |
| `workspaceId` | integer | 建议 | 项目绑定空间 | 工作空间 ID |
| `topK` | integer | 否 | 5 | 返回条数，MVP 客户端限制为 1–20 |
| `minScore` | number | 否 | 后端默认 | 可选相似度阈值；当前脚本不传 |

推荐响应：

```json
{
  "query": "Token 统计规则",
  "workspaceId": 1,
  "totalMatches": 1,
  "results": [
    {
      "chunkId": "chunk-id",
      "documentId": 105,
      "documentTitle": "文档标题",
      "content": "可引用的文档切片正文",
      "score": 0.92,
      "chunkIndex": 3,
      "pageNumber": 2
    }
  ]
}
```

客户端兼容顶层数组以及 `{ "data": { "results": [...] } }` 包装响应。`score` 是检索系统的相关度指标，不是事实正确率或置信概率。

## 4. 文档详情（可选）

`GET /api/ai/mcp/documents/{id}`

用于后续需要读取完整文档时。当前两个 shell 脚本不依赖此端点，若后端尚未实现，不影响切片检索 MVP。

## 5. 错误语义

| HTTP | 客户端处理 |
|---|---|
| `200` | 校验 JSON 格式后处理结果 |
| `400` | 参数错误；提示检查 query/topK/workspaceId |
| `401` | 凭证缺失或无效 |
| `403` | 凭证无权访问目标工作空间 |
| `404` | 端点未部署或路径不匹配 |
| `429` | 限流；稍后重试 |
| `5xx` | 服务端异常；检查服务日志 |
| 网络错误/超时 | 检查 URL、网络与服务健康状态 |

错误响应不得将凭证或完整敏感响应体输出到终端。建议连接超时 5 秒、总超时 20–30 秒。

## 6. MVP 范围与后续项

当前范围：REST 检索、项目绑定配置、本地代码搜索、基础错误处理。

暂不实现：独立 Agent Key 管理、OAuth、自动轮转、复杂权限 UI、真正的 MCP Server。后续新增 MCP Adapter 时，可复用同一检索服务与响应字段。
