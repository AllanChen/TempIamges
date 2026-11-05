# 服务端

| 模块 | 职责 |
|---|---|
| [GlanceService](GlanceService/README.md) | Cloudflare Worker API、账户、计费、D1 迁移、Widget 市场和管理后台 |
| [glance-cli](glance-cli/README.md) | Python 开发者 CLI、Widget 注册与执行 Worker |
| [widgets](widgets/) | 各 Widget 的 manifest 与处理代码 |

关系：macOS 客户端 → API 创建任务 → CLI Worker 拉取任务并执行 Widget → 回传结果 → 客户端接收结果。官网使用 API 提供账户与价格相关数据；支付回调由 API 处理。

根目录 `./glance-cli-run.sh` 转发到本目录脚本，使用根目录 `.venv/` 安装 `server/glance-cli/`，不自动启动 Worker。

非 UI 检查（仓库根目录）：

```sh
npm --prefix server/GlanceService run typecheck
npm --prefix server/GlanceService test
PYTHONPATH=server/glance-cli/src python3 -m unittest discover -s server/glance-cli/tests
```

[计费 V1](../docs/glance-billing-v1.md) · [任务积分审计](../docs/glance-task-credit-audit.md) · [系统规范](../spec.md)
