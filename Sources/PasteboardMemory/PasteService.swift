import AppKit
import Foundation

@MainActor
final class PasteService: ObservableObject {
    @Published var notice: String?
    weak var clipboardMonitor: ClipboardMonitor?

    func copy(_ item: HistoryItem, returnTo application: NSRunningApplication?, hidePanel: @escaping () -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var didWrite = false
        switch item.kind {
        case .text, .url:
            if let text = item.text { didWrite = pasteboard.setString(text, forType: .string) }
        case .image, .screenshot:
            if let image = item.image { didWrite = pasteboard.writeObjects([image]) }
        case .file:
            if let path = item.filePath { didWrite = pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL]) }
        }
        guard didWrite else {
            notice = "无法读取这条记录"
            return
        }

        clipboardMonitor?.ignoreNextChange(pasteboard.changeCount)
        notice = "已复制，按 ⌘V 粘贴"
        hidePanel()
        application?.activate(options: [.activateIgnoringOtherApps])
    }
}
