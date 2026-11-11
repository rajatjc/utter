import UtterCore
import AppKit
import SwiftUI

// MARK: - Geometry

/// The notch (or, on screens without one, the top center of the menu bar).
struct NotchGeometry {
    var screenFrame: NSRect
    var centerX: CGFloat
    /// Width of the notch in points. About 185 pt at the default display scaling;
    /// narrower with "Larger Text", wider with "More Space".
    var width: CGFloat
    /// Height of the band the notch spans (the menu bar height on that screen).
    var bandHeight: CGFloat
    var hasNotch: Bool

    static func current() -> NotchGeometry {
        // The built-in display of a notched MacBook, wherever it sits in the arrangement
        // (it isn't the main screen when an external display is primary).
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched(frame: screen.frame, topInset: screen.safeAreaInsets.top,
                           leftWidth: screen.auxiliaryTopLeftArea?.width,
                           rightWidth: screen.auxiliaryTopRightArea?.width)
        }
        // No notch (iMac, Mac mini or Studio display, older MacBooks, lid closed).
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleTop = screen?.visibleFrame.maxY ?? frame.maxY - 24
        return NotchGeometry(screenFrame: frame, centerX: frame.midX, width: 185,
                             bandHeight: max(24, frame.maxY - visibleTop), hasNotch: false)
    }

    /// Uses only the widths of the menu bar areas either side of the notch, so it
    /// doesn't matter whether the screen sits at the origin or elsewhere in a
    /// multi-display arrangement.
    static func notched(frame: NSRect, topInset: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?) -> NotchGeometry {
        let notch = NotchLayout.notch(frameMinX: frame.minX, frameWidth: frame.width,
                                      leftWidth: leftWidth, rightWidth: rightWidth)
        return NotchGeometry(screenFrame: frame, centerX: notch.centerX, width: notch.width,
                             bandHeight: max(topInset, 20), hasNotch: true)
    }
}

// MARK: - Window

/// Borderless panel allowed to sit in the menu bar band (AppKit would otherwise
/// push it down into the visible area).
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
