# Glance Native Layout

这是 Glance 新版界面的独立原生 macOS 交互原型，不是 HTML，也不会修改当前生产 App。

原型使用 SwiftUI 构建，覆盖：

- Quick Preview
- Image Inspect
- Video Inspect
- Content Viewer
- Widget Market
- Task Center
- Base64
- History
- Settings
- Onboarding
- Widget Web

## 运行

```bash
cd layout/GlanceNativeLayout
./run-layout.sh
```

脚本会使用 Release 配置生成并启动：

```text
layout/GlanceNativeLayout/Glance Layout.app
```

## 交互演示

- 在左侧切换各页面。
- Image Inspect 中点击 `Run Widget`，可查看提交、进度、缩略图呼吸状态与结果插入。
- Widget Market 的 reload 会显示与真实列表等高的 skeleton。
- Base64 可查看校验、loading、成功预览与失败状态。
- Widget Web 顶部可切换 Ready、Loading、Error。
- Video Inspect 顶部可切换 Ready、Buffering、Error。

完整尺寸、状态与动画规范见 `GLANCE-NATIVE-UI-SPEC.md`。

## 边界

这个原型用于确认新版布局和交互语言。生产实现时保留 Glance 现有的图片加载、拖放、快捷键、Widget、任务和权限逻辑，逐页替换旧 AppKit 视图树。
