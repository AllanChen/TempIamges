# Plan: Glance Landing Page

## TL;DR
为 Glance macOS 应用创建一个单页介绍网站（`index.html`），清晰展示所有核心功能和使用方法。深色主题，响应式设计。

## Context
Glance 是一个原生 macOS 菜单栏工具，功能丰富（见功能清单）。需要一个对外展示的单页网站，用于发给朋友或潜在用户了解产品。

## Work Objectives
- 创建 `index.html` 单页网站
- 包含：Hero区、核心功能卡片、支持格式、使用步骤、快捷键、系统要求、下载区
- 深色主题，匹配 Glance 的暗色 UI 风格
- 响应式，支持移动端
- 纯 HTML/CSS/JS，无需构建工具

## Must NOT Have
- 多页面导航
- 后端或 API
- 复杂动画
- 外部依赖（除可选 CDN 字体/图标）

## Execution Strategy

### Wave 1: Foundation
1. 创建 `index.html` 骨架
2. 编写 CSS 样式系统（深色主题、卡片、按钮）
3. Hero 区域（标题、简介、CTA）

### Wave 2: Content Sections  
4. 核心功能卡片网格（9个功能）
5. 支持格式展示（图片/视频/文档/其他）
6. 使用步骤（3步）
7. 快捷键表格
8. 系统要求

### Wave 3: Polish
9. 下载/Footer 区域
10. 响应式适配
11. 视觉微调（渐变、阴影、悬停效果）

## TODOs

- [x] 1. Create index.html with full page structure and styling
  **What to do**: Write a complete single-page HTML file with embedded CSS. Dark theme matching Glance's UI. Include all sections: Hero, Features, Formats, Steps, Shortcuts, Requirements, Download.
  **QA**: Open file in browser, verify all sections render correctly, check responsive layout at 375px and 1440px widths.

- [x] 2. Build and verify
  **What to do**: No build needed for static HTML. Just verify the file exists and opens correctly.
  **QA**: `open index.html` renders without errors.

## Success Criteria
- [x] index.html exists in repo root
- [x] All 9 core features documented
- [x] 3-step usage flow explained
- [x] Supported formats listed
- [x] Keyboard shortcuts shown
- [x] Responsive on mobile
- [x] Dark theme consistent
