import CoreGraphics
import Foundation

/// Converting between the three coordinate systems Snapboard deals with.
///
/// - Unit space: 0...1 over a screen's usable area, y down (layouts, the editor).
/// - AppKit (NSScreen, NSWindow): points, origin at the bottom-left of the main screen, y up.
/// - Accessibility (moving other apps' windows): points, origin at the top-left of the main
///   screen, y down.
public enum ScreenMath {
    /// A unit-space zone placed on a screen's usable area (`visibleFrame`, AppKit coordinates).
    public static func appKitRect(forUnit zone: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.minX + zone.minX * visibleFrame.width,
               y: visibleFrame.maxY - zone.maxY * visibleFrame.height,
               width: zone.width * visibleFrame.width,
               height: zone.height * visibleFrame.height).integral
    }

    /// An AppKit point as a unit-space point on that screen's usable area.
    public static func unitPoint(forAppKit point: CGPoint, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: (point.x - visibleFrame.minX) / max(visibleFrame.width, 1),
                y: (visibleFrame.maxY - point.y) / max(visibleFrame.height, 1))
    }

    /// An AppKit rect as the Accessibility API wants it. `mainScreenHeight` is the full height
    /// of the screen whose AppKit origin is (0, 0), i.e. `NSScreen.screens[0].frame.height`.
    public static func accessibilityRect(forAppKit rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The reverse of `accessibilityRect`.
    public static func appKitRect(forAccessibility rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Keeps a rect fully on a screen's usable area, moving it in first and shrinking it only if
    /// it is bigger than the screen. Used so no window or widget is ever left off-screen.
    public static func clamp(_ rect: CGRect, into area: CGRect) -> CGRect {
        let w = min(rect.width, area.width), h = min(rect.height, area.height)
        let x = min(max(rect.minX, area.minX), area.maxX - w)
        let y = min(max(rect.minY, area.minY), area.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// The invisible grid widgets line up on when dropped, like home-screen spots on a phone.
public struct WidgetGrid: Equatable {
    public var cell: CGFloat
    public var margin: CGFloat

    public init(cell: CGFloat = 8, margin: CGFloat = 16) {
        self.cell = cell
        self.margin = margin
    }

    /// The nearest grid position for a widget's frame on a screen (AppKit coordinates).
    /// The widget keeps its size, stays inside the screen with `margin` around it, and its
    /// top-left corner lands on the grid counted from the screen's top-left.
    public func snap(_ frame: CGRect, in area: CGRect) -> CGRect {
        let inner = area.insetBy(dx: margin, dy: margin)
        let left = (frame.minX - inner.minX) / cell
        let fromTop = (inner.maxY - frame.maxY) / cell
        let x = inner.minX + left.rounded() * cell
        let top = inner.maxY - fromTop.rounded() * cell
        let snapped = CGRect(x: x, y: top - frame.height, width: frame.width, height: frame.height)
        return ScreenMath.clamp(snapped, into: inner)
    }
}
