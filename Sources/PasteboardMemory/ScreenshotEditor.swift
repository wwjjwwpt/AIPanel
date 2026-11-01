import AppKit
import UniformTypeIdentifiers

enum AnnotationTool: Int, CaseIterable {
    case pen, rectangle, ellipse, arrow, text

    var title: String { ["画笔", "矩形", "圆圈", "箭头", "文字"][rawValue] }
}

struct ScreenshotAnnotation {
    let tool: AnnotationTool
    var points: [NSPoint]
    let color: NSColor
    let width: CGFloat
    var text = ""

    func draw() {
        guard let start = points.first, let end = points.last else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let rect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        switch tool {
        case .pen:
            path.move(to: start)
            if points.allSatisfy({ $0 == start }) {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: start.x - width / 2, y: start.y - width / 2,
                                          width: width, height: width)).fill()
            }
            for point in points.dropFirst() { path.line(to: point) }
        case .rectangle:
            path.appendRect(rect)
        case .ellipse:
            path.appendOval(in: rect)
        case .arrow:
            path.move(to: start)
            path.line(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = min(max(16, width * 4), hypot(end.x - start.x, end.y - start.y) * 0.4)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: end)
                path.line(to: NSPoint(x: end.x - head * cos(angle + offset),
                                      y: end.y - head * sin(angle + offset)))
            }
        case .text:
            let font = NSFont.systemFont(ofSize: max(20, width * 6), weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: start.x, y: max(0, start.y - size.height)),
                                    withAttributes: attrs)
        }
        path.stroke()
    }
}

/// Annotations use image pixel coordinates, independent of the preview's fitted size.
final class ScreenshotCanvas: NSView {
    let image: NSImage
    var tool: AnnotationTool = .pen
    var inkColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 4
    var onHistoryChange: (() -> Void)?
    private var annotations: [ScreenshotAnnotation] = []
    private var undone: [ScreenshotAnnotation] = []
    private var draft: ScreenshotAnnotation?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    private var imageRect: NSRect {
        let available = bounds.insetBy(dx: 24, dy: 24)
        let scale = max(0.001, min(available.width / image.size.width, available.height / image.size.height))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.concat()
        let scale = rect.width / image.size.width
        NSAffineTransform.transformForScale(scale).concat()
        drawImageAndAnnotations()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawImageAndAnnotations() {
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero,
                   operation: .copy, fraction: 1)
        for annotation in annotations { annotation.draw() }
        draft?.draw()
    }

    private func imagePoint(for event: NSEvent) -> NSPoint {
        let point = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        return NSPoint(x: min(image.size.width, max(0, (point.x - rect.minX) * image.size.width / rect.width)),
                       y: min(image.size.height, max(0, (point.y - rect.minY) * image.size.height / rect.height)))
    }

    override func mouseDown(with event: NSEvent) {
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        let point = imagePoint(for: event)
        if tool == .text {
            let alert = NSAlert()
            alert.messageText = "添加文字"
            alert.addButton(withTitle: "添加")
            alert.addButton(withTitle: "取消")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            field.placeholderString = "输入标注文字"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn,
               !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commit(ScreenshotAnnotation(tool: .text, points: [point], color: inkColor,
                                            width: strokeWidth, text: field.stringValue))
            }
            return
        }
        draft = ScreenshotAnnotation(tool: tool, points: [point], color: inkColor, width: strokeWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var annotation = draft else { return }
        let point = imagePoint(for: event)
        if annotation.tool == .pen || annotation.points.count == 1 {
            annotation.points.append(point)
        } else {
            annotation.points[1] = point
        }
        draft = annotation
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard draft != nil else { return }
        mouseDragged(with: event)
        guard let annotation = draft else { return }
        draft = nil
        commit(annotation)
    }

    func commit(_ annotation: ScreenshotAnnotation) {
        annotations.append(annotation)
        undone.removeAll()
        needsDisplay = true
        onHistoryChange?()
    }

    func undoAnnotation() {
        guard let last = annotations.popLast() else { return }
        undone.append(last)
        needsDisplay = true
        onHistoryChange?()
    }

    func redoAnnotation() {
        guard let last = undone.popLast() else { return }
        annotations.append(last)
        needsDisplay = true
        onHistoryChange?()
    }

    func pngData() -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawImageAndAnnotations()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension NSAffineTransform {
    static func transformForScale(_ scale: CGFloat) -> NSAffineTransform {
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        return transform
    }
}

@MainActor
final class ScreenshotEditor: NSWindowController, NSWindowDelegate {
    var onFinish: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private let canvas: ScreenshotCanvas
    private let undoButton = NSButton(title: "撤销", target: nil, action: nil)
    private let redoButton = NSButton(title: "重做", target: nil, action: nil)
    private var exportInProgress = false

    init?(image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixelImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        canvas = ScreenshotCanvas(image: pixelImage)
        let visible = (NSScreen.main?.visibleFrame.size) ?? NSSize(width: 1200, height: 800)
        let size = NSSize(width: min(1080, visible.width - 40), height: min(760, visible.height - 40))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "截图标注"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 420)
        window.delegate = self
        configureContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }

    private func configureContent() {
        guard let content = window?.contentView else { return }
        let tools = NSSegmentedControl(labels: AnnotationTool.allCases.map(\.title), trackingMode: .selectOne,
                                       target: self, action: #selector(changeTool(_:)))
        tools.selectedSegment = 0
        let color = NSColorWell()
        color.color = canvas.inkColor
        color.setAccessibilityLabel("标注颜色")
        color.target = self
        color.action = #selector(changeColor(_:))
        color.setFrameSize(NSSize(width: 44, height: 26))
        color.widthAnchor.constraint(equalToConstant: 44).isActive = true
        color.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let widths = NSPopUpButton()
        widths.addItems(withTitles: ["细", "中", "粗"])
        widths.setAccessibilityLabel("线条粗细")
        widths.selectItem(at: 1)
        widths.target = self
        widths.action = #selector(changeWidth(_:))
        configure(undoButton, action: #selector(undoStroke), key: "z")
        configure(redoButton, action: #selector(redoStroke), key: "z")
        redoButton.keyEquivalentModifierMask = [.command, .shift]
        let toolbar = NSStackView(views: [tools, color, widths, undoButton, redoButton])
        toolbar.spacing = 10
        let hint = NSTextField(labelWithString: "\(Int(canvas.image.size.width)) × \(Int(canvas.image.size.height)) 像素 · 选择工具后在截图上拖动，文字工具点击添加")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditing))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        let save = NSButton(title: "保存 PNG…", target: self, action: #selector(saveImage))
        configure(save, action: #selector(saveImage), key: "s")
        let copy = NSButton(title: "完成并复制", target: self, action: #selector(copyImage))
        configure(copy, action: #selector(copyImage), key: "c")
        let actions = NSStackView(views: [cancel, save, copy])
        actions.spacing = 10
        for view in [toolbar, canvas, hint, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            toolbar.bottomAnchor.constraint(equalTo: canvas.topAnchor, constant: -12),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -10),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            hint.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -10),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        canvas.onHistoryChange = { [weak self] in self?.updateHistoryButtons() }
        updateHistoryButtons()
    }

    private func configure(_ button: NSButton, action: Selector, key: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.keyEquivalent = key
        button.keyEquivalentModifierMask = .command
    }

    private func updateHistoryButtons() {
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
    }

    @objc private func changeTool(_ sender: NSSegmentedControl) {
        canvas.tool = AnnotationTool(rawValue: sender.selectedSegment) ?? .pen
    }
    @objc private func changeColor(_ sender: NSColorWell) { canvas.inkColor = sender.color }
    @objc private func changeWidth(_ sender: NSPopUpButton) { canvas.strokeWidth = [2, 4, 8][sender.indexOfSelectedItem] }
    @objc private func undoStroke() { canvas.undoAnnotation() }
    @objc private func redoStroke() { canvas.redoAnnotation() }
    @objc private func cancelEditing() { close() }

    @objc private func copyImage() {
        guard !exportInProgress, let data = renderedPNG() else { return }
        onFinish?(data)
        close()
    }

    @objc private func saveImage() {
        guard !exportInProgress, let window, let data = renderedPNG() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "瞬贴截图 \(formatter.string(from: Date())).png"
        exportInProgress = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.exportInProgress = false
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.onFinish?(data)
                self.close()
            } catch {
                self.showError("无法保存截图：\(error.localizedDescription)")
            }
        }
    }

    private func renderedPNG() -> Data? {
        guard let data = canvas.pngData() else {
            showError("无法生成截图，请重试。")
            return nil
        }
        return data
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "截图导出失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.orderOut(nil)
        onClose?()
    }
}
