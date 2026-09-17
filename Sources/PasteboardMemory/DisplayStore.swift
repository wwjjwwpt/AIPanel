import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class DisplayStore: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published var sourceID: CGDirectDisplayID?
    @Published var targetIDs: Set<CGDirectDisplayID> = []
    @Published private(set) var isMirroring = false
    @Published private(set) var isApplying = false
    @Published var errorMessage: String?

    private let controller = DisplayController()
    private var callbackRegistered = false

    init() {
        refresh()
        registerDisplayCallback()
    }

    deinit {
        if callbackRegistered {
            CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    var source: DisplayInfo? { displays.first { $0.id == sourceID } }
    var targets: [DisplayInfo] { displays.filter { $0.id != sourceID } }
    var canStart: Bool { displays.count > 1 && sourceID != nil && !targetIDs.isEmpty && !isApplying }

    func chooseSource(_ id: CGDirectDisplayID) {
        sourceID = id
        UserDefaults.standard.set(Int(id), forKey: "mirror.sourceDisplayID")
        targetIDs.remove(id)
        if targetIDs.isEmpty {
            targetIDs = Set(displays.filter { $0.id != id }.map(\.id))
        }
    }

    func setTarget(_ id: CGDirectDisplayID, selected: Bool) {
        if selected { targetIDs.insert(id) } else { targetIDs.remove(id) }
    }

    func toggleMirroring() {
        guard let sourceID else {
            errorMessage = DisplayError.missingSource.localizedDescription
            return
        }
        isApplying = true
        errorMessage = nil
        do {
            try controller.setMirroring(enabled: !isMirroring, sourceID: sourceID, targetIDs: targetIDs)
            isMirroring.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isApplying = false
        refresh()
    }

    func refresh() {
        let latest = controller.connectedDisplays()
        displays = latest
        let mirrorConfiguration = controller.mirrorConfiguration(latest)
        isMirroring = mirrorConfiguration != nil

        let available = Set(latest.map(\.id))
        targetIDs = targetIDs.intersection(available)

        if let mirrorConfiguration {
            sourceID = mirrorConfiguration.source
            targetIDs = mirrorConfiguration.targets
        }

        if sourceID == nil || !available.contains(sourceID!) {
            let saved = UInt32(UserDefaults.standard.integer(forKey: "mirror.sourceDisplayID"))
            sourceID = available.contains(saved) ? saved : latest.first?.id
        }
        if let sourceID {
            targetIDs.remove(sourceID)
            if targetIDs.isEmpty && !isMirroring {
                targetIDs = Set(latest.filter { $0.id != sourceID }.map(\.id))
            }
        }
    }

    private func registerDisplayCallback() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        callbackRegistered = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, context) == .success
    }
}

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    let store = Unmanaged<DisplayStore>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in store.refresh() }
}
