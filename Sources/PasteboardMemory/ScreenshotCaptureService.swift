import AppKit
import ScreenCaptureKit

enum ScreenshotCaptureService {
    static func sourceRect(selection: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: selection.minX, y: screenHeight - selection.maxY,
               width: selection.width, height: selection.height)
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    @MainActor
    static func capture(selection: CGRect, screen: NSScreen) async throws -> NSImage {
        if #available(macOS 14, *) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw failure("所选显示器已断开或暂时不可用，请重新框选。")
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = sourceRect(selection: selection, screenHeight: screen.frame.height)
            configuration.width = max(1, Int((selection.width * screen.backingScaleFactor).rounded()))
            configuration.height = max(1, Int((selection.height * screen.backingScaleFactor).rounded()))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }

        // Compatibility for macOS 13; newer systems capture within the authorized app itself.
        let local = sourceRect(selection: selection, screenHeight: screen.frame.height)
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let region = CGRect(x: screen.frame.minX + local.minX,
                            y: desktopTop - screen.frame.maxY + local.minY,
                            width: local.width, height: local.height)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        let errors = Pipe()
        process.standardError = errors
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", "\(region.minX),\(region.minY),\(region.width),\(region.height)", url.path]
        try process.run()
        process.waitUntilExit()
        let details = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0, let image = NSImage(contentsOf: url) else {
            throw failure(details.isEmpty ? "系统截图工具未生成图片（退出码 \(process.terminationStatus)）。" : details)
        }
        return image
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "com.aipanel.PasteboardMemory.capture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
