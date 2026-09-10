import AppKit
import Foundation

@MainActor
final class ScreenshotMonitor: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var sourceFolderURL: URL
    @Published private(set) var archiveFolderURL: URL?

    private weak var store: HistoryStore?
    private var timer: Timer?
    private var knownPaths = Set<String>()
    private let defaults = UserDefaults.standard

    init(store: HistoryStore) {
        self.store = store
        let savedSource = defaults.string(forKey: "screenshotSourceFolder")
            ?? defaults.string(forKey: "screenshotFolder")
        sourceFolderURL = savedSource.map(URL.init(fileURLWithPath:))
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        archiveFolderURL = defaults.string(forKey: "screenshotArchiveWorkspace").map(URL.init(fileURLWithPath:))
    }

    var needsArchiveWorkspace: Bool { archiveFolderURL == nil }

    func start() {
        seedKnownFiles()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        isMonitoring = archiveFolderURL != nil
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    @discardableResult
    func chooseArchiveWorkspace() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.prompt = "创建工作区"
        panel.message = "选择一个位置，瞬贴会在其中创建“瞬贴截图归档”文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            let workspace = url.lastPathComponent == "瞬贴截图归档"
                ? url
                : url.appendingPathComponent("瞬贴截图归档", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
                archiveFolderURL = workspace
                defaults.set(workspace.path, forKey: "screenshotArchiveWorkspace")
                isMonitoring = true
                return true
            } catch {
                NSLog("Could not create screenshot workspace: \(error.localizedDescription)")
            }
        }
        return false
    }

    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceFolderURL
        panel.prompt = "选择"
        panel.message = "选择 macOS 系统截图实际保存的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            sourceFolderURL = url
            defaults.set(url.path, forKey: "screenshotSourceFolder")
            seedKnownFiles()
        }
    }

    private func seedKnownFiles() {
        knownPaths = Set(candidateFiles().map(\.path))
    }

    private func scan() {
        guard let archiveFolderURL else { return }
        for url in candidateFiles() where !knownPaths.contains(url.path) {
            knownPaths.insert(url.path)
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            store?.addScreenshot(
                at: url,
                createdAt: values?.creationDate ?? values?.contentModificationDate ?? Date(),
                archiveDirectory: archiveFolderURL
            )
        }
    }

    private func candidateFiles() -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: sourceFolderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let imageExtensions = Set(["png", "jpg", "jpeg", "heic"])
        let screenshotWords = ["screenshot", "screen shot", "截屏", "屏幕快照"]
        return urls.filter { url in
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
            return screenshotWords.contains { url.lastPathComponent.lowercased().contains($0) }
        }
    }
}
