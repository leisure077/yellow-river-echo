# 黄河续响 · Yellow River Echo

HarmonyOS（ArkTS / Stage 模型）端的黄河流域文化导览应用。遗址档案、文创、手绘地图、黄河沙盘、
3D 文物工坊、彩陶工坊这些内容**全部随包离线在设备本地**，不联网也能完整演示；
只有「河小导」问答这一处走 AI 后端（自建 Dify）。

这份 README 回答两件事：**这台机器之外的怎么把它跑起来**，以及**提交的源码包怎么自查**。
AI 后端的部署细节单独放在 [dify/README.md](dify/README.md)，演示流程放在 [docs/演示SOP.md](docs/演示SOP.md)。

---

## 1. 工具链（本包开发实测版本，不是建议版本）

| 项 | 本机实测值 | 怎么核对 |
|---|---|---|
| DevEco Studio | 26.0.0.851（build 261.23567.138.36.2600851） | `product-info.json` |
| SDK | HarmonyOS 26.0.0（apiVersion 26，26.0.0.105，Release） | `sdk/default/sdk-pkg.json` |
| `compatibleSdkVersion` / `targetSdkVersion` | `6.0.2(22)` / `26.0.0` | `build-profile.json5` |
| `modelVersion` | 26.0.0 | `oh-package.json5`、`hvigor/hvigor-config.json5` |
| Node（DevEco 内置） | v24.14.1 | `tools/node/node.exe -v` |
| 演示设备 | HarmonyOS 模拟器 Mate 90 Pro，1280×2832，`127.0.0.1:5555` | `hdc list targets` |

## 2. 构建

命令行构建（不打开 IDE 也能出包，实测 3.4–5.6 秒）：

```bash
# 在项目根目录。DEVECO_SDK_HOME 指向你本机 DevEco Studio 的 sdk 目录
DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk" \
"C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
"C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
--mode module -p product=default -p buildMode=debug assembleHap
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名 debug 包）。
装包与启动：

```bash
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell aa start -a EntryAbility -b com.example.demo01
```

仓库里的 `build-profile.json5` 故意把 `signingConfigs` 留成空数组：签名证书是**按机器**的东西，
写进包里别人机器上没有这些文件，第一步构建就失败。需要签名包时，在 DevEco 里
`File → Project Structure → Signing Configs` 勾上「Automatically generate...」，让 IDE 把
你自己机器上的证书路径与口令写进**本地那份**配置——这几个字段请**不要**再提交回去（导出脚本会拦，见 §5）。

## 3. 目录

```
entry/         ArkTS 应用（页面/组件/服务/资源）
  src/main/ets/pages/       首页、导览、沙盘、工坊、河小导等页面
  src/main/ets/service/     AiService（SSE 流式问答）、AiStore（本地偏好）等
  src/main/resources/rawfile/  离线数据：3D 模型、地图瓦片、沙盘底图、课程影像
server/        手机号短信/号码认证联调用的小型 Node 服务，演示主线不依赖
dify/          AI 后端的复现说明、.env 模板、应用配置快照
tools/         资产烘焙脚本 + hdc/uitest 自验脚本 + 提交包导出脚本
docs/          演示 SOP
```

## 4. 河小导（Dify AI）在别人电脑上怎么调试

链路三段：`App(http SSE) → Dify 1.13.2(Docker Compose, 宿主 :80) → 模型`，
其中知识库向量化用**本机 Ollama 的 bge-m3**，生成回答用**智谱云端 glm-4.5-flash**。
版本清单、起服务步骤、知识库建库参数、取 App Key 的 SQL，都在 [dify/README.md](dify/README.md)。

换一台机器时最容易卡住的不是代码，是**地址**。App 设置页里的地址按设备在哪填：

| 场景 | 地址 | 说明 |
|---|---|---|
| 模拟器 | `http://10.0.2.2/v1` | 模拟器里的 `127.0.0.1` 是模拟器自己，填它必连不上 |
| 真机走 WiFi | `http://<宿主局域网IP>/v1` | 宿主 Windows 若在网络配置文件为「公用」的网络下，默认拦所有入站，要先放行 80 |
| 真机走 USB | `http://127.0.0.1:8080/v1` | 配 `hdc -t <设备> rport tcp:8080 tcp:80`，绕开 WiFi 与防火墙，最稳 |

App 侧自带排错，不接电脑也能自证：

- 设置页「**测一下**」——拿当前输入的地址和 Key 打一次 Dify 的 `/v1/parameters`，
  只回一句「通了 / 连不上 / 地址不对 / 钥匙开不了门」和耗时，不消耗模型额度，也不打印 Key。
  地址框为空或填了 `127.0.0.1` 时，框下面直接给出该填哪种地址的提示。
- 设置页「**最近一次失败**」——上一次问答失败时的「状态码 · 耗时 · 一句原因」留在原地给排错的人看，
  下一次成功自动清掉。里面不含 Key、不含问题、不含回答。
- **命令行侧**：所有 AI 请求的成功与失败都打在 hilog 的 `HH_AI` tag 上（首字耗时、总耗时、字数、状态码）：
  ```bash
  hdc shell hilog | grep HH_AI
  ```
  会话号失效（换 Dify 工作区、清了库）也不用手动处理：收到 404 时 App 会自动清掉本地会话号重发一次。

`tools/` 下那批脚本的本机差异收在 [tools/hh_env.py](tools/hh_env.py)，换机器只需给环境变量，
缺什么它「说什么」而不是崩：

```bash
python tools/hh_env.py          # 自检：hdc 在哪、连哪台设备、Dify 地址、Key 只报长度和前缀
set HH_HDC=D:/DevEco/sdk/default/openharmony/toolchains/hdc.exe
set HH_DEVICE=<你的设备号>
set HH_DIFY_BASE=http://127.0.0.1/v1
set HH_APP_KEY=app-...          # 或者写到 .tmp/app_key.txt（已被 .gitignore 挡着）
python tools/set_dify_cfg.py "http://10.0.2.2/v1"   # 一键写进 App 设置页并自校验
```

**不想在这台机器上起 Dify 也能演示 AI 链路**：`python tools/stall_mock.py 8899 5`
起一个最小假 Dify，App 地址填 `http://10.0.2.2:8899/v1` 即可（Key 随便填非空串）。
`tools/stale_conv_mock.py` 同理，专门用来验会话号自愈。

## 5. 提交源码包：导出与自查

```bash
python tools/export_package.py            # 从 HEAD 导出并跑五项断言
python tools/export_package.py --ref <sha|tag>
python tools/export_package.py --check .tmp/pkg/yellow-river-echo-src-xxxxxxx.zip
```

用 `git archive` 而不是复制目录，是为了让工作树里的 `build/`、`oh_modules/`、`.hvigor/`、
`shots/`、`.tmp/`（本机 Key、hilog、截图）**天然进不去**；代价是未提交的改动也不会进包，
所以脚本会先把 HEAD 和工作树状态打出来让你确认。五项断言对应赛题那句
「清理编译生成文件、缓存文件，保证组委会可复现项目编译运行」：

1. 产物与缓存——`build/`、`oh_modules/`、`.hvigor`、`__pycache__/`、`*.hap`、`*.log`、`shots/`、`.tmp/`、`local.properties` 一律不许出现；
2. 凭据与本机痕迹——Dify App Key、`sk-` 开头的 Key、阿里云 AK、私钥、签名口令字段、
   本机证书目录、写死到别人机器上就断了的盘符 + 用户目录绝对路径，逐个文件扫；
3. 签名配置——`build-profile.json5` 的 `signingConfigs` 必须是 `[]`；
4. 复现必需文件——工程配置、`AppScope/app.json5`、`entry/src/main/module.json5`、README、dify/README 少一个就判不过；
5. 体积——只报数和最大的几项，不判分。

本次自查结果（提交点 `HEAD`，脚本原样输出）：**699 个文件，zip 64.4 MB / 解压后 76.0 MB**，
五项断言全过；并且把导出的 zip 解压到干净目录、按 §2 的命令重新构建，确认能出 hap（见 §6）。

## 6. 已知限制（提前说明，别在决赛现场解释）

| 事项 | 状态 |
|---|---|
| 模拟器上 3D 文物页 | 该模拟器镜像的 ArkWeb 关闭了 GPU/vulkan，跑不了 WebGL，因此走**离线转台帧**降级；真机渲染尚未在物理设备上验证 |
| 河小导首字延迟 | Ollama 设 `OLLAMA_KEEP_ALIVE=-1`（模型常驻）后冷态首字实测 13.0s（不设是 34.5s），检索命中缓存后 1.1s |
| 生成模型在云端 | 换成 Ollama 的 `qwen2.5:1.5b` 就能完全离线复现，代价是回答质量明显下降，需自己权衡 |
| 真机走 WiFi 连宿主 Dify | 本机 WLAN 的网络配置文件是 Public，Windows 默认拒绝入站；放行需要管理员权限，校园网若开 AP 隔离仍不通。推荐用 §4 的 USB 转发 |
| 签名 | 仓库配置为空签名，出的是 unsigned debug hap；真机安装需自备对应签名 profile |

演示当天的操作动线与话术见 [docs/演示SOP.md](docs/演示SOP.md)。
