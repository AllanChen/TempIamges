# macOS 客户端

- [Glance](Glance/README.md)：生产源码、资源、Xcode 工程；内部相对结构保持不变。
- [scripts](scripts/)：签名、打包、图标与非 UI 检查工具。
- [prototypes](prototypes/)：历史系统能力实验，部分脚本会操作 UI，不属于默认测试流程。
- [legacy](legacy/)：早期 ImageHoverPreview 工程残留。
- [App 页面与 Figma 设计](../../design/app/README.md) · [服务端](../../server/README.md)

用户从仓库根目录运行 `./run.sh`（构建并启动）或 `./run`（仅启动已有产物）。规范脚本在本目录，根目录脚本只转发参数，不改变调用者工作目录。

App 产物位于 `clients/macos/Glance.app`，DMG 位于 `clients/macos/dist/`；均不提交 Git。代理不运行构建或 UI 验证。安装说明见 [docs/installation.md](../../docs/installation.md)。
