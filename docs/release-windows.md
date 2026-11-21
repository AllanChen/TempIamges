# Windows 客户端发行与官网下载按钮

给接手官网的 agent：如何把 Glance for Windows 的发行包放上线，并在 `glancepreview.com` 加上「下载 Windows 版」按钮。客户端源码与打包见 [`GlanceWin/`](../GlanceWin/)（计划与阶段：`GlanceWin/PLAN.md`）；官网构建规则见 [`website/static/README.md`](../website/static/README.md)。

> 本文只描述做法。执行前确认用户本次明确要求了哪一步：**上传发行包、改官网源码、部署官网是三件事**，未被要求的不要做。不要修改 `server/`、`clients/macos/`。

## 1. 当前发行包

| 项目 | 值 |
|---|---|
| 版本 | Glance for Windows **0.1.0**（与 macOS 版本号独立，macOS 当前为 1.x） |
| 文件 | `Glance-0.1.0-win-x64.zip`（便携版 zip，**不是安装程序**） |
| 本地路径 | `GlanceWin/dist/Glance-0.1.0-win-x64.zip`（`dist/` 被 Git 忽略，不要提交） |
| 大小 | 94,749,478 bytes（官网按 `build.py` 的十进制写法显示 **94.7 MB**） |
| SHA-256 | `35989dff89e81e6d6eb9bfad43fefe968bcb9227b10d9cc2075431aebf00c668` |
| 系统要求 | Windows 10 版本 2004（build 19041）或更新、Windows 11；仅 64 位 x64 |
| 运行时 | 自带 .NET，无需安装；网页 / PDF / Markdown 预览需要 Microsoft Edge WebView2 Runtime（Windows 11 自带） |
| 签名 | **未做代码签名**：首次运行会出现 SmartScreen「Windows 已保护你的电脑」 |
| 更新 | 暂无自动更新与安装程序（`PLAN.md` Phase 7，计划用 Velopack） |

重新打包（会先跑单元测试，失败则不打包）：

```powershell
powershell -ExecutionPolicy Bypass -File GlanceWin\package.ps1 -Version 0.1.1
Get-FileHash GlanceWin\dist\Glance-0.1.1-win-x64.zip -Algorithm SHA256
(Get-Item GlanceWin\dist\Glance-0.1.1-win-x64.zip).Length
```

每次换版本都要用新的文件名、大小和 SHA-256，不能沿用上表数值。

## 2. 发行包放在哪里（关键限制）

macOS 的 DMG 放在 `website/static/src/download/`，随 Cloudflare Pages 一起部署。**Windows zip 不能这样做**：Cloudflare Pages 单个文件上限为 25 MiB，94.7 MB 的 zip 会让部署失败。所以不要把 zip 放进 `src/download/`，也不要提交进 Git。

推荐方案：**Cloudflare R2**（与官网同一 Cloudflare 账户）。

1. 建桶（名称为建议值，需用户确认）：`wrangler r2 bucket create glance-downloads`
2. 在 Cloudflare 控制台 R2 → `glance-downloads` → Settings → Custom Domains 绑定 `downloads.glancepreview.com`（建议值，需用户确认；这一步要用户的账户权限）。
3. 上传，设置下载头：

   ```sh
   wrangler r2 object put glance-downloads/windows/Glance-0.1.0-win-x64.zip \
     --file GlanceWin/dist/Glance-0.1.0-win-x64.zip --remote \
     --content-type application/zip \
     --content-disposition 'attachment; filename="Glance-0.1.0-win-x64.zip"'
   ```

4. 校验线上文件与本地一致（大小和 SHA-256 都要对上）：

   ```sh
   curl -sSfL https://downloads.glancepreview.com/windows/Glance-0.1.0-win-x64.zip -o /tmp/g.zip
   sha256sum /tmp/g.zip   # 必须等于上表 SHA-256
   ```

5. 旧版本文件保留不删，已缓存的页面和别人转发的链接才不会失效。

备选：GitHub Release 附件。仅当仓库 `AllanChen/TempIamges` 是公开仓库时可用；私有仓库的 Release 附件需要登录，访客下载会 404，不能用作官网下载地址。

Cloudflare 凭据只通过环境变量提供，不写进源码。

## 3. 官网源码改动（`website/static/`）

### 3.1 先确认设计

首页文案与结构来自官网 Figma（`src/homepage.json` 里的节点 id，例如 `15:2378` 是 `08 / Download`；设计上下文在 `design/website/GlanceUnslopFigmaPlugin/web-context.json`）。目前**没有** Windows 按钮的设计。动手前先向用户确认按钮位置和样式（例如：与「下载 Mac 版」并排的次级按钮），不要自行发明布局。

### 3.2 发行信息只写一处

新增 `src/windows-release.json`，构建时读取（zip 不在仓库里，所以大小和校验值不能像 DMG 那样现算）：

```json
{
  "version": "0.1.0",
  "url": "https://downloads.glancepreview.com/windows/Glance-0.1.0-win-x64.zip",
  "bytes": 94749478,
  "sha256": "35989dff89e81e6d6eb9bfad43fefe968bcb9227b10d9cc2075431aebf00c668",
  "minimumOs": "Windows 10 2004+ · x64"
}
```

在 `build.py` 中：

- 在 `VERSION` / `DMG`（约第 29–30 行）旁读取该文件，得到 `WIN_VERSION`、`WIN_URL`、`WIN_SIZE`（`f"{bytes / 1_000_000:.1f} MB"`，与 `dmg_facts()` 一致）、`WIN_SHA256`。
- 校验并在失败时 `SystemExit`：`url` 必须是 `https://` 且主机为确认过的下载域名；`sha256` 必须是 64 位十六进制；`bytes` 为正整数；文件名里的版本等于 `version`。
- 在模板替换表（约第 314–321 行，`{{DMG}}` 等所在处）加入 `{{WIN_VERSION}}`、`{{WIN_URL}}`、`{{WIN_SIZE}}`、`{{WIN_SHA256}}`。
- `_redirects`（约第 470 行）加一条稳定入口，按钮和对外分享都用它，换版本只改 JSON：
  `/download/windows {WIN_URL} 302`
- 不要改动 DMG、appcast、公证相关的检查。

### 3.3 首页按钮（`homepage.py` + `src/homepage.json`）

- `homepage.py` 的 `download(rows)`（约第 44–46 行）目前只输出 Mac 按钮。按确认的设计加一个 Windows 按钮，`href="/download/windows"`，并带上 `data-download-cta="home"`。
- 用到它的位置：首屏（约第 75 行 `home-actions`）和 `#download` 区块（约第 103 行）。`#download` 区块里的系统要求、大小、「已通过 Apple 公证」和 SHA-256 都是 Mac 专属。Windows 要有自己的一行：`Glance for Windows 0.1.0 · Windows 10 2004+ · x64 · 94.7 MB`，以及单独的 SHA-256。**不要**把「Apple 公证」用在 Windows 上；Windows 包未签名。
- `src/homepage.json` 为首页四种语言（zh / en / ja / de）各加文案键，例如 `Download for Windows` / `Windows system requirements`。建议文案：
  - zh：`下载 Windows 版`
  - en：`Download for Windows`
  - ja：`Windows 版を入手`
  - de：`Für Windows laden`

### 3.4 下载与安装页（`src/pages/30-install.html`）

该页目前全部是 macOS 内容（中英双语，`lang="zh"` / `lang="en"`）。增加一个 Windows 小节，包含下载按钮（`href="/download/windows"`，`data-download-cta="install"`，`data-app-version="{{WIN_VERSION}}"`）、`SHA-256: {{WIN_SHA256}}` 和下面的步骤。页首描述（第 1 行 `desc:`）同步加上 Windows。

中文：

1. 下载 `Glance-{{WIN_VERSION}}-win-x64.zip`（{{WIN_SIZE}}）。
2. 右键 zip →「全部解压缩」，把解压出的文件夹放到固定位置，例如 `C:\Users\你的用户名\AppData\Local\Programs\Glance`。开机启动会记住这个位置，之后不要移动它。
3. 打开文件夹，双击 `Glance.exe`。
4. 如果出现「Windows 已保护你的电脑」：点「更多信息」→「仍要运行」。Glance for Windows 目前还没有代码签名，可以用上方的 SHA-256 核对下载是否完整。
5. Glance 会出现在任务栏右下角的通知区域。选中任意路径、链接或文件名，按 `Alt+Q` 预览；可在「偏好设置」中更改快捷键、开机启动和资源管理器右键菜单。
6. 网页、PDF 或 Markdown 无法显示时，按提示安装 Microsoft Edge WebView2 Runtime（Windows 11 已自带）。

卸载：在「偏好设置」关闭「随 Windows 启动」和资源管理器右键菜单 → 从通知区域图标退出 Glance → 删除程序文件夹。如需同时删除设置、历史和登录信息，再删除 `%APPDATA%\Glance` 和 `%LOCALAPPDATA%\Glance`。

English:

1. Download `Glance-{{WIN_VERSION}}-win-x64.zip` ({{WIN_SIZE}}).
2. Right-click the zip → Extract All, and put the folder somewhere permanent, for example `%LOCALAPPDATA%\Programs\Glance`. Start with Windows remembers this location, so don't move the folder later.
3. Open the folder and double-click `Glance.exe`.
4. If Windows shows "Windows protected your PC", click More info → Run anyway. Glance for Windows isn't code-signed yet; you can check the download with the SHA-256 above.
5. Glance appears in the notification area. Select any path, link or file name and press `Alt+Q` to preview it. Change the hotkey, startup and File Explorer menu in Preferences.
6. If web pages, PDFs or Markdown don't show, install the Microsoft Edge WebView2 Runtime when Glance asks (Windows 11 already has it).

Uninstall: in Preferences, turn off Start with Windows and the File Explorer menu → quit Glance from its notification-area icon → delete the folder. To also remove settings, history and sign-in, delete `%APPDATA%\Glance` and `%LOCALAPPDATA%\Glance`.

### 3.5 其他需要同步的位置

- **结构化数据**（`build.py` 约第 230–236 行 `SoftwareApplication`）：`operatingSystem` / `downloadUrl` 目前只描述 Mac。可加第二个 `SoftwareApplication`，或改成多平台写法；不要把 Mac 的 `softwareVersion` 套在 Windows 上。
- **SEO 定位**：页面描述和 `DESCRIPTIONS` 仍写作「Mac 图片和视频查看器」。是否改成跨平台措辞是产品决定，先问用户，不要顺手改。
- **可选的平台识别**：可在 `site.js` 中按 `navigator.userAgentData?.platform` 或 UA 含 `Windows` 时把 Windows 按钮设为主按钮。两个按钮在无 JavaScript 时都必须可见可用。
- **统计**：`site.js` 把带 `data-download-cta` 的点击记为 `cta_click / download`，Windows 按钮会自动计入，但与 Mac 不分开。要分平台统计，需要服务端 `server/GlanceService/src/launch-analytics.ts` 的 `targets` 集合加新值，这属于服务端改动，需用户另行要求。
- **测试**：`test_site.py` 中补充检查：首页和安装页含 `/download/windows`、Windows 版本号和 SHA-256；`_redirects` 含 `/download/windows`；`windows-release.json` 缺字段或格式错时构建失败。

## 4. 检查与发布

按 `website/static/README.md` 运行全部检查：

```sh
python3 website/static/build.py
python3 -m unittest discover -s website/static -p 'test_*.py'
node --check website/static/src/assets/site.js
node --check website/static/functions/_middleware.js
node --test website/static/test_middleware.cjs website/static/test_presentation.cjs website/static/test_analytics.cjs
git diff --check
```

注意 `build.py` 还要求 macOS DMG 存在且已公证（见该 README），在缺 DMG 的工作区会直接失败。这与 Windows 改动无关，不要为了通过构建而删掉或绕过这些检查。

只有用户明确要求部署时才执行 `wrangler pages deploy`（命令见官网 README）。部署后核对：

- 首页 `/`、`/en/`、`/ja/`、`/de/` 和 `/install/`、`/en/install/` 都有 Windows 按钮；
- `https://glancepreview.com/download/windows` 302 到 R2 上的 zip，下载文件的 SHA-256 与页面一致；
- Mac 下载、校验值、appcast 均未受影响。

## 5. 每次发布新 Windows 版本

1. `GlanceWin\package.ps1 -Version X.Y.Z`，记录大小与 SHA-256。
2. 上传到 R2 的 `windows/Glance-X.Y.Z-win-x64.zip`，下载回来核对 SHA-256。
3. 更新 `website/static/src/windows-release.json`，运行检查；用户要求时再部署官网。
4. 在本文顶部追加一条发行记录（日期、版本、bytes、SHA-256、R2 路径），格式参照 [`release-macos.md`](release-macos.md)。

## 发行记录

### 2026-11-21 Glance for Windows 0.1.0 打包完成（尚未上线）

`GlanceWin/package.ps1` 生成 `Glance-0.1.0-win-x64.zip`，94,749,478 bytes，SHA-256 `35989dff89e81e6d6eb9bfad43fefe968bcb9227b10d9cc2075431aebf00c668`。179 项单元测试通过。自包含 x64、未签名、无安装程序。源码在分支 `feat/windows-client`（提交 `17ba0e1` 及之后）。尚未上传 R2、未改官网、未部署。
