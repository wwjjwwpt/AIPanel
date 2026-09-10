import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private weak var store: HistoryStore?
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?

    init(store: HistoryStore) {
        self.store = store
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func ignoreNextChange(_ changeCount: Int) {
        ignoredChangeCount = changeCount
        lastChangeCount = changeCount
    }

    private func poll() {
        let change = pasteboard.changeCount
        guard change != lastChangeCount else { return }
        lastChangeCount = change
        if ignoredChangeCount == change {
            ignoredChangeCount = nil
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let fileURLs = urls.filter(\.isFileURL)
            if !fileURLs.isEmpty {
                store?.addFiles(fileURLs, sourceApp: sourceApp)
                return
            }
        }
        if let image = NSImage(pasteboard: pasteboard) {
            store?.addClipboardImage(image, sourceApp: sourceApp)
            return
        }
        if let text = pasteboard.string(forType: .string) {
            store?.addText(text, sourceApp: sourceApp)
        }
    }
}
