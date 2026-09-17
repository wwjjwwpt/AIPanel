# 瞬贴 v1.2.0 合并 MirrorBar 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 MirrorBar 的显示器镜像开关功能合并进瞬贴，主面板顶部加「剪贴板｜显示器镜像」标签切换。

**Architecture:** MirrorBar 三个核心文件（数据模型、CGDisplay 控制器、状态 Store）原样迁入瞬贴 target；`MirrorPanel` 改造成 `MirrorTabView` 嵌入主面板；`AppController` 新增 `displayStore` 并通过回调和通知联动标签状态。

**Tech Stack:** Swift 5（SwiftPM）、AppKit、SwiftUI、CoreGraphics（Quartz Display Services）。

**设计文档:** `docs/superpowers/specs/2026-09-17-merge-mirrorbar-design.md`

**测试说明:** 本项目无测试 target，功能为菜单栏 UI + 硬件显示器 API（CGDisplay 无法在单屏环境模拟）。按已批准设计的验收标准，每个任务以 `swift build` 为自动门禁，最后统一做构建 + 运行时手动验收。

**提交规范:** 所有提交使用 `git -c user.name="老虎温温" -c user.email="wwjjwwpt@users.noreply.github.com" commit`。

**源码来源:** `~/workspace/monitor_control/Sources/MirrorBar/`（只读，不修改该仓库）。

---

### Task 1: 迁移镜像核心三文件

**Files:**
- Create: `Sources/PasteboardMemory/DisplayInfo.swift`
- Create: `Sources/PasteboardMemory/DisplayController.swift`
- Create: `Sources/PasteboardMemory/DisplayStore.swift`

- [ ] **Step 1: 拷贝三个文件**

```bash
cp ~/workspace/monitor_control/Sources/MirrorBar/DisplayInfo.swift ~/workspace/AIPanel/Sources/PasteboardMemory/
cp ~/workspace/monitor_control/Sources/MirrorBar/DisplayController.swift ~/workspace/AIPanel/Sources/PasteboardMemory/
cp ~/workspace/monitor_control/Sources/MirrorBar/DisplayStore.swift ~/workspace/AIPanel/Sources/PasteboardMemory/
```

- [ ] **Step 2: DisplayStore.swift 的 UserDefaults 键加前缀**

两处修改，避免与其他键冲突：

第 34 行：
```swift
UserDefaults.standard.set(Int(id), forKey: "mirror.sourceDisplayID")
```

第 77 行：
```swift
let saved = UInt32(UserDefaults.standard.integer(forKey: "mirror.sourceDisplayID"))
```

- [ ] **Step 3: 编译验证**

Run: `cd ~/workspace/AIPanel && swift build 2>&1 | tail -3`
Expected: `Build complete!`（三个新文件未被引用但必须编译通过；瞬贴用 Swift 5 语言模式，比 MirrorBar 的 Swift 6 模式更宽松）

- [ ] **Step 4: Commit**

```bash
cd ~/workspace/AIPanel && git add Sources/PasteboardMemory/DisplayInfo.swift Sources/PasteboardMemory/DisplayController.swift Sources/PasteboardMemory/DisplayStore.swift
git -c user.name="老虎温温" -c user.email="wwjjwwpt@users.noreply.github.com" commit -m "迁入 MirrorBar 显示器镜像核心（DisplayInfo/DisplayController/DisplayStore）"
```

---

### Task 2: 创建 MirrorTabView

**Files:**
- Create: `Sources/PasteboardMemory/MirrorTabView.swift`

- [ ] **Step 1: 写入完整文件**

从 `MirrorPanel.swift` 改造：去掉登录自启区块、去掉「刷新」「退出」按钮；内容区限宽 460 居中以适配 780 宽面板；保留主显示器单选、镜像目标多选、一键开关、错误提示、「显示器设置…」链接。

```swift
import AppKit
import SwiftUI

struct MirrorTabView: View {
    @ObservedObject var store: DisplayStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: store.isMirroring ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.isMirroring ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text("显示器镜像").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(store.isMirroring ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .accessibilityLabel(store.isMirroring ? "镜像已开启" : "镜像已关闭")
        }
        .padding(16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.displays.count < 2 {
                VStack(spacing: 10) {
                    Image(systemName: "display")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("需要另一台显示器")
                        .font(.headline)
                    Text("连接外接显示器后即可设置镜像。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                displaySection(title: "主显示器") {
                    ForEach(store.displays) { display in
                        displayRow(display, selected: store.sourceID == display.id) {
                            store.chooseSource(display.id)
                        }
                    }
                }

                displaySection(title: "镜像到") {
                    ForEach(store.targets) { display in
                        Toggle(isOn: Binding(
                            get: { store.targetIDs.contains(display.id) },
                            set: { store.setTarget(display.id, selected: $0) }
                        )) {
                            displayLabel(display)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(store.isMirroring || store.isApplying)
                    }
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: store.toggleMirroring) {
                    HStack {
                        if store.isApplying { ProgressView().controlSize(.small) }
                        Text(store.isMirroring ? "关闭镜像" : "开启镜像")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isMirroring ? store.isApplying : !store.canStart)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("显示器设置…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusText: String {
        if store.displays.count < 2 { return "未检测到外接显示器" }
        if store.isMirroring, let source = store.source { return "正在镜像 · \(source.name)" }
        return "扩展显示模式"
    }

    private func displaySection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9, content: content)
        }
    }

    private func displayRow(_ display: DisplayInfo, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                displayLabel(display)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isMirroring || store.isApplying)
    }

    private func displayLabel(_ display: DisplayInfo) -> some View {
        HStack(spacing: 9) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name).lineLimit(1)
                Text(display.resolution).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `cd ~/workspace/AIPanel && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/workspace/AIPanel && git add Sources/PasteboardMemory/MirrorTabView.swift
git -c user.name="老虎温温" -c user.email="wwjjwwpt@users.noreply.github.com" commit -m "新增 MirrorTabView：镜像标签页视图（自 MirrorPanel 改造）"
```

---

### Task 3: 主面板加标签切换

**Files:**
- Modify: `Sources/PasteboardMemory/HistoryPanelView.swift`

- [ ] **Step 1: 新增 PanelTab 枚举**

加在 `HistoryFilter` 枚举后面：

```swift
enum PanelTab: String, CaseIterable, Identifiable {
    case clipboard = "剪贴板"
    case mirror = "显示器镜像"
    var id: String { rawValue }
}
```

- [ ] **Step 2: 新增视图属性**

加在 `struct HistoryPanelView` 现有属性区（`let onOpenSettings` 之后）：

```swift
    @ObservedObject var displayStore: DisplayStore
    let onTabChange: (PanelTab) -> Void
    @State private var tab: PanelTab = .clipboard
```

- [ ] **Step 3: 改造 body 顶部结构**

把 body 的 VStack 开头：

```swift
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredItems.isEmpty { emptyState } else { historyList }
            Divider()
            footer
        }
```

改为（tabBar 置顶；剪贴板标签保持原结构；镜像标签替换中间区域，不含剪贴板 footer）：

```swift
    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            if tab == .clipboard {
                header
                Divider()
                if filteredItems.isEmpty { emptyState } else { historyList }
                Divider()
                footer
            } else {
                MirrorTabView(store: displayStore)
            }
        }
```

- [ ] **Step 4: 新增 tabBar 视图**

加在 `private var header` 之前：

```swift
    private var tabBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 285)
            Spacer()
            if tab == .mirror {
                Circle().fill(displayStore.isMirroring ? .green : .secondary.opacity(0.35)).frame(width: 7, height: 7)
                Text(displayStore.isMirroring
                     ? "镜像中"
                     : (displayStore.displays.count < 2 ? "未检测到外接显示器" : "扩展显示模式"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
```

- [ ] **Step 5: 联动通知**

在 body 的 `.onReceive(NotificationCenter.default.publisher(for: .focusHistorySearch))` 一行之后追加：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .showMirrorTab)) { _ in tab = .mirror }
        .onChange(of: tab) { onTabChange($0) }
```

并在文件底部 `extension Notification.Name` 中追加：

```swift
    static let showMirrorTab = Notification.Name("showMirrorTab")
```

- [ ] **Step 6: 编译验证**

Run: `cd ~/workspace/AIPanel && swift build 2>&1 | tail -5`
Expected: 编译失败，报 `HistoryPanelView` 缺少 `displayStore`、`onTabChange` 初始化参数（调用方在 Task 4 修复）。若报其他错误则先修复。

（本任务不单独提交，与 Task 4 一起提交）

---

### Task 4: AppController 接线与右键菜单

**Files:**
- Modify: `Sources/PasteboardMemory/AppController.swift`

- [ ] **Step 1: 新增属性**

加在 `let store = HistoryStore()` 之后：

```swift
    let displayStore = DisplayStore()
    private var activeTab: PanelTab = .clipboard
```

- [ ] **Step 2: configurePanel 传入新参数**

```swift
        let content = HistoryPanelView(
            store: store,
            pasteService: pasteService,
            displayStore: displayStore,
            onPaste: { [weak self] item in self?.paste(item) },
            onClose: { [weak self] in self?.hidePanel() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onTabChange: { [weak self] tab in self?.activeTab = tab }
        )
```

- [ ] **Step 3: 键盘监听按标签分流**

镜像标签下方向键/回车/删除键不能触发剪贴板操作（否则回车会粘贴隐藏选中的历史记录）。把 `configurePanel` 中的 localKeyMonitor 闭包整体替换为：

```swift
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.panel?.isVisible == true else { return event }
            switch event.keyCode {
            case 53:
                self?.hidePanel()
                return nil
            case 126, 125, 36, 76, 51, 117:
                guard self?.activeTab == .clipboard else { return event }
                switch event.keyCode {
                case 126:
                    NotificationCenter.default.post(name: .moveHistorySelectionUp, object: nil)
                    return nil
                case 125:
                    NotificationCenter.default.post(name: .moveHistorySelectionDown, object: nil)
                    return nil
                case 36, 76:
                    NotificationCenter.default.post(name: .pasteHistorySelection, object: nil)
                    return nil
                case 51, 117:
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                        NotificationCenter.default.post(name: .deleteHistorySelection, object: nil)
                        return nil
                    }
                    return event
                default:
                    return event
                }
            default:
                return event
            }
        }
```

- [ ] **Step 4: 右键菜单加「显示器镜像」项**

`configureStatusItem` 中，在「显示瞬贴」之后加一行：

```swift
        menu.addItem(withTitle: "显示器镜像", action: #selector(showMirrorFromMenu), keyEquivalent: "")
```

- [ ] **Step 5: 新增 action 方法**

加在 `@objc private func showFromMenu()` 之后：

```swift
    @objc private func showMirrorFromMenu() {
        NotificationCenter.default.post(name: .showMirrorTab, object: nil)
        showPanel()
    }
```

- [ ] **Step 6: 编译验证**

Run: `cd ~/workspace/AIPanel && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 7: Commit（含 Task 3 改动）**

```bash
cd ~/workspace/AIPanel && git add Sources/PasteboardMemory/HistoryPanelView.swift Sources/PasteboardMemory/AppController.swift
git -c user.name="老虎温温" -c user.email="wwjjwwpt@users.noreply.github.com" commit -m "主面板新增剪贴板/显示器镜像标签切换，右键菜单直达镜像标签"
```

---

### Task 5: 版本号与 README

**Files:**
- Modify: `scripts/build-app.sh:32-33`
- Modify: `README.md`

- [ ] **Step 1: 版本号 1.1.0 → 1.2.0**

```bash
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.2.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 3" "$CONTENTS_DIR/Info.plist"
```

- [ ] **Step 2: README 更新**

第一行描述改为：

```markdown
一个原生 macOS 菜单栏剪贴板、截图历史与显示器镜像工具。
```

「功能」列表末尾（`- 可选开机启动` 之后）追加：

```markdown
- 主面板「显示器镜像」标签：选择主显示器与镜像目标，一键开/关屏幕镜像（需外接显示器，自动响应显示器插拔）
```

- [ ] **Step 3: Commit**

```bash
cd ~/workspace/AIPanel && git add scripts/build-app.sh README.md
git -c user.name="老虎温温" -c user.email="wwjjwwpt@users.noreply.github.com" commit -m "版本升至 1.2.0，README 补充显示器镜像功能说明"
```

---

### Task 6: 构建与运行验收

**Files:** 无代码改动（验证任务）

- [ ] **Step 1: 退出正在运行的旧版瞬贴**

```bash
pkill -x PasteboardMemory || true
```

- [ ] **Step 2: 完整构建**

Run: `cd ~/workspace/AIPanel && ./scripts/build-app.sh`
Expected: 输出 `dist/瞬贴.app` 路径，无签名错误

- [ ] **Step 3: 启动并手动验收**

```bash
open dist/瞬贴.app
```

验收清单（对照设计文档验收标准）：
1. 菜单栏出现剪贴板图标，面板自动弹出
2. 顶部「剪贴板｜显示器镜像」切换正常
3. 镜像标签显示「需要另一台显示器」空状态（当前单屏）
4. Esc 在两个标签下都能关闭面板
5. 剪贴板回归：⌘⇧V 呼出、搜索、方向键、回车复制返回原应用
6. 截图回归：⌃⇧A 触发截图
7. 右键菜单栏图标 → 「显示器镜像」直达镜像标签
8. 镜像标签下按回车不会粘贴历史记录（键盘分流生效）

- [ ] **Step 4: 里程碑提交（可选，如构建产物不进 git 则跳过）**

dist/ 已在 .gitignore 或未跟踪时无需提交。

- [ ] **Step 5: 用户双屏实测确认后卸载独立版**

镜像开/关需要两台在线显示器，本机当前单屏无法实测。用户接上第二台屏验证「开启镜像/关闭镜像」后执行：

```bash
pkill -x MirrorBar || true
rm -rf /Applications/MirrorBar.app
```

（此步为已批准操作，但需等用户确认双屏实测通过；`monitor_control` 源码仓库不动）

---

## Self-Review 记录

- **Spec 覆盖:** 迁移表 5 个文件 ✓（Task 1/2）；标签 UI ✓（Task 3/4）；UserDefaults 前缀 ✓（Task 1）；右键菜单 ✓（Task 4）；版本 + README ✓（Task 5）；验收 + 卸载 ✓（Task 6）
- **占位符扫描:** 无 TBD/TODO
- **类型一致性:** `PanelTab` 定义于 Task 3、使用于 Task 4（同模块）✓；`DisplayStore` Task 1 创建、Task 3/4 引用 ✓；通知名 `.showMirrorTab` Task 3 定义、Task 4 发送 ✓；回调名 `onTabChange` 两任务一致 ✓
- **已知风险:** Task 3 Step 6 预期编译失败是中间状态（跨任务耦合），Task 4 Step 6 恢复绿色
