import UtterCore
import AppKit
import SwiftUI

// MARK: - Geometry

/// The notch (or, on screens without one, the top center of the menu bar).
struct NotchGeometry {
    var screenFrame: NSRect
    var centerX: CGFloat
    /// Width of the physical notch (185 pt on current MacBooks).
    var width: CGFloat
    /// Height of the menu bar band, which the notch spans.
    var bandHeight: CGFloat
    var hasNotch: Bool

    static func current() -> NotchGeometry {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(
                screenFrame: screen.frame,
                centerX: (left.maxX + right.minX) / 2,
                width: right.minX - left.maxX,
                bandHeight: screen.safeAreaInsets.top, // exactly the notch's height
                hasNotch: true
            )
        }
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleTop = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.maxY ?? frame.maxY - 24
        return NotchGeometry(screenFrame: frame, centerX: frame.midX, width: 185,
                             bandHeight: max(24, frame.maxY - visibleTop), hasNotch: false)
    }
}

// MARK: - Window

/// Borderless panel allowed to sit in the menu bar band (AppKit would otherwise
/// push it down into the visible area).
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

