# 官网

- [static](static/README.md)：当前生产官网 `https://glancepreview.com/`，Python 静态生成，部署到 Cloudflare Pages。
- [app](app/)：保留的 React / Vinext 网站实现，拥有独立 package.json；不要与生产静态源混用。
- [seo](seo/README.md)：SEO、合规、内容和发布记录。
- [官网设计与历史方案](../design/website/README.md) · [宣传素材源](../design/marketing/README.md)

从仓库根目录构建与检查静态官网：

```sh
python3 website/static/build.py
python3 -m unittest discover -s website/static -p 'test_*.py'
node --check website/static/src/assets/site.js
```

本机网站同步分支为 `website/ops`，源码位于 `website/static/src/`，可运行 `python3 website/static/build.py` 生成 `public/` 本地预览。线上只从 Grok Bot 运维机 `/workspace/glance-site/static` 通过 `deploy.sh` 部署；本机禁止直接部署。发布与 SEO 同步流程见 [static/README.md](static/README.md)。
