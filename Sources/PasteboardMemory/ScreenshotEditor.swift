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
final class ScreenshotCanvas: NSView, NSTextFieldDelegate {
    let image: NSImage
    var tool: AnnotationTool = .pen
    var inkColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 4
    var onHistoryChange: (() -> Void)?
    private var annotations: [ScreenshotAnnotation] = []
    private var undone: [ScreenshotAnnotation] = []
    private var draft: ScreenshotAnnotation?
    private var textField: NSTextField?
    private var textAnnotation: ScreenshotAnnotation?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    private var imageRect: NSRect {
        let available = bounds
        let scale = max(0.001, min(available.width / image.size.width, available.height / image.size.height))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
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
            beginText(at: point)
            return
        }
        draft = ScreenshotAnnotation(tool: tool, points: [point], color: inkColor, width: strokeWidth)
        needsDisplay = true
    }

    private func beginText(at point: NSPoint) {
        finishTextEditing()
        let scale = imageRect.width / image.size.width
        let font = NSFont.systemFont(ofSize: max(20, strokeWidth * 6) * scale, weight: .semibold)
        let height = min(bounds.height, max(24, font.pointSize + 8))
        let x = min(max(0, point.x * scale), max(0, bounds.width - 160))
        let y = min(max(0, point.y * scale - height), max(0, bounds.height - height))
        let field = NSTextField(frame: NSRect(x: x, y: y,
                                              width: min(300, bounds.width - x), height: height))
        field.font = font
        field.textColor = inkColor
        field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.9)
        field.placeholderString = "输入文字，回车确认"
        field.delegate = self
        textAnnotation = ScreenshotAnnotation(tool: .text,
                                              points: [NSPoint(x: x / scale, y: (y + height) / scale)],
                                              color: inkColor, width: strokeWidth)
        textField = field
        addSubview(field)
        window?.makeFirstResponder(field)
    }

    func finishTextEditing(commitText: Bool = true) {
        guard let field = textField, var annotation = textAnnotation else { return }
        textField = nil
        textAnnotation = nil
        annotation.text = field.currentEditor()?.string ?? field.stringValue
        field.removeFromSuperview()
        if commitText && !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commit(annotation)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) { finishTextEditing() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
            commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEditing(commitText: commandSelector != #selector(NSResponder.cancelOperation(_:)))
            window?.makeFirstResponder(self)
            return true
        }
        return false
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
        finishTextEditing()
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

/// Places the toolbar beside the selection, keeping it within the display's usable bounds.
enum ScreenshotEditorLayout {
    static func toolbarFrame(selection: NSRect, available: NSRect, size: NSSize) -> NSRect {
        let margin: CGFloat = 8
        let width = min(size.width, available.width)
        let height = min(size.height, available.height)
        let x = min(max(selection.maxX - width, available.minX), available.maxX - width)
        let below = selection.minY - height - margin
        let above = selection.maxY + margin
        let y: CGFloat
        if below >= available.minY {
            y = below
        } else if above + height <= available.maxY {
            y = above
        } else {
            y = min(max(selection.minY + margin, available.minY), available.maxY - height)
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class ScreenshotEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ScreenshotEditor: NSWindowController, NSWindowDelegate {
    var onFinish: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private let canvas: ScreenshotCanvas
    private let selectionRect: NSRect
    private let availableRect: NSRect
    private let undoButton = NSButton(title: "撤销", target: nil, action: nil)
    private let redoButton = NSButton(title: "重做", target: nil, action: nil)
    private let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black]
    private var exportInProgress = false

    init?(image: NSImage, selectionRect: NSRect, screen: NSScreen) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixelImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        canvas = ScreenshotCanvas(image: pixelImage)
        self.selectionRect = selectionRect
        availableRect = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY).insetBy(dx: 8, dy: 8)
        let window = ScreenshotEditorWindow(contentRect: screen.frame, styleMask: .borderless,
                                            backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "截图标注"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        configureContent()
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
        // The captured image stays exactly where the user selected it. Only the toolbar has a background.
        canvas.frame = selectionRect
        canvas.wantsLayer = true
        canvas.layer?.borderWidth = 1
        canvas.layer?.borderColor = NSColor.controlAccentColor.cgColor
        content.addSubview(canvas)

        let tools = NSSegmentedControl(labels: AnnotationTool.allCases.map(\.title), trackingMode: .selectOne,
                                       target: self, action: #selector(changeTool(_:)))
        tools.selectedSegment = 0
        let palette = NSSegmentedControl()
        palette.segmentCount = colors.count
        palette.trackingMode = .selectOne
        palette.selectedSegment = 0
        palette.target = self
        palette.action = #selector(changeColor(_:))
        palette.setAccessibilityLabel("标注颜色：红、黄、绿、蓝、白、黑")
        for (index, color) in colors.enumerated() {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                color.setFill()
                let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                dot.fill()
                NSColor.gray.setStroke()
                dot.lineWidth = 0.5
                dot.stroke()
                return true
            }
            palette.setImage(image, forSegment: index)
            palette.setWidth(22, forSegment: index)
        }
        let widths = NSPopUpButton()
        widths.addItems(withTitles: ["细", "中", "粗"])
        widths.setAccessibilityLabel("线条粗细")
        widths.selectItem(at: 1)
        widths.target = self
        widths.action = #selector(changeWidth(_:))
        configure(undoButton, action: #selector(undoStroke), key: "z")
        configure(redoButton, action: #selector(redoStroke), key: "z")
        redoButton.keyEquivalentModifierMask = [.command, .shift]
        let toolsRow = NSStackView(views: [tools, undoButton, redoButton])
        toolsRow.spacing = 8
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditing))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        let save = NSButton(title: "保存…", target: self, action: #selector(saveImage))
        configure(save, action: #selector(saveImage), key: "s")
        let copy = NSButton(title: "完成", target: self, action: #selector(copyImage))
        configure(copy, action: #selector(copyImage), key: "c")
        copy.toolTip = "完成并复制（⌘C）"
        let optionsRow = NSStackView(views: [palette, widths, cancel, save, copy])
        optionsRow.spacing = 8
        let stack = NSStackView(views: [toolsRow, optionsRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let toolbar = NSVisualEffectView()
        toolbar.material = .popover
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 10
        toolbar.layer?.masksToBounds = true
        toolbar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -10),
        ])
        let size = NSSize(width: max(toolsRow.fittingSize.width, optionsRow.fittingSize.width) + 24,
                          height: toolsRow.fittingSize.height + optionsRow.fittingSize.height + 28)
        toolbar.frame = ScreenshotEditorLayout.toolbarFrame(selection: selectionRect, available: availableRect, size: size)
        content.addSubview(toolbar)
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
        canvas.finishTextEditing()
        canvas.tool = AnnotationTool(rawValue: sender.selectedSegment) ?? .pen
    }
    @objc private func changeColor(_ sender: NSSegmentedControl) { canvas.inkColor = colors[sender.selectedSegment] }
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
        onClose?()
    }
}
