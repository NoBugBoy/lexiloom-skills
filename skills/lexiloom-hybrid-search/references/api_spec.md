# LexiLoom Hybrid Search — MVP API Contract

本文档描述 Skill 当前依赖的 REST API。路径中包含 `/mcp/` 并不代表这些端点本身就是 MCP 协议；MVP 通过 HTTP REST 调用，后续可增加 MCP Adapter 而不必改变检索语义。

## 1. 鉴权（MVP 现状）

- 请求头：`Authorization: Bearer <API_KEY>`；如后端已支持，也可兼容 `X-API-Key`。
- OpenAPI Key 按 scope 控制接口权限：`/workspaces` 需要 `kb:read`，知识库检索需要 `kb:search`，文档详情需要 `doc:read`，对话补全需要 `chat:completion`。scope 不足时后端返回 HTTP `403`，ProblemDetail 的 `detail` 字段说明缺少的权限范围，例如 `当前 API Key 未授予 kb:search 权限范围`。
- 后端权限校验也可能因工作空间白名单或用户/文档权限返回 `403`；客户端应优先展示 ProblemDetail 的 `detail`，不可用时再显示通用权限提示。`401` 表示凭证缺失、无效或未登录。
- 客户端不得将 Key 写入可提交配置、日志或检索输出。项目级 `.lexiloom.env` 应加入 `.gitignore`，文件权限建议为 `600`。
- `LEXILOOM_API_KEY` 环境变量优先于 `.lexiloom.env`。

## 2. 工作空间列表

`GET /api/v1/openapi/workspaces`

用途：初始化时列出当前凭证可访问的工作空间，用户必须选择服务端实际返回的 ID。客户端不得在失败时猜测 ID 或静默使用 `1`。

期望响应：

```json
[
  { "id": 1, "name": "研发空间", "description": "可选描述" }
]
```

若后端使用包装格式 `{ "data": [...] }`，客户端可兼容。返回 `200` 但列表为空时应停止初始化。

## 3. 知识库切片检索

推荐使用 `POST /api/v1/openapi/knowledge/search`（后端同时支持 `GET /api/v1/openapi/knowledge/search`，脚本使用 GET 便于命令行联调）。

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

## 4. 文档详情

`GET /api/v1/openapi/documents/{id}`

用于根据切片结果中的 `documentId` 按需读取单篇文档详情。后端 `McpDocumentDetailVO` 的真实字段为：

| 字段 | 类型 | 含义 |
|---|---|---|
| `id` | integer | 文档 ID |
| `title` | string | 标题 |
| `workspaceId` | integer | 工作空间 ID |
| `categoryName` | string | 分类名称 |
| `status` | string | 文档状态 |
| `version` | integer | 当前版本号 |
| `content` | string | 文档正文 |
| `createTime` | string | 创建时间 |
| `updateTime` | string | 更新时间 |

详情以 JSON 对象直接返回（不是 `data` 包装）。`scripts/get_document.sh <documentId>` 保留并展示这些实际字段及完整 `content`。客户端不应自行重命名或推导版本状态字段。

Skill 应先通过 `/knowledge/search` 获得 `documentId`，再按需请求详情，并将切片与全文核对。`403` 表示无权限；`404` 可能是文档不存在，也可能是端点未部署或路径不匹配，客户端无法仅凭状态码区分。

## 5. 错误语义

| HTTP | 客户端处理 |
|---|---|
| `200` | 校验 JSON 格式后处理结果 |
| `400` | 参数错误；提示检查 query/topK/workspaceId |
| `401` | 凭证缺失或无效 |
| `403` | 凭证无权访问目标工作空间 |
| `404` | 资源不存在，或端点未部署/路径不匹配；结合请求路径排查 |
| `429` | 限流；稍后重试 |
| `5xx` | 服务端异常；检查服务日志 |
| 网络错误/超时 | 检查 URL、网络与服务健康状态 |

错误响应不得将凭证或完整敏感响应体输出到终端。建议连接超时 5 秒、总超时 20–30 秒。

## 6. MVP 范围与后续项

当前范围：REST 检索、项目绑定配置、本地代码搜索、基础错误处理。

暂不实现：独立 Agent Key 管理、OAuth、自动轮转、复杂权限 UI、真正的 MCP Server。后续新增 MCP Adapter 时，可复用同一检索服务与响应字段。
