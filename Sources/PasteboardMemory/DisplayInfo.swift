import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let isBuiltIn: Bool

    var resolution: String { "\(width) × \(height)" }
}

enum DisplayError: LocalizedError {
    case notEnoughDisplays
    case missingSource
    case configurationFailed(CGError)

    var errorDescription: String? {
        switch self {
        case .notEnoughDisplays:
            return "请至少连接两台显示器。"
        case .missingSource:
            return "主显示器已断开，请重新选择。"
        case .configurationFailed(let error):
            return "macOS 无法应用显示器配置（错误 \(error.rawValue)）。"
        }
    }
}
