import AppKit
import SwiftUI

struct MirrorTabView: View {
    @ObservedObject var store: DisplayStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: store.isMirroring ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.isMirroring ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text("显示器镜像").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(store.isMirroring ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .accessibilityLabel(store.isMirroring ? "镜像已开启" : "镜像已关闭")
        }
        .padding(16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.displays.count < 2 {
                VStack(spacing: 10) {
                    Image(systemName: "display")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("需要另一台显示器")
                        .font(.headline)
                    Text("连接外接显示器后即可设置镜像。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                displaySection(title: "主显示器") {
                    ForEach(store.displays) { display in
                        displayRow(display, selected: store.sourceID == display.id) {
                            store.chooseSource(display.id)
                        }
                    }
                }

                displaySection(title: "镜像到") {
                    ForEach(store.targets) { display in
                        Toggle(isOn: Binding(
                            get: { store.targetIDs.contains(display.id) },
                            set: { store.setTarget(display.id, selected: $0) }
                        )) {
                            displayLabel(display)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(store.isMirroring || store.isApplying)
                    }
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: store.toggleMirroring) {
                    HStack {
                        if store.isApplying { ProgressView().controlSize(.small) }
                        Text(store.isMirroring ? "关闭镜像" : "开启镜像")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isMirroring ? store.isApplying : !store.canStart)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("显示器设置…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusText: String {
        if store.displays.count < 2 { return "未检测到外接显示器" }
        if store.isMirroring, let source = store.source { return "正在镜像 · \(source.name)" }
        return "扩展显示模式"
    }

    private func displaySection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9, content: content)
        }
    }

    private func displayRow(_ display: DisplayInfo, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                displayLabel(display)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isMirroring || store.isApplying)
    }

    private func displayLabel(_ display: DisplayInfo) -> some View {
        HStack(spacing: 9) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name).lineLimit(1)
                Text(display.resolution).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
