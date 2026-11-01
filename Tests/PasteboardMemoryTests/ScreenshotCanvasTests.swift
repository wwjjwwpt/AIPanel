import AppKit

// Standalone AppKit regression checks; no Xcode or test framework required.
@main
struct ScreenshotCanvasTests {
    @MainActor
    static func main() throws {
        try testExportPreservesPixelsAndOrientationAtDifferentPreviewSizes()
        try testAnnotationCoordinatesUndoRedoAndNewBranch()
        try testAllToolsRenderIntoExport()
        try testToolbarStaysOnScreen()
        try testTransparentOverlayAndInlineText()
        print("PASS: pixel export, all tools, undo/redo, toolbar placement, transparent overlay, inline text")
    }

    private static func require<T>(_ value: T?, line: UInt = #line) throws -> T {
        guard let value else { throw CheckFailure.failed("Line \(line): Unexpected nil") }
        return value
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String = "Check failed",
                               line: UInt = #line) throws {
        guard value() else { throw CheckFailure.failed("Line \(line): \(message)") }
    }

    private enum CheckFailure: Error { case failed(String) }

    @MainActor
    private static func makeCanvas() -> ScreenshotCanvas {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        // Asymmetric source makes an accidental vertical flip visible.
        for y in 0..<200 {
            for x in 0..<400 { bitmap.setColor(NSColor(deviceRed: y < 100 ? 1 : 0, green: y < 100 ? 1 : 0, blue: 1, alpha: 1), atX: x, y: y) }
        }
        let image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: 400, height: 200))
        let canvas = ScreenshotCanvas(image: image)
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        return canvas
    }

    @MainActor
    static func testExportPreservesPixelsAndOrientationAtDifferentPreviewSizes() throws {
        let canvas = makeCanvas()
        let first = try require(canvas.pngData())
        let bitmap = try require(NSBitmapImageRep(data: first))
        try expect(bitmap.pixelsWide == 400)
        try expect(bitmap.pixelsHigh == 200)
        let top = try require(bitmap.colorAt(x: 200, y: 20)?.usingColorSpace(.sRGB))
        let bottom = try require(bitmap.colorAt(x: 200, y: 180)?.usingColorSpace(.sRGB))
        try expect(top.redComponent > 0.95)
        try expect(bottom.redComponent < 0.05)
        try expect(bottom.blueComponent > 0.95)
        canvas.frame.size = NSSize(width: 240, height: 160)
        try expect(first == canvas.pngData())
    }

    @MainActor
    static func testAnnotationCoordinatesUndoRedoAndNewBranch() throws {
        let canvas = makeCanvas()
        let original = try require(canvas.pngData())
        canvas.commit(ScreenshotAnnotation(tool: .rectangle,
                                          points: [NSPoint(x: 50, y: 120), NSPoint(x: 150, y: 180)],
                                          color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 8))
        let marked = try require(canvas.pngData())
        try expect(marked != original)
        let bitmap = try require(NSBitmapImageRep(data: marked))
        // y=150 in bottom-left canvas coordinates maps to y=50 in the bitmap.
        let stroke = try require(bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
        try expect(stroke.redComponent > 0.95)
        // Allow device RGB color management while distinguishing the stroke from white.
        try expect(stroke.greenComponent < 0.3)
        canvas.undoAnnotation()
        try expect(canvas.pngData() == original)
        try expect(canvas.canRedo)
        canvas.redoAnnotation()
        try expect(canvas.pngData() == marked)
        canvas.undoAnnotation()
        canvas.commit(ScreenshotAnnotation(tool: .ellipse,
                                          points: [NSPoint(x: 20, y: 20), NSPoint(x: 80, y: 80)],
                                          color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 4))
        try expect(!canvas.canRedo)
        canvas.undoAnnotation()
        try expect(!canvas.canUndo)
        try expect(canvas.pngData() == original)
    }

    @MainActor
    static func testAllToolsRenderIntoExport() throws {
        for tool in AnnotationTool.allCases {
            let canvas = makeCanvas()
            let original = try require(canvas.pngData())
            canvas.commit(ScreenshotAnnotation(tool: tool,
                                              points: [NSPoint(x: 40, y: 140), NSPoint(x: 180, y: 170)],
                                              color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 4, text: "截图标注"))
            try expect(canvas.pngData() != original, "\(tool.title) did not render")
        }
    }

    static func testToolbarStaysOnScreen() throws {
        let screen = NSRect(x: 8, y: 8, width: 1200, height: 760)
        let size = NSSize(width: 440, height: 90)
        for selection in [NSRect(x: 100, y: 300, width: 500, height: 200),
                          NSRect(x: 0, y: 0, width: 30, height: 30),
                          NSRect(x: 1180, y: 730, width: 30, height: 30),
                          NSRect(x: 0, y: 0, width: 1216, height: 800)] {
            let frame = ScreenshotEditorLayout.toolbarFrame(selection: selection, available: screen, size: size)
            try expect(screen.contains(frame))
            if selection.minY > size.height + 16 {
                try expect(frame.maxY < selection.minY)
            }
        }
    }

    @MainActor
    static func testTransparentOverlayAndInlineText() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let screen = try require(NSScreen.main)
        let source = makeCanvas().image
        source.size = NSSize(width: 200, height: 100) // Retina image: logical size differs from pixels.
        let selection = NSRect(x: 100, y: 200, width: 400, height: 200)
        let editor = try require(ScreenshotEditor(image: source, selectionRect: selection, screen: screen))
        let window = try require(editor.window)
        defer { editor.close() }
        try expect(!window.isOpaque)
        try expect(window.backgroundColor?.alphaComponent == 0)
        try expect(!window.styleMask.contains(.titled))
        try expect(!window.hasShadow)
        let content = try require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let canvas = try require(content.subviews.compactMap { $0 as? ScreenshotCanvas }.first)
        try expect(canvas.frame == selection)
        try expect(canvas.image.size == NSSize(width: 400, height: 200))
        let toolbar = try require(content.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        try expect(toolbar.frame.width > 300 && toolbar.frame.height > 50)
        try expect(!toolbar.frame.intersects(selection))
        try expect(!toolbar.hasAmbiguousLayout)

        canvas.tool = .text
        let click = try require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 180, y: 320),
                                                  modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let before = try require(canvas.pngData())
        canvas.mouseDown(with: click)
        let field = try require(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "原位标注"
        canvas.finishTextEditing()
        try expect(!canvas.subviews.contains { $0 is NSTextField })
        try expect(canvas.pngData() != before)
        canvas.undoAnnotation()
        try expect(canvas.pngData() == before)

        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try expect(bitmap.colorAt(x: bitmap.pixelsWide - 2, y: 2)?.alphaComponent == 0)
            let data = try require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: ".build/screenshot-overlay-preview.png"))
        }
    }
}
