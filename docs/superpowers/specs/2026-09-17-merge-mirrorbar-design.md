# 瞬贴 v1.2.0 — 合并 MirrorBar 显示器镜像功能 · 设计文档

日期：2026-09-17
状态：已获用户批准

## 背景

用户自研的 MirrorBar（`~/workspace/monitor_control`，Swift Package，485 行）是 macOS 菜单栏显示器镜像开关工具，与瞬贴（AIPanel）架构完全一致（SwiftPM + 菜单栏 App + AppKit/SwiftUI）。目标：把镜像功能合并进瞬贴，减少菜单栏图标数量，统一入口。

## 已确认的产品决策

1. **入口方式**：瞬贴主面板顶部加标签切换「剪贴板」｜「显示器镜像」
2. **快捷键**：不为镜像开关新增全局快捷键
3. **独立版去留**：合并验收通过后，退出运行中的 MirrorBar 并删除 `/Applications/MirrorBar.app`；`monitor_control` 源码仓库保留不动

## 代码迁移

从 `monitor_control/Sources/MirrorBar/` 拷入 `AIPanel/Sources/PasteboardMemory/`：

| 源文件 | 处理 |
|---|---|
| `DisplayInfo.swift` | 原样拷入（数据模型 + `DisplayError`） |
| `DisplayController.swift` | 原样拷入（CGDisplay 镜像配置核心逻辑） |
| `DisplayStore.swift` | 拷入，UserDefaults 键改为带 `mirror.` 前缀（`mirror.sourceDisplayID`） |
| `MirrorPanel.swift` | 改造为 `MirrorTabView.swift`：去掉登录自启开关（瞬贴设置已有 `LaunchAtLoginManager`）、去掉「退出」按钮；保留主显示器单选、镜像目标多选、一键开/关、状态指示、「显示器设置…」链接 |
| `MirrorBarApp.swift` | 不拷（@main 入口冲突） |
| `LoginItemManager.swift` | 不拷（与瞬贴功能重复） |

## UI 设计

- `HistoryPanelView` 顶部新增标签切换控件：「剪贴板」｜「显示器镜像」
- 剪贴板标签 = 现有功能原样不动（搜索、筛选、键盘导航、粘贴）
- 镜像标签 = `MirrorTabView`，适配 780 宽面板（原 MirrorBar 面板 340 宽，改为自适应布局）
- 单显示器时镜像标签显示「需要另一台显示器」空状态
- Esc 关闭面板行为在两个标签下一致
- 镜像开/关进行中显示进度（`isApplying`），错误用中文提示（`DisplayError` 已有）

## 接线

- `AppController` 新增 `let displayStore = DisplayStore()`（与 `HistoryStore` 同级），传给面板视图
- `DisplayStore` 自带 `CGDisplayRegisterReconfigurationCallback` 显示器插拔监听，插拔自动刷新，无需轮询
- 状态栏右键菜单新增「显示器镜像」菜单项：打开主面板并切到镜像标签

## 版本与构建

- 版本号 v1.1.0 → v1.2.0
- README 新增镜像功能说明
- 构建脚本沿用现有 `scripts/build-app.sh`（结构相同，无需改动）
- 当前工作区未提交的面板层级修复（AppController.swift）与签名证书改动（build-app.sh）为上次会话成果，先单独提交，再做本功能

## 错误处理

沿用 `DisplayError` 三种场景的中文提示：显示器不足、主显示器断开、系统配置失败。镜像切换失败在标签内联展示，不影响剪贴板功能。

## 验收标准

1. `./scripts/build-app.sh` 构建通过，瞬贴正常启动
2. 标签切换正常，两个标签下 Esc 行为一致
3. 镜像标签：单显示器显示空状态（当前机器 M4 + 单台 2K 屏）
4. 剪贴板/截图回归：⌘⇧V 呼出历史、⌃⇧A 截图正常
5. 验收通过后执行独立版卸载（退出进程 + 删 `/Applications/MirrorBar.app`）

## 限制说明

镜像开关的实际切换效果需要至少两台在线显示器才能实测；当前机器仅一台，无法在本机完整验证。核心逻辑从用户日常在用的 MirrorBar 原样迁移，风险低。
