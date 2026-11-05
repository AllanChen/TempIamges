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

部署目录为 `website/static/`，输出为 `public/`，并包含 `functions/`。本次整理未部署；若外部 CI 保存了旧目录 `website-static`，下次发布前应改为 `website/static`。实际发布步骤见 static/README.md。
