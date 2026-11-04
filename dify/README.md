# 河小导 AI 后端（Dify）复现说明

这份文档回答一个问题：**换一台电脑，怎么把 App 里那个「问一句、带引用地答」的河小导重新跑起来。**

## 1. 这条链路一共三段

```
App(ArkTS, http SSE)  →  Dify 1.13.2(Docker Compose, 宿主 :80)  →  模型
                                                              ├─ 知识库向量化：本机 Ollama bge-m3
                                                              └─ 生成回答：智谱云端 glm-4.5-flash
```

第三段是混合的，这一点最容易踩坑：**知识库用的是本机 Ollama，但生成回答用的是智谱的云服务**。
所以新机器上只有 Docker + Ollama 还不够，必须另外有一把可用的智谱 API Key，否则应用建得起来、
库也索引好了，问一句还是答不出来。想彻底离线复现，就把应用的模型换成 Ollama 的
`qwen2.5:1.5b`（本机其余 4 个测试应用用的就是它），代价是回答质量明显下降，需要自己权衡。

## 2. 版本清单（都是本机实测值，不是猜的）

| 组件 | 镜像 / 版本 | 本机实测体积 |
|---|---|---|
| Dify api / worker / worker_beat | `langgenius/dify-api:1.13.2` | 3.99 GB |
| Dify web | `langgenius/dify-web:1.13.2` | 476 MB |
| 插件守护 | `langgenius/dify-plugin-daemon:0.5.4-local` | 2.2 GB |
| 代码沙箱 | `langgenius/dify-sandbox:0.2.12` | 825 MB |
| 向量库 | `semitechnologies/weaviate:1.27.0` | 234 MB |
| 数据库 | `postgres:15-alpine` | 392 MB |
| 队列 | `redis:6-alpine` | 45.1 MB |
| 网关 | `nginx:latest`（宿主 80 / 443） | 240 MB |
| SSRF 代理 | `ubuntu/squid:latest` | — |
| 向量化模型 | Ollama 0.33.3 + `bge-m3:latest` | 1.2 GB（常驻占 664 MB 显存） |
| 生成模型 | 智谱 `glm-4.5-flash`（`thinking:false`） | 云端，不占本机 |

全套镜像约 **8.4 GB**。Docker Hub 直连在本机网络下超时，实测可用镜像站前缀
`docker.m.daocloud.io/library/...`（elastic.co 那边可直连）。

## 3. 起 Dify

1. 取 Dify 官方部署包，版本对齐 `1.13.2`（`github.com/langgenius/dify`，`releases/1.13.2` 分支或 tag）。
2. `cp .env.example .env`，把密钥类字段填上；本目录的 [.env.example](.env.example) 只列本项目实际依赖的项，
   其余保持官方默认。
3. `docker compose up -d`，浏览器开 `http://127.0.0.1` 初始化管理员。
4. 只暴露 80/443 是默认行为，数据库、redis、weaviate 都不对外发布端口（本机实测端口映射只有 nginx 与插件调试 5003）。

## 4. 配模型与知识库

- **Ollama（向量化用）**：`ollama pull bge-m3`；在 Dify「模型供应商 → Ollama」里 Base URL 填
  `http://host.docker.internal:11434`（容器要访问宿主机，Windows 的 Docker Desktop 提供这个域名）。
  建议给 Ollama 进程设 `OLLAMA_KEEP_ALIVE=-1`，理由见第 7 节。
- **智谱（生成用）**：供应商 `langgenius/zhipuai/zhipuai`，模型 `glm-4.5-flash`，需要 API Key（不入库）。
- **知识库**：语料就是仓库里的 `tools/kb/docs/` 23 个 md 文件（由 `tools/kb/gen_kb_docs.py` 从 App 的
  rawfile 数据生成，可重跑）。建库参数照抄 [app-config.snapshot.yaml](app-config.snapshot.yaml) 末尾的
  `knowledge_base` 段：分段分隔符 `\n\n`、`max_tokens 500`、`chunk_overlap 50`、去掉多余空格、
  索引方式 high_quality、embedding `bge-m3:latest`、检索 semantic_search + 阈值 0.35 + top_k 4。
  本机结果是 **23 篇文档 / 369 个分段**。
- **应用**：提示词、开场白、推荐问题、检索权重全在 [app-config.snapshot.yaml](app-config.snapshot.yaml)
  里（从本机 dify 库只读导出）。正式迁移请在 Dify 控制台「导出 DSL」得到 yaml 后导入，
  快照文件用于核对，不是 DSL 格式。

## 5. 拿服务密钥并填进 App

App 设置页要两样东西：Dify 地址和 `app-` 开头的服务密钥（控制台「访问 API」→ API Key，本机是 28 字符）。

本机取法（按应用名取，比 `limit 1` 稳）：

```bash
docker exec docker-db_postgres-1 psql -U postgres -d dify -t -A -c \
  "select t.token from api_tokens t join apps a on a.id = t.app_id where a.name = '河小导'"
```

**这把 Key 不入库**，任何提交材料里都不该出现它的值。

地址怎么填取决于设备在哪：

| 场景 | 地址 | 说明 |
|---|---|---|
| 模拟器 | `http://10.0.2.2/v1` | 模拟器里 `127.0.0.1` 是模拟器自己，填它必连不上 |
| 真机走 WiFi | `http://<宿主局域网IP>/v1` | 本机是 `10.104.181.84`；**公用网络下 Windows 默认拦入站，见第 6 节** |
| 真机走 USB | `http://127.0.0.1:8080/v1` | 配合 `hdc rport`，绕开 WiFi 与防火墙，见第 6 节 |

本机有一键写入并自校验的脚本：`python tools/set_dify_cfg.py "http://10.0.2.2/v1"`
（Key 省略时它自己去 dify 库取，只报长度和前缀，不打印值）。

## 6. 别人电脑连你的机器：三种接法与实测状态

- **模拟器**：`http://10.0.2.2/v1`，已实测通（首字 9.1s，带两条引用条）。
- **真机走 WiFi**：nginx 确实监听 `0.0.0.0:80`，但本机 WLAN 的网络配置文件是 **Public**
  （`HTU_Student 2`），Windows 在公用网络下默认拒绝所有入站，且查不到任何 TCP 80 的放行规则。
  所以这条路要先用管理员权限放行，再实测；校园网若开了 AP 隔离，放行也照样不通。
- **真机走 USB（推荐）**：`hdc -t <设备> rport tcp:8080 tcp:80` 把设备的 8080 反向转到宿主机 80，
  App 里填 `http://127.0.0.1:8080/v1`。本机实测 `rport` 能登记（`fport ls` 显示 `[Reverse]`），
  删除要用 `fport rm tcp:8080 tcp:80`（两个参数都要给）。这条路不依赖网络环境。

## 7. 已知故障与实测延迟

| 现象 | 原因 | 处理 |
|---|---|---|
| 所有 Dify 路由超时、`docker-api-1` 在跑但 CPU 0%、容器内大量 CLOSE_WAIT | 1.13.2 的 gunicorn+gevent worker 会僵死 | `docker restart docker-api-1`（只 restart，不要 rm 容器/卷，数据都在卷里） |
| 冷态首字 34.5s | Ollama 默认 5 分钟卸载模型，重新装回显存要 8.9s，叠加检索与生成 | 给 Ollama 设 `OLLAMA_KEEP_ALIVE=-1`，实测降到 **13.0s**，`ollama ps` 的 UNTIL 变 Forever |
| 常驻后仍偶发慢 | 首轮检索无缓存 | 实测同一句第二轮首字 1.1s |
| App 报「档案翻得有点久」 | 看门狗 60s 内没收到新字节 | 属预期：静默 70s 实测触发该文案；静默 30s 实测能正常答完 |

App 侧的超时链条（改任何一环都要重测）：`connectTimeout 8s` → `readTimeout 90s` → 看门狗 60s 无新字节。

排错工具：`tools/dify_latency.py`（首字延迟/分片手感）、`tools/stall_mock.py` + `tools/stall_ui_check.py`
（把「静默多少秒」变成可控量，双向验看门狗）、`tools/regress_dify.py`。
