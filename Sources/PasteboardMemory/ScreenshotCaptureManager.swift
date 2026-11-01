import AppKit
import CoreGraphics
import Foundation

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class ScreenshotOverlayView: NSView {
    var onCapture: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        startPoint = nil
        currentPoint = nil
        if rect.width < 10 || rect.height < 10 {
            onCancel?()
            return
        }
        onCapture?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            startPoint = nil
            currentPoint = nil
            onCancel?()
        }
    }

    override func draw(_ rect: NSRect) {
        guard let start = startPoint, let current = currentPoint else {
            dimBackground(selection: nil)
            return
        }
        let selection = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                               width: abs(current.x - start.x), height: abs(current.y - start.y))
        dimBackground(selection: selection)

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 2
        border.stroke()

        let sizeText = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = sizeText.size(withAttributes: attrs)
        let labelOrigin = NSPoint(x: selection.midX - size.width / 2,
                                  y: selection.maxY + 6)
        if labelOrigin.y + size.height > bounds.maxY {
            sizeText.draw(at: NSPoint(x: labelOrigin.x, y: selection.maxY - size.height - 6),
                          withAttributes: attrs)
        } else {
            sizeText.draw(at: labelOrigin, withAttributes: attrs)
        }
    }

    private func dimBackground(selection: NSRect?) {
        let fill = NSColor.black.withAlphaComponent(0.35)
        if let selection {
            let clipPath = NSBezierPath(rect: bounds)
            let hole = NSBezierPath(rect: selection)
            clipPath.append(hole)
            clipPath.windingRule = .evenOdd
            fill.set()
            clipPath.fill()
        } else {
            fill.set()
            NSBezierPath(rect: bounds).fill()
        }
    }
}

@MainActor
final class ScreenshotCaptureManager {
    private weak var store: HistoryStore?
    private weak var clipboardMonitor: ClipboardMonitor?
    private var overlayWindow: NSWindow?
    private var editor: ScreenshotEditor?

    init(store: HistoryStore, clipboardMonitor: ClipboardMonitor) {
        self.store = store
        self.clipboardMonitor = clipboardMonitor
    }

    func startCapture() {
        if let editor {
            editor.present()
            return
        }
        guard overlayWindow == nil else { return }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main else { return }

        let view = ScreenshotOverlayView(frame: screen.frame)
        view.onCapture = { [weak self] rect in
            self?.captureRegion(rect, screen: screen)
        }
        view.onCancel = { [weak self] in
            self?.dismissOverlay()
        }

        let window = OverlayWindow(contentRect: screen.frame,
                                   styleMask: .borderless,
                                   backing: .buffered,
                                   defer: false)
        window.contentView = view
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    private func captureRegion(_ rect: CGRect, screen: NSScreen) {
        // AppKit uses a bottom-left origin; screencapture uses the main display's top-left.
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let captureRect = CGRect(x: screen.frame.minX + rect.minX,
                                 y: desktopTop - (screen.frame.minY + rect.maxY),
                                 width: rect.width,
                                 height: rect.height)
        dismissOverlay()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R",
                              "\(captureRect.minX),\(captureRect.minY),\(captureRect.width),\(captureRect.height)",
                              tempURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            showAlert(title: "截图失败", message: "无法启动截图工具：\(error.localizedDescription)")
            return
        }

        guard FileManager.default.fileExists(atPath: tempURL.path),
              let nsImage = NSImage(contentsOf: tempURL) else {
            showAlert(title: "截图失败",
                      message: "无法捕获屏幕内容。请在系统设置 > 隐私与安全性 > 屏幕录制中允许瞬贴，然后重试。")
            return
        }

        guard let editor = ScreenshotEditor(image: nsImage, selectionRect: rect, screen: screen) else {
            showAlert(title: "截图失败", message: "无法打开截图编辑器，请重试。")
            return
        }
        editor.onFinish = { [weak self] data in self?.finishCapture(data) }
        editor.onClose = { [weak self] in self?.editor = nil }
        self.editor = editor
        editor.present()
    }

    private func finishCapture(_ data: Data) {
        guard let image = NSImage(data: data) else { return }
        let archiveURL = UserDefaults.standard
            .string(forKey: "screenshotArchiveWorkspace")
            .map(URL.init(fileURLWithPath:))

        if let archiveURL {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("瞬贴截图-\(UUID().uuidString).png")
            do {
                try data.write(to: tempURL, options: .atomic)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                store?.addScreenshot(at: tempURL, createdAt: Date(), archiveDirectory: archiveURL)
            } catch {
                store?.addClipboardImage(image, sourceApp: "瞬贴截图")
            }
        } else {
            store?.addClipboardImage(image, sourceApp: "瞬贴截图")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Publish the exact rendered PNG so pixel dimensions and annotations are preserved.
        pasteboard.setData(data, forType: .png)
        clipboardMonitor?.ignoreNextChange(pasteboard.changeCount)
    }

    private func dismissOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
