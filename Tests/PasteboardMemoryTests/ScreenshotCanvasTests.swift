import AppKit

// Standalone AppKit regression checks; no Xcode or test framework required.
@main
struct ScreenshotCanvasTests {
    @MainActor
    static func main() throws {
        try testExportPreservesPixelsAndOrientationAtDifferentPreviewSizes()
        try testAnnotationCoordinatesUndoRedoAndNewBranch()
        try testAllToolsRenderIntoExport()
        print("PASS: original pixel dimensions, orientation, preview independence, annotation coordinates, undo/redo, all five tools")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure.failed("Unexpected nil") }
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
}
