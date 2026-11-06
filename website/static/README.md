# Glance 官网

正式站点：<https://glancepreview.com/>。本机网站同步分支为
`website/ops`（仓库 `AllanChen/TempIamges`）；线上部署由 Grok Bot 运维机独占。

## 构建与检查

```sh
python3 website/static/refresh_public_snapshot.py
python3 website/static/build.py
python3 -m unittest discover -s website/static -p 'test_*.py'
node --check website/static/src/assets/site.js
node --check website/static/functions/_middleware.js
git diff --check
```

这是官网的静态生成流程，不构建或启动 macOS App。使用 Python 3.12 或更新版本。

`build.py` 要求现有发行包位于 `src/download/Glance-1.0.0-beta.1.dmg`。DMG 由 Git 忽略；在新工作区中准备发行包时，应核对正式安装页公布的 SHA-256，不能用空文件代替。

`refresh_public_snapshot.py` 从公开 API 更新 `src/public-snapshot.json`。每次发布前运行，确认 Widget 名称、计费单位和销售状态与服务端一致。构建器用它生成无需 JavaScript 即可阅读的 Widget 列表和当前定价状态；浏览器加载后仍向 API 获取实时数据。刷新失败时不要沿用旧快照发布价格变化。

## 页面与语言

- 编辑 `src/pages/*.html`，文件首行声明路径、中文名、英文名和可选 `noindex`。
- 同一源文件中的 `lang="zh"` / `lang="en"` 内容在构建时拆分，原路径提供中文，`/en/` 下提供英文。
- `localize.py` 会转换内部页面链接，选择对应语言媒体，并保留脚本内容。
- `build.py` 的 `DESCRIPTIONS` 保存各页的中英文描述；首页 title 也在生成器内。
- 可索引页面生成 self-canonical 和双向 hreflang。语言切换使用真实链接，不依赖本地存储或浏览器语言。
- 支付返回页与 404 不生成语言副本，不进入 sitemap；支付返回页允许抓取但使用 `noindex`。
- Pages 的 `.pages.dev` 预览域名通过中间件响应头设置 `noindex`，正式域名保持可索引。
- 同一路径出现多个源文件时构建失败，防止页面和索引规则被覆盖。
- 不统一刷新 sitemap 的 `lastmod`；目前省略该可选字段。

## 线上部署与本地预览

Cloudflare Pages 线上唯一部署源是 Grok Bot 运维机上的
`/workspace/glance-site/static`，并由该机器的 `deploy.sh` 发布。本地
`website/static` 是同步源码快照；严禁从本机运行 `wrangler pages deploy`
或直接推送生产站。完成源码修改后，把变更交给 SEO/运营 bot 拉取并部署；
如需自行安排同步，先取得确认再让 bot 同步。

本地可在 `website/static/` 运行 `python3 build.py` 生成 `public/` 供预览。
编辑 `src/`，`public/` 是构建产物，通常不要提交。发布前的源码快照、
部署状态和回同步由运营 bot 管理。

当前品牌文案使用 `glancepreview.com`，客服为 X 私信 `@Sir03834855`；
不要在当前页面新增 `mcreator.ai` 或 `support@mcreator.ai`。

每日英文、日文、德文 SEO 内容由 Glance SEO 汇总 bot 生成并直接发布；
本机不再单独发布同题内容，避免分叉。bot 发布后，将网站改动同步回
`website/ops`。

SEO 调研与发布记录位于 [`../seo/`](../seo/)。
