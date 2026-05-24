# Glance 安装指南

## 方式一：直接下载 DMG（最简单）

1. 下载 `Glance-1.0.0.dmg`
2. 双击打开，将 Glance 拖拽到 Applications 文件夹
3. 首次打开时，去 **系统设置 > 隐私与安全性** 允许打开
4. 启动后按提示授予权限：
   - **辅助功能**：读取选中文本
   - **输入监控**：监听热键（Control/Option）

## 方式二：Homebrew 安装（推荐，方便更新）

```bash
brew tap allanchen/tap
brew install --cask glance
```

## 使用方式

1. 启动 Glance，它会在菜单栏运行（不显示 Dock）
2. 在任意应用中选中包含 URL/路径/文件名的文本
3. 按住 **Control**（或你在偏好设置中设置的热键）
4. 松开即可看到预览面板

## 反馈收集

欢迎分享你的使用感受：
- 热键是否顺手？
- 预览速度如何？
- 文件类型识别是否准确？
- 有什么想要的功能？

直接回复我或在 GitHub Issues 留言即可。
