# Glance 官网

正式站点：<https://glancepreview.com/>。Cloudflare Pages 项目：`glance`，生产分支：`main`。

## 构建与检查

```sh
python3 website-static/build.py
python3 -m unittest discover -s website-static -p 'test_*.py'
node --check website-static/src/assets/site.js
git diff --check
```

这是官网的静态生成流程，不构建或启动 macOS App。使用 Python 3.12 或更新版本。

`build.py` 要求现有发行包位于 `src/download/Glance-1.0.0-beta.1.dmg`。DMG 由 Git 忽略；在新工作区中准备发行包时，应核对正式安装页公布的 SHA-256，不能用空文件代替。

## 页面与语言

- 编辑 `src/pages/*.html`，文件首行声明路径、中文名、英文名和可选 `noindex`。
- 同一源文件中的 `lang="zh"` / `lang="en"` 内容在构建时拆分，原路径提供中文，`/en/` 下提供英文。
- `localize.py` 会转换内部页面链接，选择对应语言媒体，并保留脚本内容。
- `build.py` 的 `DESCRIPTIONS` 保存各页的中英文描述；首页 title 也在生成器内。
- 可索引页面生成 self-canonical 和双向 hreflang。语言切换使用真实链接，不依赖本地存储或浏览器语言。
- 支付返回页与 404 不生成语言副本，不进入 sitemap；支付返回页允许抓取但使用 `noindex`。
- 同一路径出现多个源文件时构建失败，防止页面和索引规则被覆盖。
- 不统一刷新 sitemap 的 `lastmod`；目前省略该可选字段。

## 发布

确认 Cloudflare 凭据与账户已经通过环境变量配置，且目标项目域名包含 `glancepreview.com` 后，在本目录执行：

```sh
wrangler pages deploy public --project-name glance --branch main --commit-dirty=true
```

发布必须在 `website-static/` 中执行，以便包含 `functions/_middleware.js` 的域名跳转规则。不要把账户密钥写进源码或提交到 Git。发布后核对 `/`、`/en/`、语言子页面、sitemap、robots、支付页 `noindex`、下载校验值和域名跳转。

SEO 调研与发布记录位于 [`../seo/`](../seo/)。
