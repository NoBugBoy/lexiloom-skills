# LexiLoom Hybrid Search — OpenAPI Contract Reference

本文档描述本技能脚本（`scripts/*.sh`）所调用的 LexiLoom OpenAPI REST 接口契约，供排查接口异常或核对字段语义时参考。日常检索请直接调用 `scripts/` 下的脚本，不要手写包含明文 API Key 的请求。

## 1. 鉴权与安全约定

- 请求头：`Authorization: Bearer <API_KEY>`（脚本通过 `curl --config -` 从标准输入传入，避免在进程列表中暴露命令参数）。
- 知识库检索请求额外发送 `X-Call-Source: CLI_SKILL`，用于标识该检索来自 CLI Skill；工作空间发现和文档详情请求不发送此请求头。
- OpenAPI Key 按 scope 控制接口权限：
  - `/api/v1/openapi/workspaces`：需要 `kb:read`
  - `/api/v1/openapi/knowledge/search`：需要 `kb:search`
  - `/api/v1/openapi/documents/{id}`：需要 `doc:read`
  - 对话补全：需要 `chat:completion`
- 当 scope 不足、工作空间不在白名单或文档无权限时，后端返回 HTTP `403`，并在 RFC 7807 ProblemDetail 的 `detail` 字段说明具体原因（例如 `当前 API Key 未授予 kb:search 权限范围`）。脚本会优先提取并展示该字段。
- `401` 表示凭证缺失、无效或已过期。
- 本地凭证存储在目标仓库根目录的 `.lexiloom.env`（权限 `600`，加入 `.gitignore`），环境变量 `LEXILOOM_API_KEY` 优先级高于 `.lexiloom.env`。

## 2. 工作空间列表

`GET /api/v1/openapi/workspaces`

用途：初始化（`setup.sh`）时列出当前凭证可访问的工作空间，用户必须选择服务端实际返回的 ID。客户端不得在失败时猜测 ID 或静默绑定默认 ID。

期望响应（兼容顶层数组或 `{ "data": [...] }` 包装格式）：

```json
[
  { "id": 1, "name": "研发空间", "description": "可选描述" }
]
```

## 3. 知识库切片检索

`GET /api/v1/openapi/knowledge/search`（后端同时支持 `POST`）

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---:|---|
| `q` | string | 是 | — | 自然语言查询问题 |
| `workspaceId` | integer | 是 | 项目绑定空间 | 工作空间 ID |
| `topK` | integer | 否 | 5 | 返回条数，脚本限制为 1–20 |
| `minScore` | number | 否 | 后端默认 | 可选相似度阈值 |

期望响应（兼容顶层对象、顶层数组以及 `{ "data": { "results": [...] } }` 包装响应）：

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

`score` 是检索系统的相关度排序指标，不是事实正确率或置信概率。

## 4. 文档详情

`GET /api/v1/openapi/documents/{id}`

用于根据切片结果中的 `documentId` 按需读取单篇文档完整正文与元数据：

| 字段 | 类型 | 含义 |
|---|---|---|
| `id` | integer | 文档 ID |
| `title` | string | 标题 |
| `workspaceId` | integer | 工作空间 ID |
| `categoryName` | string | 分类名称 |
| `status` | string | 文档状态 |
| `version` | integer | 当前版本号 |
| `content` | string | 文档 Markdown 正文 |
| `createTime` | string | 创建时间 |
| `updateTime` | string | 更新时间 |

`scripts/get_document.sh <documentId> [maxChars]` 保留并展示上述元数据字段及正文 `content`（默认超过 30000 字符时友好截断并提示，传 `0` 可输出不截断全文）。

## 5. 错误状态码语义

| HTTP | 客户端处理建议 |
|---|---|
| `200` | 校验 JSON 结构后展示结果 |
| `400` | 参数错误；提示检查 `q` / `topK` / `workspaceId` / `documentId` |
| `401` | 凭证缺失或无效 |
| `403` | 凭证缺少对应 scope 或无权访问目标工作空间/文档 |
| `404` | 资源不存在，或对应端点未部署/路径不匹配 |
| `429` | 触发限流；稍后重试 |
| `5xx` | 服务端异常；提示检查后端服务日志 |
| 网络错误/超时 | 提示检查 `serverUrl`、网络连接与服务健康状态（连接超时 5s，总超时 20–30s） |
