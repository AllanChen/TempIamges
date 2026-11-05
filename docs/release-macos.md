# macOS 官网发行与更新

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
