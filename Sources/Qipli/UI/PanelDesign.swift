import AppKit
import SwiftUI

/// Shared rhythm for the two camera-black clipboard panels.
enum PanelDesign {
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let contentInset: CGFloat = 20
    static let cardGap: CGFloat = 12
    static let revealDuration: TimeInterval = 0.56
    static let collapseDuration: TimeInterval = 0.32
    static let dismissDuration: TimeInterval = 0.26
    static let feedbackDuration: TimeInterval = 0.12
    static let cardFill = Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 1))
    static let controlFill = Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1))
    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.18, 1, 0.30, 1)
    }
}

/// The shell meets the physical display edge. Dock space belongs inside the
/// black shell; interactive content stays in the usable display area.
enum PanelEdgeGeometry {
    static let sideWidth: CGFloat = 360

    static func expandedFrame(edge: PanelEdge, screenFrame: NSRect? = nil, visibleFrame: NSRect, isStack: Bool) -> NSRect {
        let size = edge.isVertical
            ? NSSize(width: sideWidth, height: isStack ? 580 : 640)
            : (isStack ? TopNotchHistoryGeometry.pasteStackPanelSize : TopNotchHistoryGeometry.defaultPanelSize)
        return frame(edge: edge, screenFrame: screenFrame, visibleFrame: visibleFrame, size: size)
    }

    static func reservedEdgeInset(edge: PanelEdge, screenFrame: NSRect, visibleFrame: NSRect) -> CGFloat {
        switch edge {
        case .top: max(0, screenFrame.maxY - visibleFrame.maxY)
        case .bottom: max(0, visibleFrame.minY - screenFrame.minY)
        case .left: max(0, visibleFrame.minX - screenFrame.minX)
        case .right: max(0, screenFrame.maxX - visibleFrame.maxX)
        }
    }

    static func frame(edge: PanelEdge, screenFrame: NSRect? = nil, visibleFrame: NSRect, size: NSSize) -> NSRect {
        let screen = screenFrame ?? visibleFrame
        let reserved = reservedEdgeInset(edge: edge, screenFrame: screen, visibleFrame: visibleFrame)
        let width = max(1, min(size.width, visibleFrame.width)) + (edge.isVertical ? reserved : 0)
        let height = max(1, min(size.height, visibleFrame.height)) + (edge.isVertical ? 0 : reserved)
        let x: CGFloat = edge == .left ? screen.minX : edge == .right ? screen.maxX - width : visibleFrame.midX - width / 2
        let y: CGFloat = edge == .bottom ? screen.minY : edge == .top ? screen.maxY - height : visibleFrame.midY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func compactGeometry(edge: PanelEdge, screenFrame: NSRect? = nil, visibleFrame: NSRect) -> PasteStackCompactGeometry {
        let frame = frame(edge: edge, screenFrame: screenFrame, visibleFrame: visibleFrame, size: NSSize(width: 196, height: 60))
        let usable = frame.intersection(visibleFrame)
        let content = usable.insetBy(dx: min(20, usable.width / 4), dy: min(12, usable.height / 4))
        let leftWidth = content.width * 0.60
        return PasteStackCompactGeometry(
            panelFrame: frame,
            leftContentRect: NSRect(x: content.minX, y: content.minY, width: leftWidth, height: content.height),
            rightContentRect: NSRect(x: content.minX + leftWidth, y: content.minY, width: content.width - leftWidth, height: content.height),
            isNotched: false
        )
    }

    static func collapsedFrame(edge: PanelEdge, expandedFrame: NSRect) -> NSRect {
        switch edge {
        case .top:
            NSRect(x: expandedFrame.midX - 64, y: expandedFrame.maxY - 2, width: 128, height: 2)
        case .bottom:
            NSRect(x: expandedFrame.midX - 64, y: expandedFrame.minY, width: 128, height: 2)
        case .left:
            NSRect(x: expandedFrame.minX, y: expandedFrame.midY - 64, width: 2, height: 128)
        case .right:
            NSRect(x: expandedFrame.maxX - 2, y: expandedFrame.midY - 64, width: 2, height: 128)
        }
    }

    /// AppKit screen coordinates are bottom-up; the surface mask is flipped.
    static func localRect(_ screenRect: NSRect, in expandedFrame: NSRect) -> CGRect {
        CGRect(x: screenRect.minX - expandedFrame.minX,
               y: expandedFrame.maxY - screenRect.maxY,
               width: screenRect.width, height: screenRect.height)
    }
}

/// One continuous contour, rotated toward the selected edge. The two-point
/// overscan keeps the attachment opaque even at fractional backing pixels.
enum PanelLiquidContour {
    static func path(in rect: CGRect, edge: PanelEdge, compact: Bool = false) -> CGPath {
        guard !rect.isEmpty, !rect.isNull else { return CGMutablePath() }
        let canonical = CGRect(origin: .zero, size: edge.isVertical
            ? CGSize(width: rect.height, height: rect.width) : rect.size)
        let path = TopNotchHistorySurfaceView.surfacePath(in: canonical,
            topCornerRadius: compact ? 8 : 24,
            bottomCornerRadius: compact ? 10 : 32, edgeBleed: 2)
        var transform: CGAffineTransform
        switch edge {
        case .top: transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        case .bottom: transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: rect.minX, ty: rect.maxY)
        case .left: transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: rect.minX, ty: rect.minY)
        case .right: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.maxX, ty: rect.minY)
        }
        return path.copy(using: &transform) ?? path
    }
}

/// Spread leads a lightly underdamped depth response on entry. The free edge
/// stretches once, then settles; the attachment never moves. A small transparent
/// allowance inside the window keeps that stretch from clipping into a flat edge.
enum PanelLiquidMotion {
    static func restingRect(in bounds: CGRect, edge: PanelEdge) -> CGRect {
        let depth = edge.isVertical ? bounds.width : bounds.height
        let allowance = max(0, depth * 0.02)
        switch edge {
        case .top: return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height - allowance)
        case .bottom: return CGRect(x: bounds.minX, y: bounds.minY + allowance, width: bounds.width, height: bounds.height - allowance)
        case .left: return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width - allowance, height: bounds.height)
        case .right: return CGRect(x: bounds.minX + allowance, y: bounds.minY, width: bounds.width - allowance, height: bounds.height)
        }
    }

    static func paths(from source: CGPath, to target: CGPath, edge: PanelEdge, expanding: Bool) -> [CGPath] {
        let start = elements(in: source)
        let end = elements(in: target)
        guard start.count == end.count,
              zip(start, end).allSatisfy({ $0.type == $1.type }) else { return [source, target] }
        return (0...60).map { sample in
            if sample == 0 { return source }
            if sample == 60 { return target }
            let time = Double(sample) / 60
            let spread = response(time, rate: expanding ? 12 : 7.5)
            let depth = expanding ? settlingResponse(time) : response(time, rate: 12)
            let x = edge.isVertical ? depth : spread
            let y = edge.isVertical ? spread : depth
            let path = CGMutablePath()
            for (a, b) in zip(start, end) {
                let points = zip(a.points, b.points).map { from, to in
                    CGPoint(x: from.x + (to.x - from.x) * x,
                            y: from.y + (to.y - from.y) * y)
                }
                switch a.type {
                case .moveToPoint: path.move(to: points[0])
                case .addLineToPoint: path.addLine(to: points[0])
                case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
                case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
                case .closeSubpath: path.closeSubpath()
                @unknown default: break
                }
            }
            return path
        }
    }

    private static func response(_ time: Double, rate: Double) -> CGFloat {
        let progress = 1 - (1 + rate * time) * exp(-rate * time)
        let endpoint = 1 - (1 + rate) * exp(-rate)
        return CGFloat(progress / endpoint)
    }

    private static func settlingResponse(_ time: Double) -> CGFloat {
        // About 1.3% peak extension, one return, no repeated bounce. Normalize
        // the tail so interruptible keyframes land exactly on the resting path.
        func spring(_ t: Double) -> Double {
            1 - exp(-6.5 * t) * (cos(4.8 * t) + (6.5 / 4.8) * sin(4.8 * t))
        }
        return CGFloat(spring(time) / spring(1))
    }

    private struct Element {
        let type: CGPathElementType
        let points: [CGPoint]
    }

    private static func elements(in path: CGPath) -> [Element] {
        var result: [Element] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            result.append(Element(type: element.type, points: Array(UnsafeBufferPointer(start: element.points, count: count))))
        }
        return result
    }
}

struct PanelControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 30, height: 30)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: PanelDesign.controlRadius, style: .continuous)
                    .fill(isHovered || configuration.isPressed ? PanelDesign.controlFill : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: PanelDesign.controlRadius))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: PanelDesign.feedbackDuration), value: configuration.isPressed)
            .animation(.easeOut(duration: PanelDesign.feedbackDuration), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
