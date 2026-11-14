import Foundation
import CoreGraphics

/// Platform-independent representation of a connected display's usable area.
public struct ScreenDescriptor: Sendable, Equatable {
    public let displayUUID: String?
    public let visibleFrame: CGRect

    public init(displayUUID: String?, visibleFrame: CGRect) {
        self.displayUUID = displayUUID
        self.visibleFrame = visibleFrame
    }
}

/// Pure geometry helpers for placing and clamping shelf panels across monitors.
public enum DisplayPlacement {
    public static let defaultSize = CGSize(width: 320, height: 240)
    public static let minimumSize = CGSize(width: 240, height: 160)

    /// Resolves a persisted placement onto currently connected screens, ensuring the panel
    /// (and especially its header) is never off-screen after a monitor is disconnected.
    public static func resolveFrame(
        for placement: WindowPlacement?,
        screens: [ScreenDescriptor]
    ) -> CGRect {
        guard !screens.isEmpty else {
            return placement?.cgRect ?? CGRect(origin: CGPoint(x: 100, y: 100), size: defaultSize)
        }

        guard let placement else {
            return centeredFrame(size: defaultSize, in: screens[0].visibleFrame)
        }

        let desired = CGRect(
            x: placement.x,
            y: placement.y,
            width: max(placement.width, Double(minimumSize.width)),
            height: max(placement.height, Double(minimumSize.height))
        )

        if let targetUUID = placement.displayUUID,
           let matchedScreen = screens.first(where: { $0.displayUUID == targetUUID }) {
            return clamp(desired, into: matchedScreen.visibleFrame)
        }

        // Fall back to the screen with the largest intersection, or the primary screen.
        let bestScreen = screens.max(by: { a, b in
            let ia = a.visibleFrame.intersection(desired)
            let ib = b.visibleFrame.intersection(desired)
            let areaA = ia.isNull ? 0 : ia.width * ia.height
            let areaB = ib.isNull ? 0 : ib.width * ib.height
            return areaA < areaB
        }) ?? screens[0]

        return clamp(desired, into: bestScreen.visibleFrame)
    }

    /// Computes a placement near `cursorPoint` inside `screenVisibleFrame`.
    public static func frameNearCursor(
        _ cursorPoint: CGPoint,
        size: CGSize = defaultSize,
        in screenVisibleFrame: CGRect
    ) -> CGRect {
        let origin = CGPoint(
            x: cursorPoint.x - size.width / 2,
            y: cursorPoint.y - size.height / 2
        )
        return clamp(CGRect(origin: origin, size: size), into: screenVisibleFrame)
    }

    /// Clamps `rect` into `bounds`, preserving size up to `bounds` dimensions.
    public static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        let width = min(max(rect.width, minimumSize.width), bounds.width)
        let height = min(max(rect.height, minimumSize.height), bounds.height)

        let minX = bounds.minX
        let maxX = max(minX, bounds.maxX - width)
        let minY = bounds.minY
        let maxY = max(minY, bounds.maxY - height)

        let clampedX = min(max(rect.origin.x, minX), maxX)
        let clampedY = min(max(rect.origin.y, minY), maxY)

        return CGRect(x: clampedX, y: clampedY, width: width, height: height)
    }

    private static func centeredFrame(size: CGSize, in bounds: CGRect) -> CGRect {
        let origin = CGPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        return clamp(CGRect(origin: origin, size: size), into: bounds)
    }
}
