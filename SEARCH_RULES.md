# Glance 文件搜索规则 (Search Rules)

## 概述

Glance 的核心能力是通过文件名或部分文本快速定位文件。本规则定义了搜索策略、优先级和优化参数，确保搜索**快**且**准**。

## 搜索层级（从上到下，逐层回退）

### Layer 1: 内存缓存（纳秒级）
- **机制**: LRU 缓存，最多 500 条
- **命中条件**: 精确匹配 token（大小写不敏感）
- **验证**: 返回前检查文件是否仍然存在
- **持久化**: 缓存保存到 `~/Library/Application Support/Glance/filename-cache.json`
- **策略**: 每次成功解析后写入，下次直接命中

### Layer 2: 快速文件系统搜索（毫秒级）
- **目标**: 在 0.5 秒内完成，最多遍历 20,000 个目录，最大深度 10
- **策略 A - 直接候选路径**: 
  - 尝试 `file://` 协议路径
  - 尝试 `~/` 路径并展开
  - 尝试绝对路径 `/`
  - 在常见根目录下拼接相对路径：Desktop, Documents, Downloads, CWD, CWD 的父目录
- **策略 B - 浅层目录遍历**:
  - 优先搜索 Desktop, Documents, Downloads 的子目录（最大深度 1）
  - 按目录修改时间排序（最新的优先）
- **终止条件**: 找到匹配或超时

### Layer 3: Spotlight (mdfind) + 深度搜索（亚秒级）
当 Layer 2 未命中时，并行启动三个搜索：

#### 3A: mdfind 精确匹配
```bash
mdfind -name "<basename>" -onlyin ~
```
- 使用文件名精确匹配
- 仅在用户主目录搜索
- 超时: 0.8 秒

#### 3B: mdfind 模糊匹配 (case-insensitive, diacritic-insensitive)
```bash
mdfind 'kMDItemFSName == "<basename>"cd' -onlyin ~
```
- 忽略大小写和变音符号
- 超时: 0.8 秒

#### 3C: 深度文件系统遍历
- **目标**: 在 1.0 秒内完成，最多遍历 50,000 个目录，最大深度 12
- **搜索根目录**:
  - `~/Projects`, `~/Workspace`, `~/Code`, `~/Dev`, `~/work`（如果存在）
  - Desktop, Documents, Downloads
  - 当前工作目录及其父目录链
  - 整个用户主目录
- **排序策略**: 按目录修改时间（最新的优先深入）

### 结果合并与排序
1. **去重**: 按绝对路径去重
2. **优先级排序**:
   - 优先显示 Desktop/Documents/Downloads 中的文件
   - 其次显示用户主目录内的文件
   - 再按最后修改时间排序（最新的在前）
   - 最后按路径长度排序（越短越靠前）

## 准确性规则

### Token 规范化
1. 去除首尾空白字符
2. 去除首尾引号 `"'`
3. 去除尾部标点 `,.;!?"')}]`
4. 去除开头的 `./`

### 后缀过滤 (对于相对路径)
- 如果 token 包含 `/`，要求匹配文件的路径以该后缀结尾
- 例如 `docs/readme.md` 只匹配 `.../docs/readme.md`，不匹配 `.../other/readme.md`

### 黑名单过滤
自动排除包含以下子串的路径：
- `/.Trash/`, `/.Trashes/`, `/Trash/`
- `/Library/Caches/`
- `/private/var/folders/`
- `/.git/`
- `.icloud`

### 目录跳过
跳过以下目录名（不遍历其子目录）：
```
.git, .svn, .hg, node_modules, DerivedData, build, dist,
.build, .dart_tool, .next, .nuxt, .cache, Pods, Carthage,
Library, Applications, Movies, Music, Pictures
```

## 性能优化规则

### 超时控制
| 层级 | 超时时间 | 说明 |
|------|---------|------|
| Layer 2 (快速) | 0.5 秒 | 浅层搜索 |
| Layer 3A (mdfind 精确) | 0.8 秒 | Spotlight |
| Layer 3B (mdfind 模糊) | 0.8 秒 | Spotlight |
| Layer 3C (深度) | 1.0 秒 | 深度遍历 |
| 总超时 | 1.5 秒 | 整个 resolve 调用 |

### 并发策略
- Layer 3 的三个搜索并行执行（使用 DispatchGroup）
- 每个搜索在独立的 `.userInitiated` QoS 线程上运行
- 任一搜索完成即贡献结果，不需要全部完成

### 限制参数
| 参数 | Layer 2 | Layer 3C | 说明 |
|------|---------|----------|------|
| 最大目录数 | 20,000 | 50,000 | 防止无限遍历 |
| 最大深度 | 10 | 12 | 防止过深递归 |
| 返回结果上限 | 24 | 24 | 减少 UI 负担 |

## 缓存策略

### 缓存键
- 使用规范化后的 token 作为键
- 大小写不敏感

### 缓存验证
- 每次查找时验证文件是否仍然存在
- 如果文件已删除，自动从缓存移除

### 缓存淘汰
- LRU (Least Recently Used)
- 最大条目数: 500
- 超过上限时淘汰最旧的条目

## 最佳实践

### 提高命中率的技巧
1. **使用完整文件名**: `readme.md` 比 `readme` 更准确
2. **包含扩展名**: 有扩展名的 token 会被优先识别为文件
3. **相对路径提示**: `docs/readme.md` 比 `readme.md` 更精确

### 对于开发者
- 项目文件放在 `~/Projects`, `~/Workspace`, `~/Code` 下会被优先深度搜索
- 经常访问的文件会进入缓存，后续几乎是瞬间显示

## 调试

查看搜索日志：
```bash
tail -f ~/Library/Application\ Support/Glance/app.log | grep -E "FileNameResolver|PathDetector"
```

关键日志：
- `cache hit` - 缓存命中
- `quick hit` - 快速搜索命中
- `mdfind failed` - Spotlight 搜索失败
- `-> N [completed]` - 搜索完成，返回 N 个结果
- `-> N [timeout]` - 搜索超时，返回 N 个已找到的结果
