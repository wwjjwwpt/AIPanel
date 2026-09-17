import AppKit
import CoreGraphics

final class DisplayController {
    func connectedDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        let names: [CGDirectDisplayID: String] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return nil
                }
                return (CGDirectDisplayID(number.uint32Value), screen.localizedName)
            }
        )

        return ids.prefix(Int(count)).map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayInfo(
                id: id,
                name: names[id] ?? "显示器 \(id)",
                width: mode?.pixelWidth ?? Int(CGDisplayPixelsWide(id)),
                height: mode?.pixelHeight ?? Int(CGDisplayPixelsHigh(id)),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func isAnyDisplayMirrored(_ displays: [DisplayInfo]) -> Bool {
        displays.contains { CGDisplayIsInMirrorSet($0.id) != 0 }
    }

    func mirrorConfiguration(_ displays: [DisplayInfo]) -> (source: CGDirectDisplayID, targets: Set<CGDirectDisplayID>)? {
        var targets: Set<CGDirectDisplayID> = []
        var source: CGDirectDisplayID?

        for display in displays {
            let mirroredSource = CGDisplayMirrorsDisplay(display.id)
            if mirroredSource != kCGNullDirectDisplay {
                targets.insert(display.id)
                source = mirroredSource
            }
        }

        guard let source, !targets.isEmpty else { return nil }
        return (source, targets)
    }

    func setMirroring(enabled: Bool, sourceID: CGDirectDisplayID, targetIDs: Set<CGDirectDisplayID>) throws {
        let onlineIDs = Set(connectedDisplays().map(\.id))
        guard onlineIDs.count >= 2 else { throw DisplayError.notEnoughDisplays }
        guard onlineIDs.contains(sourceID) else { throw DisplayError.missingSource }

        var configuration: CGDisplayConfigRef?
        var result = CGBeginDisplayConfiguration(&configuration)
        guard result == .success, let configuration else {
            throw DisplayError.configurationFailed(result)
        }

        var shouldCancel = true
        defer {
            if shouldCancel { CGCancelDisplayConfiguration(configuration) }
        }

        // Clear existing mirror sets first so switching the source is deterministic.
        for id in onlineIDs {
            result = CGConfigureDisplayMirrorOfDisplay(configuration, id, kCGNullDirectDisplay)
            guard result == .success else { throw DisplayError.configurationFailed(result) }
        }

        if enabled {
            for id in targetIDs where id != sourceID && onlineIDs.contains(id) {
                result = CGConfigureDisplayMirrorOfDisplay(configuration, id, sourceID)
                guard result == .success else { throw DisplayError.configurationFailed(result) }
            }
        }

        result = CGCompleteDisplayConfiguration(configuration, .forSession)
        guard result == .success else { throw DisplayError.configurationFailed(result) }
        shouldCancel = false
    }
}
