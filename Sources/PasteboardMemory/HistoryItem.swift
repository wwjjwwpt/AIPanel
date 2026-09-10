import AppKit
import Foundation

enum HistoryKind: String, Codable, CaseIterable, Sendable {
    case text
    case url
    case image
    case screenshot
    case file

    var title: String {
        switch self {
        case .text: "文本"
        case .url: "链接"
        case .image: "图片"
        case .screenshot: "截图"
        case .file: "文件"
        }
    }

    var symbol: String {
        switch self {
        case .text: "doc.text"
        case .url: "link"
        case .image, .screenshot: "photo"
        case .file: "doc"
        }
    }
}

struct HistoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: HistoryKind
    var text: String?
    var filePath: String?
    var createdAt: Date
    var sourceApp: String?
    var isPinned: Bool
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int?

    init(
        id: UUID = UUID(),
        kind: HistoryKind,
        text: String? = nil,
        filePath: String? = nil,
        createdAt: Date = Date(),
        sourceApp: String? = nil,
        isPinned: Bool = false,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        byteCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.filePath = filePath
        self.createdAt = createdAt
        self.sourceApp = sourceApp
        self.isPinned = isPinned
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
    }

    var searchableText: String {
        [kind.title, text, filePath, sourceApp]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var displayTitle: String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.replacingOccurrences(of: "\n", with: " ")
        }
        if let filePath {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        return kind.title
    }

    var detailText: String {
        var parts: [String] = []
        if let pixelWidth, let pixelHeight { parts.append("\(pixelWidth) × \(pixelHeight)") }
        if let byteCount { parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)) }
        if let sourceApp, !sourceApp.isEmpty { parts.append(sourceApp) }
        return parts.joined(separator: "  ·  ")
    }

    var image: NSImage? {
        guard let filePath else { return nil }
        return NSImage(contentsOfFile: filePath)
    }
}
