import CoreGraphics

/// Where the notch is on a screen, from the widths of the menu bar areas either
/// side of it. Uses widths only, so the result is right wherever the screen sits
/// in a multi-display arrangement (its frame can start at any x).
public enum NotchLayout {
    public static let defaultWidth: CGFloat = 185

    public static func notch(frameMinX: CGFloat, frameWidth: CGFloat,
                             leftWidth: CGFloat?, rightWidth: CGFloat?) -> (centerX: CGFloat, width: CGFloat) {
        if let left = leftWidth, let right = rightWidth {
            let measured = frameWidth - left - right
            if measured > 60, measured < frameWidth / 2 { // ignore nonsense values
                return (frameMinX + left + measured / 2, measured)
            }
        }
        return (frameMinX + frameWidth / 2, defaultWidth)
    }
}
