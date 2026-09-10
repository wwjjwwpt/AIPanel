import AppKit
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []

    private let fileManager = FileManager.default
    private let maxItems = 500
    private let rootURL: URL
    private let imagesURL: URL
    private let dataURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = support.appendingPathComponent("PasteboardMemory", isDirectory: true)
        imagesURL = rootURL.appendingPathComponent("Images", isDirectory: true)
        dataURL = rootURL.appendingPathComponent("history.json")
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    func addText(_ text: String, sourceApp: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let kind: HistoryKind = URL(string: trimmed)?.scheme != nil ? .url : .text
        let item = HistoryItem(kind: kind, text: trimmed, sourceApp: sourceApp)
        insertDeduplicating(item)
    }

    func addClipboardImage(_ image: NSImage, sourceApp: String?) {
        guard let stored = persistImage(image, preferredExtension: "png") else { return }
        let item = HistoryItem(
            kind: .image,
            filePath: stored.path,
            sourceApp: sourceApp,
            pixelWidth: Int(image.size.width),
            pixelHeight: Int(image.size.height),
            byteCount: fileSize(at: stored)
        )
        insertDeduplicating(item)
    }

    func addFiles(_ urls: [URL], sourceApp: String?) {
        for url in urls.prefix(12).reversed() {
            let item = HistoryItem(kind: .file, text: url.lastPathComponent, filePath: url.path, sourceApp: sourceApp)
            insertDeduplicating(item)
        }
    }

    func addScreenshot(at originalURL: URL, createdAt: Date, archiveDirectory: URL) {
        guard !items.contains(where: { $0.kind == .screenshot && $0.text == originalURL.path }) else { return }
        let destination = uniqueDestination(for: originalURL, in: archiveDirectory)
        do {
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: originalURL, to: destination)
            let image = NSImage(contentsOf: destination)
            let item = HistoryItem(
                kind: .screenshot,
                text: originalURL.path,
                filePath: destination.path,
                createdAt: createdAt,
                sourceApp: "系统截图",
                pixelWidth: image.map { Int($0.size.width) },
                pixelHeight: image.map { Int($0.size.height) },
                byteCount: fileSize(at: destination)
            )
            insertDeduplicating(item, signature: originalURL.path)
        } catch {
            NSLog("Could not archive screenshot: \(error.localizedDescription)")
        }
    }

    func togglePinned(_ item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    func delete(_ item: HistoryItem) {
        if let path = item.filePath,
           path.hasPrefix(imagesURL.path) {
            try? fileManager.removeItem(atPath: path)
        }
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }

    func clearUnpinned() {
        let removing = items.filter { !$0.isPinned }
        for item in removing {
            if let path = item.filePath, path.hasPrefix(imagesURL.path) {
                try? fileManager.removeItem(atPath: path)
            }
        }
        items.removeAll { !$0.isPinned }
        scheduleSave()
    }

    private func insertDeduplicating(_ item: HistoryItem, signature: String? = nil) {
        let value = signature ?? item.displayTitle
        items.removeAll { existing in
            if item.kind == .image { return existing.kind == .image && existing.filePath == item.filePath }
            return existing.kind == item.kind && existing.displayTitle == value
        }
        items.insert(item, at: 0)
        trimIfNeeded()
        scheduleSave()
    }

    private func trimIfNeeded() {
        guard items.count > maxItems else { return }
        let pinned = items.filter(\.isPinned)
        let regular = items.filter { !$0.isPinned }.prefix(max(0, maxItems - pinned.count))
        items = (pinned + regular).sorted { $0.createdAt > $1.createdAt }
    }

    private func persistImage(_ image: NSImage, preferredExtension: String) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = imagesURL.appendingPathComponent("clipboard-\(UUID().uuidString).\(preferredExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("Could not save clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    private func fileSize(at url: URL) -> Int? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    private func uniqueDestination(for source: URL, in directory: URL) -> URL {
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var index = 2
        repeat {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            destination = directory.appendingPathComponent(name)
            index += 1
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }

    private func load() {
        guard let data = try? Data(contentsOf: dataURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded.filter { item in
            guard let path = item.filePath, item.kind == .image || item.kind == .screenshot else { return true }
            return fileManager.fileExists(atPath: path)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        let url = dataURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Could not save history: \(error.localizedDescription)")
            }
        }
    }
}
