# macOS 官网发行与更新

## 2026-11-13 Glance 1.0.3 / build 9 已发布

在 1.0.2 基础上修复 Widget Market 语言：App 为中文时，主名称为中文、只带 `en` 翻译的 Widget 直接显示中文，不再落到英文；日／德语缺翻译时仍用英文。用户明确要求后执行 Developer ID Release 构建与 `package-release.sh`：App 公证 `850ffb3a-95d6-4c4c-89d6-d0ea2f43f368` Accepted，DMG 公证 `0f149e58-1c8d-409a-bde5-4c9f81964f1b` Accepted，`stapler validate` 与 `spctl` 通过。DMG `clients/macos/dist/updates/Glance-1.0.3.dmg`，7,784,572 bytes，SHA-256 `d3edccd2746e8a07df7174f5b4da579e55b7a53ba7c1ee7e12b84d73ffd888aa`。按 1.0.2 的做法，appcast 已用 Sparkle 私钥重新生成为只含 1.0.3 一个完整 DMG enclosure（无 delta），签名校验通过；本地生成的 `Glance9-*.delta` 不发布。官网从当前源码刷新公开快照并重建，25 页构建、14 项检查、脚本语法及 `git diff --check` 通过，Pages 部署为 `acc113ec.glance-6t3.pages.dev`。正式域名中／英／日／德首页和中英安装页均显示 1.0.3；两个 1.0.3 DMG URL 实际下载均为 HTTP 200、7,784,572 bytes，SHA-256 与本地一致；线上 appcast 签名验证通过，仅含 1.0.3/build 9 完整包，enclosure 可访问且长度匹配。旧版 DMG 两个目录共 10 个 URL 与全部 12 个本地 delta 对应公开 URL 均返回 404。仅替换官网公开产物，本地 `clients/macos/dist` 历史归档及无关工作区改动保留；未启动 App 或做 UI 验收。

## 2026-11-11 Glance 1.0.2 / build 8 已发布

包含本轮反馈／诊断导出、客户端元数据与首次成功预览埋点、首帧检查等 Swift 改动及德／日语言资源。Developer ID Release 构建后运行 `package-release.sh`：App 公证 `a0b0e400-0c47-45ea-83dd-2525cf756647` Accepted，DMG 公证 `51c3d8a1-ce2f-4c62-b8fb-8ed2e9f14048` Accepted，`stapler validate` 与 `spctl` 均通过。DMG `clients/macos/dist/updates/Glance-1.0.2.dmg`，SHA-256 `123164c3321a9580c9dd354fe8c03ab237c4b28d52f41f2660e7c47d0900f289`。初次发布的 appcast 含历史条目与 delta；随后按用户明确批准将公开产物收缩为仅最新完整包，并用 Sparkle 私钥重新生成、验证签名 feed。最终 appcast 只含 1.0.2/build 8 的一个完整 DMG enclosure，不含 delta 或失效引用，旧客户端可通过该条目获取最新完整包。官网从当前源码刷新公开快照并重建，25 页构建与 14 项检查通过，最终 Pages 部署为 `e6be2d77.glance-6t3.pages.dev`。正式域名中／英／日／德首页和中英安装页均显示 1.0.2；两个 1.0.2 DMG URL 均为 HTTP 200、7,783,267 bytes 且 SHA-256 与本地一致；旧 1.0.1、1.0.0、beta.1、beta.2 的公开 DMG 及全部旧 delta URL 共 18 个均返回 404。仅删除官网 `src/download`、`src/updates` 及生成目录中的旧公开产物，本地 `clients/macos/dist` 历史归档保留。干净环境安装与旧版实际更新验收仍由用户完成。

## 2026-11-10 官网再次被旧 beta.1 覆盖后恢复 1.0.1

正式域名一度再次返回 1.0.0-beta.1 内容和空的签名 appcast。已刷新公开快照、重建官网（25 页、14 项静态检查、7 项采集测试、脚本语法检查通过），DMG 重新通过 `stapler validate` 与 `spctl` 后重新发布 Pages：`125bbf76.glance-6t3.pages.dev`。发布后正式域名核对：首页只显示 1.0.1；appcast 首项为 1.0.1/build 7 并保留 1.0.0、beta.2 归档；`/download/` 与 `/updates/` 的 DMG HTTP 200、长度 7586421、SHA-256 `6642a52208f7635d07a0475000bdb6e00a5f8cbee428946bd9430740dae2cf81` 与本地公证包一致；三个 7 系 delta HTTP 200。这是 11 月 9 日同类问题的第二次发生，发布来源仍未锁定。

## 2026-11-10 P0 源码与发行交接

本轮反馈／诊断、客户端元数据和首次成功预览埋点尚未进入新的发行包；公开版本仍是下面记录的 1.0.1 / build 7。本轮未部署迁移 0028、Worker 或官网，也未创建发行提交／tag。最终服务端回归及编译检查有超时阻塞，验收状态见 [上线清单](launch-readiness.md) 和 [统计说明](launch-analytics.md)。后续发行必须递增版本与 build，保留 1.0.1 归档和现有更新签名。

已做范围有限的文件检查：扫描 831 个仓库／公开产物文本文件的私钥头和 token 字面量模式；唯一命中为 `src/billing.ts` 中去除 PEM 包装的正则，不是密钥内容。当前 `website/static/public` 和本地 `Glance.app` 未发现 `.p12`、`.p8`、`.key`、`.env`、`.dev.vars`、Sparkle 私钥或 `account_info.txt` 这类文件名。这不代替 Git 全历史和新发行包的最终敏感信息审计。

## 2026-11-09 官网恢复与 1.0.1 发布

- 正式域名被后续生产部署覆盖为旧 beta.1 内容，正式包链接返回 404，更新源为空；先重新发布当前站点恢复 1.0.0，再发布 1.0.1（build 7）。未回滚官网其他页面。
- 完整 Release 构建、Developer ID 签名通过；App 公证 `42e4df89-d927-44e9-b3d9-b429890dc52e`、DMG 公证 `2718fdca-ce8c-4183-bcd2-601433c49f20` 均 Accepted，凭证附加、验证和 Gatekeeper 检查通过。
- 新版包含主动 Pro 入口、中英日德语言资源、已购主页隐藏 Pro 管理入口，以及任务等待执行器提示。未启动 App 或进行 UI 验收。
- 官网部署 `69c12c89.glance-6t3.pages.dev`；四语言首页、安装页和 appcast 均已核对指向 1.0.1/build 7。公开下载与更新源中的 DMG 均与本地文件一致：`6642a52208f7635d07a0475000bdb6e00a5f8cbee428946bd9430740dae2cf81`。
- 官网构建新增校验：正式版本必须在 appcast 中存在，所有引用安装包和差分包必须存在且大小匹配。该检查无法阻止其他工作区绕过构建直接发布旧产物；发布者仍需使用当前源码和发行资源。
- 服务端队列诊断已部署，版本 `d6fa9848-5db4-45c8-a808-d1eaca2fca79`。164 项服务测试、类型检查、13 项官网测试和翻译检查通过。真实付款退款与客户端安装/更新仍待用户验收。

## 2026-11-05 正式版发布

- 用户授权发布官网并开放正式购买。版本 1.0.0（build 6），功能日期 2026-11-05，arm64 / macOS 12.3+。
- 完整 Release 构建及 Developer ID 签名通过，包含 Resize、权限页 Logo、任务余额充足直接提交和 Information 圆角兼容性修复。
- App 公证 `8a11d701-a0dc-4086-acec-8a920827335d`、DMG 公证 `409797fa-eb8d-464c-b606-18295d877a1b` 均 Accepted，凭证附加与验证通过；Gatekeeper 均 accepted / Notarized Developer ID。
- 正式包：`clients/macos/dist/updates/Glance-1.0.0.dmg`；官网 `/download/Glance-1.0.0.dmg`、`/updates/Glance-1.0.0.dmg` 已发布且字节一致。SHA-256：`1cb9bf4a277a87fc68da0ec8f4b3b5204a81eb91a667dcd3a922580f8c99bd3a`。
- Sparkle 签名更新源及 build 4/5 到 6 的 delta 已发布，旧 beta 归档保留。实际旧版更新安装与最新 UI 验收仍由用户完成。

客户端默认由用户自行构建、运行和验收；本次 Release 构建与公证由用户明确授权执行，UI 验收仍由用户完成。

## 2026-11-04 验收版公证记录

- 用户明确要求再次构建 Release，版本递增为 `1.0.0-beta.2`（build `5`），保留 beta.1 安装包。
- App：`clients/macos/Glance.app`；DMG：`clients/macos/dist/updates/Glance-1.0.0-beta.2.dmg`（约 7.1 MB）。本次为 arm64 / Apple Silicon，最低 macOS 12.3，未生成 Intel 版本。
- 包含可跳过的权限引导、输入监控显式 IOHID 请求、辅助功能覆盖 Peek 的判断，以及图片／视频／Peek 窗口最小尺寸修复。中英文权限文案已核对进入包内。
- Developer ID 签名、Hardened Runtime 和严格签名校验通过；App 公证 `bdeb6855-c6db-469b-8be5-854e48fad8af`、DMG 公证 `f1a78e28-b05b-43e9-b5aa-521b0d099538` 均为 `Accepted`，公证凭证已附加并验证。
- Gatekeeper 对 App 和 DMG 均返回 `accepted / Notarized Developer ID`；DMG SHA-256 与 Sparkle feed 签名校验通过，appcast 包含 build 5 条目。
- 构建日志：`/private/tmp/glance-release-build-20261104.log`；打包日志：`/private/tmp/glance-notarize-package-20261104.log`。现有弃用 API／Swift 6 并发迁移警告未阻止 Swift 5 模式构建。
- 未启动 App 或代替用户做 UI 验收。安装包及更新 feed 仅生成在本地，等待用户验收后发布官网。

## 2026-11-02 公证记录

- `1.0.0-beta.1`（build `4`，arm64）Release 构建成功，产物为 `clients/macos/Glance.app`。
- 使用 `Developer ID Application: yongjian chen (4C8WK3Z8YZ)` 签名，包含安全时间戳；主 App 与 Sparkle 内嵌组件严格签名校验通过，主 App 不含调试或禁用库校验 entitlement。
- 公证凭据已保存于本机 Keychain profile `glance-notary`，文档与脚本不保存密码。
- App 公证提交编号：`2ac38f41-6a99-4764-a913-d4a8e70ec3d6`；Apple 已返回 `Accepted`，公证凭证已附加并验证通过。
- 打包日志：`/private/tmp/glance-notarize-package-20261102.log`。DMG 已生成：`clients/macos/dist/updates/Glance-1.0.0-beta.1.dmg`（约 7.1 MB）；DMG 公证编号 `8ffb9047-26d2-4063-a2e4-c30a71f72f05`，状态 `Accepted`，凭证验证通过。Sparkle appcast 签名与 SHA-256 校验通过；`spctl` 对 App 返回 `accepted / Notarized Developer ID`。
- 修正打包脚本的签名检查：使用 `codesign -dvv` 获取 Authority，避免 `-dv` 缺少该字段而错误拒绝有效的 Developer ID 包。
- 首次等待连接出现 `NSURLErrorDomain -1001` 超时，重新查询确认同一提交仍为 `In Progress`。已使用 `GLANCE_APP_NOTARY_SUBMISSION=2ac38f41-6a99-4764-a913-d4a8e70ec3d6` 恢复原任务并完成公证，未重复上传 App。脚本改为每分钟查询状态，暂时网络失败最多连续重试 10 次，仅在 `Accepted` 后继续；通过、排队后通过、网络恢复、拒绝、连续失败停止五项模拟检查通过。
- 未发布官网、更新源或开启正式支付；仍需用户进行安装与功能验收。

## 先做本地验收

2026-11-03 源码已修复权限引导无法关闭、继续按钮强制授权及系统设置缺少 App 时无添加指引的问题；包含中英文文案、跳过记忆和手动添加帮助。同日进一步修正输入监控的显式 HID 请求、辅助功能授权覆盖 Peek 的判断（包括菜单状态），并为图片／视频窗口增加最小可操作尺寸。权限依据见 [Apple DTS 说明](https://developer.apple.com/forums/thread/828052)。这些修复已包含在 2026-11-04 的 beta.2 公证包中，UI 验收由用户完成；2026-11-02 的 beta.1 安装包不包含这些修复。后续打包仍需递增版本／build，避免覆盖已归档安装包。

在仓库根目录执行 `./run.sh Debug`。`./run.sh` 和构建脚本省略参数时也默认 Debug，生成本地测试包，不上传安装包或打开正式收款。先确认启动正常，再按 [上线验收清单](launch-readiness.md) 测试功能与沙盒付款；验收通过后才准备正式 Release。正式构建必须显式传入 `Release`。

## 已准备

- Sparkle 2.10.1 固定版本依赖；Glance 菜单与状态栏菜单可检查更新。
- 更新源：`https://glancepreview.com/updates/appcast.xml`；要求签名 feed 和签名更新包。
- 更新私钥存于本地 `infomation/sparkle-update-key.txt`，权限 0600，Git 忽略。必须离线备份，不能丢失或公开。公钥写入客户端 Info.plist。
- `Glance.Debug.entitlements` 与 Release 分开；Developer ID Release 不带调试及禁用库校验的授权。本地 `Glance Self-Signed` Release 没有 Apple Team ID，构建脚本通过临时 entitlement 允许加载自签名 Sparkle；该本地包不能用于正式公证发布。
- 当前更新 feed 不包含发行条目，避免把内测包误当成正式更新。

## Apple 审核通过之后

1. 安装 **Developer ID Application** 证书，并配置 `notarytool` Keychain profile。
2. 用户使用自己的 Developer ID 身份构建 Release；验证实际包的权限、登录、计费与功能。
3. 设置 `GLANCE_SIGN_IDENTITY`、`GLANCE_NOTARY_PROFILE`、`SPARKLE_BIN` 后运行：

   ```sh
   clients/macos/scripts/package-release.sh /absolute/path/to/Glance.app
   ```

   脚本不构建或启动 App。它会检查签名与 entitlement，依次公证 App、生成并公证 DMG、签名 appcast 和生成 SHA-256。
4. 发布 `clients/macos/dist/updates/` 中的 DMG 与校验文件，然后发布 appcast；更新官网下载入口及版本说明。不得只发布 feed 而漏传 DMG。
5. 在已接入 Sparkle 的旧版本检查更新、安装新版本并确认授权仍有效，由用户完成此 UI 验收。更早的、未接入 Sparkle 的内测版需手动下载首个正式版本。

## 禁止混淆

Developer ID、公证和 Sparkle 签名分别解决开发者身份、Apple 检查和更新完整性。未经过实际证书签名和公证的本地构建不应称为正式已认证发行包。已有内测下载维持内测身份。

手动签名遵循 [Sparkle 官方签名说明](https://sparkle-project.org/documentation/sandboxing/#code-signing)：逐层签名内部组件，保留辅助程序 entitlement，主 App 不使用 `--deep` 签名。Developer ID 使用安全时间戳；本地自签名／ad-hoc 调试不请求时间戳。发布脚本已完成实际 Developer ID 包与 DMG 公证；更新安装仍待用户验收。
