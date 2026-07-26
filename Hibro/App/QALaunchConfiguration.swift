import CoreGraphics
import Foundation

enum QALaunchConfiguration {
    private static let viewportWidthFlag = "-hibro-qa-viewport-width"

    static var viewportWidth: CGFloat? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: viewportWidthFlag),
              arguments.indices.contains(flagIndex + 1),
              let value = Double(arguments[flagIndex + 1]),
              value >= 320
        else {
            return nil
        }
        return CGFloat(value)
#else
        return nil
#endif
    }

    static var horizontalSizeClass: QAHorizontalSizeClass? {
        guard let viewportWidth else { return nil }
        return viewportWidth < 600 ? .compact : .regular
    }
}

enum QAHorizontalSizeClass {
    case compact
    case regular
}
