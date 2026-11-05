# 仓库目录整理记录

日期：2026-10-27。范围：按客户端、服务端、官网、文档和设计归类，保持业务行为不变。

## 当前入口

- [系统规范](../spec.md)：目录树、模块连接、路径与部署契约。
- [代理规则](../AGENTS.md) 和 [agent.md 兼容入口](../agent.md)。
- [项目结构](project-structure.md)：完整导航和原有 macOS 模块说明。
- [计费 V1](glance-billing-v1.md)：已记录五币种价格、五个 USD 购买链接及商品 ID；价格和支付配置未随整理上线。

## 迁移映射

下表旧路径只用于迁移追溯，不是当前命令或发布入口。所有路径均相对仓库根目录。

| 原路径 | 新路径 |
|---|---|
| `Glance` | `clients/macos/Glance` |
| `Glance.app` | `clients/macos/Glance.app` |
| `ImageHoverPreview` | `clients/macos/legacy/ImageHoverPreview` |
| `prototype` | `clients/macos/prototypes` |
| `GlanceService` | `server/GlanceService` |
| `glance-cli` | `server/glance-cli` |
| `widgets` | `server/widgets` |
| `website` | `website/app` |
| `website-static` | `website/static` |
| `seo` | `website/seo` |
| `design/image-compression-ui-spec.md` | `design/app/specs/image-compression-ui-spec.md` |
| `design/widget-submission-checklist.md` | `design/app/specs/widget-submission-checklist.md` |
| `docs/designs` | `design/app/specs/plans` |
| `layout/brand-assets` | `design/marketing/brand-assets` |
| `layout` | `design/app/layout` |
| `outputs` | `design/marketing/videos` |
| `logo.png` | `design/marketing/brand-assets/logo.png` |
| `logo.svg` | `design/marketing/brand-assets/logo.svg` |
| `glance-image-viewer-alpine.png` | `design/marketing/brand-assets/glance-image-viewer-alpine.png` |
| `index.html` | `design/website/legacy/index.html` |
| `taste-skill-index.html` | `design/website/legacy/taste-skill-index.html` |
| `dist/index.html` | `design/website/legacy/dist/index.html` |
| `dist` | `clients/macos/dist` |
| `memory` | `docs/history` |
| `PRD-ImageViewer.md` | `docs/product/PRD-ImageViewer.md` |
| `SEARCH_RULES.md` | `docs/architecture/SEARCH_RULES.md` |
| `INSTALL.md` | `docs/installation.md` |
| `PROJECT_STRUCTURE.md` | `docs/project-structure.md` |
| `information.txt` | `docs/archive/information.txt` |
| `:memory:.ses` | `docs/archive/local-state/:memory:.ses` |
| `scripts/refresh-brand-media.py` | `design/marketing/scripts/refresh-brand-media.py` |
| `scripts` | `clients/macos/scripts` |
| `run.sh` | `clients/macos/run.sh` |
| `run` | `clients/macos/run` |
| `glance-cli-run.sh` | `server/glance-cli-run.sh` |
| `desktop-1440-screenshot.png` | `design/website/screenshots/desktop-1440-screenshot.png` |
| `desktop-screenshot.png` | `design/website/screenshots/desktop-screenshot.png` |
| `i18n-en-desktop.png` | `design/website/screenshots/i18n-en-desktop.png` |
| `i18n-zh-desktop.png` | `design/website/screenshots/i18n-zh-desktop.png` |
| `mobile-screenshot.png` | `design/website/screenshots/mobile-screenshot.png` |

`run.sh`、`run`、`glance-cli-run.sh` 的实现已归入所属模块；根目录同名脚本保留为兼容转发入口。执行权限与参数转发保留。

`.git`、`.github`、`.agents`、`.claude`、`.baoyu-skills`、`.gstack`、`.playwright-mcp`、`.sisyphus` 等工具目录保留在原处。历史工具日志可能提到旧路径，作为历史证据保留，不作为当前执行步骤。`.venv` 保留在仓库根目录，避免破坏主虚拟环境的绝对解释器路径。

## 已修正的关联

- macOS：完整移动 Xcode 项目及源码资源，内部路径不变；现有构建脚本输出到 `clients/macos/Glance.app` 和 `clients/macos/dist/`。根目录启动入口转发至新目录。
- 平台工具：签名脚本提示、DMG 打包位置、图标输出位置及非 UI 检查的源码位置已同步。
- 服务端：Worker、管理后台、数据库迁移和测试保持模块内相对布局；未部署或执行线上数据库迁移。
- CLI：发布 workflow 的工作目录、构建产物目录、包源码链接及本地安装脚本使用新路径；包名和 tag 规则不变。
- 本地技能：`.agents/skills/glance-widget-publish/SKILL.md` 已改用 `server/widgets/`、`server/glance-cli/` 与 `server/GlanceService/`。
- 宣传资料：视频生成脚本按新层级寻找仓库根目录，并连接品牌素材和 Figma 导出；未重新渲染视频或生成截图。
- 官网：生产源在 `website/static/`，React/Vinext 实现保存在 `website/app/`，旧根目录 HTML 归入设计历史；源文件、构建输出、SEO 相对链接已同步。
- 文档：按原文件位置解析并修正现有本地 Markdown 链接和 HTML 素材引用；根 README、spec、AGENTS 和各类别 README 提供新导航。
- Git：忽略本地 App、DMG、缓存和归档会话状态；显式保留两个 npm 锁文件，避免迁移后被全局忽略规则漏掉。

## 本机执行环境

已经将根目录 `.venv` 内的 `glance-cli` 重新以 editable 方式安装到 `server/glance-cli/`，验证 CLI 导入位置及 `--help` 正常。没有启动真实 Worker 或提交处理任务。

本机 Widget 注册表位于工作区外的 `~/.config/glance/widgets.sqlite`。经权限批准，使用 [路径迁移工具](../server/tools/migrate-local-paths.py) 先备份数据库，再修正 17 个路径字段；不改启用状态、版本、服务端状态或其他注册信息。一个随 Widget 移动的专用 `.venv` 的启动脚本和激活路径也已更新。

备份文件：`~/.config/glance/widgets.sqlite.before-reorganization-20261027T082931841308Z.bak`。

迁移后复查：没有剩余可迁移路径；有一个原有缺失 manifest 的注册记录保留未修复：`7e485144-443d-48ee-a55c-7fc5ed681d28`，版本 `0.1.0`。新目录也没有对应 `widget.json`，本次未删除记录或伪造 manifest。

其他机器可先执行只读预览，再决定是否应用：

```sh
python3 server/tools/migrate-local-paths.py
python3 server/tools/migrate-local-paths.py --apply
```

`--apply` 写入本机配置目录前需要具备对应权限；每次实际更新先生成备份。已有运行进程不会被本次整理自动停止或重启。路径迁移工具已用隔离数据库验证原始数据备份、非路径字段保留及重复运行幂等性。

## 验证结果

- 原始文件清单核对：708 个原有文件全部在新位置保留，图片、音视频和 Xcode project 文件内容未因移动改变。
- 原有未提交的服务端、管理后台、Worker、测试及迁移文件改动保留。CLI README 只随目录调整引用。
- 服务端 TypeScript 类型检查通过；Vitest **8 个文件、103 项测试通过**。
- Python CLI 单元测试通过；本机 editable 安装与命令入口验证通过。
- 静态官网从新目录构建成功，生成 19 页；**7 项测试通过**，含页面链接、媒体和语言关系检查。
- Figma 插件 JavaScript 语法与页面生成检查通过；没有运行 Figma UI。
- Xcode project、Info.plist 通过 `plutil -lint`；Python／Shell 语法、宣传素材路径、140 条本地文档链接及仓库布局检查通过。
- 没有构建或启动 Glance，没有操作桌面 UI，没有发布网站、服务、Widget 或包。

## 后续发布位置

生产官网发布工作目录为 `website/static/`，输出为 `public/`，同目录 `functions/` 必须包含。若 Cloudflare 或其他外部 CI 曾配置根目录 `website-static`，需在下次发布前改为 `website/static`；本次未更改远程部署设置。

服务端从 `server/GlanceService/` 发布。macOS 的 Xcode 工程是 `clients/macos/Glance/Glance.xcodeproj`。Windows 目录只是占位，不表示已有客户端。
