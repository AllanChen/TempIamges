# Glance 改进计划：让触发更省事

> 目标：从「用户必须先选中/复制文字 + 按快捷键」演进到「光标下的文件路径被自动识别，几乎零显式操作即可预览」。
> 现状：Swift/SwiftUI 原生 macOS 菜单栏 App；当前触发方式 = 全局快捷键读取选中/剪贴板文字 → 解析成文件 → 弹窗预览。
> 核心痛点：**触发太麻烦**。

---

## 背景：为什么不能「拦截任意软件的 Cmd+click」

- 别的软件（终端 / VSCode / IDE）内部的 Cmd+click 链接事件在**它们自己进程内**处理，不会向外广播，无法直接监听。
- 想「无侵入、通用拦截」只能走操作系统层全局监听（CGEventTap + Accessibility），但：
  - 终端是**自绘 canvas**，Accessibility 树里通常**读不到那段文字**，无法可靠判断点了哪个路径。
  - 会与目标 app 自身的点击处理**冲突**。
- 因此结论：**没有对所有软件通用的干净方案**。可行路径是「逐个接入开放了扩展点的应用」+「本机全局 hover 只读探测」。

---

## 三层改进方案（按优先级）

### Tier 1 — 降低现有全局快捷键成本（低风险，先做）

最直接缓解「触发太麻烦」，纯读取、不消费点击、不与其他 app 抢事件。

1. **Hover + 单修饰键预览（重点）**
   - 不再要求先选中/复制。用户按住某修饰键（如 Cmd / Fn）时，用 Accessibility API 读取**鼠标光标位置下**的文本 token，自动识别路径 → 悬停即预览。
   - 这是最接近「Cmd+click 感觉」的做法，且只读不抢点击。
   - 依赖 `SelectedTextExtractor` 是否已支持「读鼠标位置下文本」而非仅「读选中」。
   - 终端类 app 读不到时需降级策略（见 Tier 3）。

2. **自动剪贴板监听（可选开关）**
   - 复制到剪贴板且内容像路径 → 静默角标提示，按住修饰键才弹大窗，避免打扰。

涉及文件：`KeyboardMonitor.swift`、`SelectedTextExtractor.swift`、`PreviewPanel.swift`、`Preferences.swift`

---

### Tier 2 — 每个应用的深度集成（覆盖终端/IDE，最接近真·Cmd+click）

用各 app 的官方扩展点，把「打开文件」重定向到 Glance。这是解决「终端里读不到文本」的正解。

3. **统一后端入口**：为 Glance 增加
   - **CLI 入口**：`glance --preview <path>`
   - **URL scheme**：`glance://preview?path=...`
   为下面所有集成提供统一调用方式。

4. **iTerm2 Semantic History** → 配置调用 `glance --preview <path>`，Cmd+click 文件即弹 Glance。

5. **VSCode 扩展** → 注册 LinkProvider / 覆盖 open 行为，Cmd+click 走 `glance://` 或 CLI。

6. **WezTerm / kitty** → 配置 hyperlink / open-uri handler 指向 Glance。

覆盖 iTerm2 + VSCode + WezTerm 基本吃掉绝大多数开发者场景。

---

### Tier 3 — 识别鲁棒性（让「触发后能命中」）

7. **强化路径解析**：相对路径、`~` 展开、`file.png:12` 行号、项目根推断、提高 `FilenameCache` 命中率。

8. **终端场景降级链**：读不到光标下文本时，按优先级回退：
   读光标下文本 → 读当前行 → 读选中 → 读剪贴板。

涉及文件：`PathDetector.swift`、`FileNameResolver.swift`、`FilenameCache.swift`

---

## 建议实施顺序

1. **先做 Tier 1 的 hover + 修饰键**：最直接缓解痛点，纯读不抢点击，改动集中在 `KeyboardMonitor` + `SelectedTextExtractor`。
2. **再补 Tier 2 的 CLI/URL scheme + iTerm2 + VSCode 集成**：覆盖开发者主场景。
3. **持续做 Tier 3**：提升命中率与终端降级体验。

---

## 重启后需要先确认的问题

1. `SelectedTextExtractor` 目前**已支持「读鼠标光标下文本」了吗**，还是只支持「读选中文本」？（决定 Tier 1 能否低成本落地）
2. `KeyboardMonitor` 现在用的是 CGEventTap 还是其他？是否已监听 `flagsChanged`（修饰键状态）？
3. `PathDetector` / `FileNameResolver` 现有的解析规则覆盖到哪些格式（相对路径 / 行号 / `~`）？
4. 是否已有 CLI 入口 / URL scheme 注册？

> 重启到 `/Users/mac/Desktop/side_project/TempIamges` 后，我会读 `KeyboardMonitor.swift`、`SelectedTextExtractor.swift`、`PathDetector.swift`、`FileNameResolver.swift`、`SEARCH_RULES.md`，把本计划细化到「精确到文件与函数」的可执行步骤。
