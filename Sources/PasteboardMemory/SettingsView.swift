import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var screenshotMonitor: ScreenshotMonitor
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var pasteService: PasteService
    @ObservedObject var store: HistoryStore

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机时自动启动瞬贴", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                LabeledContent("快速粘贴快捷键") { Text("⌘ ⇧ V").font(.system(.body, design: .monospaced)) }
                Text("选中记录后会复制并返回原应用，直接按 ⌘V 粘贴。")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("区域截图快捷键") { Text("⌃ ⇧ A").font(.system(.body, design: .monospaced)) }
                Text("框选屏幕区域截图，自动复制到剪贴板并归档。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("截图归档") {
                LabeledContent("归档工作区") {
                    Text(screenshotMonitor.archiveFolderURL?.path ?? "尚未选择")
                        .lineLimit(1).truncationMode(.middle)
                }
                Button("选择归档工作区…") { screenshotMonitor.chooseArchiveWorkspace() }
                LabeledContent("系统截图来源") {
                    Text(screenshotMonitor.sourceFolderURL.path).lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("更改截图来源…") { screenshotMonitor.chooseSourceFolder() }
                    Spacer()
                    Circle().fill(screenshotMonitor.isMonitoring ? .green : .gray).frame(width: 7, height: 7)
                    Text(screenshotMonitor.isMonitoring ? "自动归档已开启" : "等待选择工作区").foregroundStyle(.secondary)
                }
            }

            Section("历史记录") {
                LabeledContent("保存位置") { Text("~/Library/Application Support/PasteboardMemory").font(.caption) }
                Button("清除未固定的历史记录", role: .destructive) { store.clearUnpinned() }
            }

            Section {
                Button("退出瞬贴") { NSApp.terminate(nil) }
            }

            if let error = launchAtLogin.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 520, height: 430)
        .onAppear { launchAtLogin.refresh() }
    }
}
