// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

/// Proportions of the crop frame (lot 1).
public enum CropAspect: Sendable, Hashable, Codable {
    /// Any proportions.
    case free
    /// The proportions of the image (after the quarter turns).
    case original
    /// Width and height of a film format or of a custom ratio, as named:
    /// 6×7 is 6 wide and 7 high; `CropSettings.portrait` exchanges them (X).
    case ratio(width: Double, height: Double)

    /// The film formats offered in the menu, as named.
    public static let presets: [CropAspect] = [
        .ratio(width: 6, height: 4.5), .ratio(width: 6, height: 6), .ratio(width: 6, height: 7),
        .ratio(width: 6, height: 9), .ratio(width: 4, height: 5), .ratio(width: 24, height: 36),
    ]

    /// Width over height as named (the image's own for `original`); nil for free.
    public func namedRatio(imageRatio: Double) -> Double? {
        switch self {
        case .free: nil
        case .original: imageRatio
        case .ratio(let width, let height): width > 0 && height > 0 ? width / height : nil
        }
    }

    /// A ratio typed by the user; nil if not usable.
    public static func custom(_ a: Double, _ b: Double) -> CropAspect? {
        guard a.isFinite, b.isFinite, a > 0, b > 0, max(a, b) / min(a, b) <= 20 else { return nil }
        return .ratio(width: a, height: b)
    }
}

/// The crop part of the recipe: frame, proportions, lock, constraint.
///
/// `frame` is normalised (0...1) in the image *after the quarter turns and
/// mirror, before the fine angle*: the frame is upright on screen and the
/// image turns under it by `angle` about its centre. Physical units: a
/// preview pixel counts 3 times its width in height. This is also how a raw
/// developer describes a crop with an angle (pixels not turned), so it can
/// be written later as an instruction instead of resampled pixels.
public struct CropSettings: Sendable, Hashable, Codable {
    /// Fine angle in degrees, −45...45, positive clockwise on screen.
    public var angle: Double = 0 {
        didSet { angle = Self.clampedAngle(angle) }
    }
    /// The frame, normalised; nil: the whole image.
    public var frame: CGRect?
    public var aspect: CropAspect = .free
    /// Width and height of the proportions exchanged (key X).
    public var portrait = false
    /// The proportions are kept while resizing.
    public var locked = false
    /// The frame stays inside the turned image (no empty corners).
    public var constrained = true

    public static let angleRange: ClosedRange<Double> = -45...45
    /// Precision of the angle kept in the recipe: the straightening rule
    /// measures to the tenth (user's decision of 2026-11-20, lot 1b).
    public static let angleResolution = 0.1
    /// Step of the slider, the field and the arrow keys (lot 1b): whole degrees.
    public static let angleStep = 1.0
    /// Shift + arrow.
    public static let angleLargeStep = 5.0

    public init() {}

    private enum CodingKeys: String, CodingKey { case angle, frame, aspect, portrait, locked, constrained }
    private enum FrameKeys: String, CodingKey { case x, y, width, height }

    /// The frame is written as {x, y, width, height}, normalised.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(angle, forKey: .angle)
        if let frame {
            var nested = container.nestedContainer(keyedBy: FrameKeys.self, forKey: .frame)
            try nested.encode(frame.minX, forKey: .x)
            try nested.encode(frame.minY, forKey: .y)
            try nested.encode(frame.width, forKey: .width)
            try nested.encode(frame.height, forKey: .height)
        }
        try container.encode(aspect, forKey: .aspect)
        try container.encode(portrait, forKey: .portrait)
        try container.encode(locked, forKey: .locked)
        try container.encode(constrained, forKey: .constrained)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        angle = Self.clampedAngle(try container.decodeIfPresent(Double.self, forKey: .angle) ?? 0)
        if container.contains(.frame) {
            let nested = try container.nestedContainer(keyedBy: FrameKeys.self, forKey: .frame)
            frame = CGRect(x: try nested.decode(Double.self, forKey: .x), y: try nested.decode(Double.self, forKey: .y),
                           width: try nested.decode(Double.self, forKey: .width),
                           height: try nested.decode(Double.self, forKey: .height))
        }
        aspect = try container.decodeIfPresent(CropAspect.self, forKey: .aspect) ?? .free
        portrait = try container.decodeIfPresent(Bool.self, forKey: .portrait) ?? false
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        constrained = try container.decodeIfPresent(Bool.self, forKey: .constrained) ?? true
    }

    // MARK: Following the image's turns (lot 1, step F)

    /// The image is turned a quarter (clockwise or not): the frame turns with
    /// it, exactly (normalised coordinates), and the proportions are
    /// exchanged (6×7 becomes 7×6). The fine angle is unchanged: a quarter
    /// turn and a fine rotation about the same centre commute.
    public mutating func turnQuarter(clockwise: Bool) {
        if let frame {
            // Unit square, y down. Clockwise: (u, v) → (1 − v, u); counterclockwise: (u, v) → (v, 1 − u).
            self.frame = clockwise
                ? CGRect(x: 1 - frame.maxY, y: frame.minX, width: frame.height, height: frame.width)
                : CGRect(x: frame.minY, y: 1 - frame.maxX, width: frame.height, height: frame.width)
        }
        // The image's own proportions turn with the image; a named ratio is exchanged.
        if case .ratio = aspect { portrait.toggle() }
    }

    /// The image is mirrored left to right: the frame is mirrored and the
    /// fine angle changes sign.
    public mutating func mirrorHorizontally() {
        if let frame { self.frame = CGRect(x: 1 - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) }
        angle = -angle
    }

    /// Proportions chosen: their direction follows the frame's (or without a
    /// frame, the image's): a frame higher than wide stays so. A square
    /// ratio has no direction.
    public mutating func choose(_ aspect: CropAspect, imageSize: CGSize, currentFrame: CGRect?) {
        self.aspect = aspect
        portrait = false
        let reference = currentFrame ?? CGRect(origin: .zero, size: imageSize)
        guard reference.width > 0, reference.height > 0, imageSize.width > 0, imageSize.height > 0,
              let named = aspect.namedRatio(imageRatio: imageSize.width / imageSize.height),
              abs(named - 1) > 1e-9, abs(reference.width / reference.height - 1) > 1e-9 else { return }
        portrait = (named > 1) != (reference.width > reference.height)
    }

    /// Width over height of the frame the proportions ask for; nil: free.
    /// `imageSize`: the oriented image, physical units.
    public func ratio(imageSize: CGSize) -> Double? {
        guard imageSize.width > 0, imageSize.height > 0,
              let named = aspect.namedRatio(imageRatio: imageSize.width / imageSize.height) else { return nil }
        return portrait ? 1 / named : named
    }

    /// The frame used for the image, normalised: the frame drawn, or with an
    /// angle and the constraint on, the largest frame without empty corners;
    /// nil: the whole image.
    /// A frame drawn is also kept inside the turned image here (constraint
    /// on), so that a recipe read from a file never gives empty corners.
    public func effectiveFrame(imageSize: CGSize) -> CGRect? {
        if let frame {
            guard angle != 0, constrained, imageSize.width > 0, imageSize.height > 0 else { return frame }
            let physical = CGRect(x: frame.minX * imageSize.width, y: frame.minY * imageSize.height,
                                  width: frame.width * imageSize.width, height: frame.height * imageSize.height)
            let inside = CropGeometry.constrained(physical, imageSize: imageSize, angle: angle)
            return CGRect(x: inside.minX / imageSize.width, y: inside.minY / imageSize.height,
                          width: inside.width / imageSize.width, height: inside.height / imageSize.height)
        }
        guard angle != 0, constrained, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let largest = CropGeometry.largestFrame(ratio: ratio(imageSize: imageSize), imageSize: imageSize, angle: angle)
        return CGRect(x: largest.minX / imageSize.width, y: largest.minY / imageSize.height,
                      width: largest.width / imageSize.width, height: largest.height / imageSize.height)
    }

    public static func clampedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        // Tenths, divided rather than multiplied: 0.3, not 0.30000000000000004, in the recipe.
        let rounded = (value / angleResolution).rounded() / (1 / angleResolution)
        return min(max(rounded, angleRange.lowerBound), angleRange.upperBound)
    }

    /// An arrow key (lot 1b, user's decisions of 2026-11-20): the next
    /// multiple of `delta` in its direction. With 1°, from −1.3°, → gives −1°
    /// and ← gives −2°; with 5° (Shift), → gives 0°, then 5°.
    public static func nudgedAngle(_ angle: Double, by delta: Double) -> Double {
        let step = abs(delta)
        guard step > 0, angle.isFinite else { return clampedAngle(angle) }
        // A tiny margin: a value already on a multiple (computed as −1.1102e-16) moves a whole step.
        let next = delta > 0 ? ((angle + 1e-9) / step).rounded(.down) * step + step
                             : ((angle - 1e-9) / step).rounded(.up) * step - step
        return clampedAngle(next) + 0  // + 0: never −0 in the recipe
    }

    /// Nothing to do: no angle, no frame.
    public var isIdentity: Bool { angle == 0 && frame == nil }
}

/// Geometry of a frame over an image turned by a fine angle, in physical
/// units (the oriented image is `imageSize`, origin top left, y down).
public enum CropGeometry {
    /// The frame's corners are all inside the image turned by `angle` degrees
    /// (clockwise) about its centre.
    public static func fits(_ frame: CGRect, imageSize: CGSize, angle: Double, tolerance: Double = 1e-6) -> Bool {
        let center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let radians = -angle * .pi / 180  // back into the image's own axes
        let c = cos(radians), s = sin(radians)
        let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)]
        return corners.allSatisfy { point in
            let dx = point.x - center.x, dy = point.y - center.y
            let x = center.x + dx * c - dy * s
            let y = center.y + dx * s + dy * c
            return x >= -tolerance && y >= -tolerance
                && x <= imageSize.width + tolerance && y <= imageSize.height + tolerance
        }
    }

    /// The largest frame of `ratio` (width / height; nil: the image's own
    /// proportions) centred in the image turned by `angle`, without empty corners.
    public static func largestFrame(ratio: Double?, imageSize: CGSize, angle: Double) -> CGRect {
        let radians = abs(angle) * .pi / 180
        let c = cos(radians), s = sin(radians)
        let w = imageSize.width, h = imageSize.height
        let r = ratio ?? (w / h)
        // A centred frame fits iff its turned bounding box fits:
        //   fw·c + fh·s ≤ W and fw·s + fh·c ≤ H, with fw = r·fh.
        let height = min(w / (r * c + s), h / (r * s + c))
        let width = r * height
        return CGRect(x: (w - width) / 2, y: (h - height) / 2, width: width, height: height)
    }

    /// `frame` brought inside the turned image: first moved the least it
    /// takes (along the edge it passes: across only, then along only, then
    /// towards the centre), then, if too large, shrunk about the image's
    /// centre (proportions kept).
    public static func constrained(_ frame: CGRect, imageSize: CGSize, angle: Double) -> CGRect {
        if fits(frame, imageSize: imageSize, angle: angle) { return frame }
        let center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let toCentre = CGVector(dx: center.x - frame.midX, dy: center.y - frame.midY)
        // Candidate directions, the smallest move first that fits along each.
        let directions = [CGVector(dx: toCentre.dx, dy: 0), CGVector(dx: 0, dy: toCentre.dy), toCentre]
        var best: CGRect?
        var bestDistance = Double.infinity
        for direction in directions where direction.dx != 0 || direction.dy != 0 {
            func moved(_ t: Double) -> CGRect { frame.offsetBy(dx: direction.dx * t, dy: direction.dy * t) }
            guard fits(moved(1), imageSize: imageSize, angle: angle) else { continue }
            var low = 0.0, high = 1.0
            for _ in 0..<50 {
                let middle = (low + high) / 2
                if fits(moved(middle), imageSize: imageSize, angle: angle) { high = middle } else { low = middle }
            }
            let distance = high * (direction.dx * direction.dx + direction.dy * direction.dy).squareRoot()
            if distance < bestDistance {
                bestDistance = distance
                best = moved(high)
            }
        }
        if let best { return best }
        // Too large even centred: shrink about the image centre.
        let centred = frame.offsetBy(dx: toCentre.dx, dy: toCentre.dy)
        var low = 0.0, high = 1.0
        for _ in 0..<50 {
            let middle = (low + high) / 2
            let candidate = centred.insetBy(dx: centred.width * (1 - middle) / 2, dy: centred.height * (1 - middle) / 2)
            if fits(candidate, imageSize: imageSize, angle: angle) { low = middle } else { high = middle }
        }
        return centred.insetBy(dx: centred.width * (1 - low) / 2, dy: centred.height * (1 - low) / 2)
    }

    /// A corner dragged to `point` while the opposite corner `fixed` stays
    /// put; `imageSize` and `angle` give the region the frame must fit in
    /// (the image turned by `angle`; 0 for the image itself).
    ///
    /// - The frame keeps the side of `fixed` given by `direction` (the signs
    ///   of the dragged corner minus `fixed`): a corner pulled past `fixed`
    ///   stops at the smallest frame instead of flipping over.
    /// - Each side is at least `minimumSide` (the shorter side, with
    ///   proportions), unless the room left from `fixed` is smaller: then
    ///   the largest frame that fits there.
    /// - Where the frame asked for does not fit, it grows only as far as it
    ///   still fits: with proportions, both sides together; free, both
    ///   together, then the width alone, then the height alone (along the
    ///   edge reached).
    /// - A `fixed` point outside the region (a new frame started in an empty
    ///   corner of the turned image, or off the image) is first brought to
    ///   the nearest place inside it.
    public static func resized(fixed: CGPoint, to point: CGPoint, direction: CGVector, ratio: Double?,
                               minimumSide: Double, imageSize: CGSize, angle: Double) -> CGRect {
        func fits(_ rect: CGRect) -> Bool { Self.fits(rect, imageSize: imageSize, angle: angle) }
        var fixed = fixed
        if !fits(CGRect(origin: fixed, size: .zero)) {
            fixed = constrained(CGRect(origin: fixed, size: .zero), imageSize: imageSize, angle: angle).origin
        }
        let sx: Double = direction.dx < 0 ? -1 : 1, sy: Double = direction.dy < 0 ? -1 : 1
        func rect(_ width: Double, _ height: Double) -> CGRect {
            CGRect(x: sx > 0 ? fixed.x : fixed.x - width, y: sy > 0 ? fixed.y : fixed.y - height,
                   width: width, height: height)
        }
        /// The largest t in 0...1 for which `make(t)` fits; `make(0)` fits.
        func largest(_ make: (Double) -> CGRect) -> Double {
            if fits(make(1)) { return 1 }
            var low = 0.0, high = 1.0
            for _ in 0..<50 {
                let middle = (low + high) / 2
                if fits(make(middle)) { low = middle } else { high = middle }
            }
            return low
        }
        let ratio = ratio.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        var minWidth = minimumSide, minHeight = minimumSide
        if let ratio { (minWidth, minHeight) = ratio >= 1 ? (minimumSide * ratio, minimumSide) : (minimumSide, minimumSide / ratio) }
        // Less room than the minimum from `fixed`: the largest frame that fits there.
        let room = largest { rect(minWidth * $0, minHeight * $0) }
        minWidth *= room
        minHeight *= room

        var width = max(sx * (point.x - fixed.x), 0), height = max(sy * (point.y - fixed.y), 0)
        if let ratio {
            if width / max(height, 1e-12) > ratio { height = width / ratio } else { width = height * ratio }
            if width < minWidth { width = minWidth; height = minHeight }
        } else {
            width = max(width, minWidth)
            height = max(height, minHeight)
        }
        let t = largest { rect(minWidth + (width - minWidth) * $0, minHeight + (height - minHeight) * $0) }
        var fitWidth = minWidth + (width - minWidth) * t, fitHeight = minHeight + (height - minHeight) * t
        if ratio == nil {
            let w = largest { rect(fitWidth + (width - fitWidth) * $0, fitHeight) }
            fitWidth += (width - fitWidth) * w
            let h = largest { rect(fitWidth, fitHeight + (height - fitHeight) * $0) }
            fitHeight += (height - fitHeight) * h
        }
        return rect(fitWidth, fitHeight)
    }

    /// `frame` changed to `ratio` (width / height), same centre, same area
    /// as far as possible.
    public static func reshaped(_ frame: CGRect, ratio: Double) -> CGRect {
        let area = frame.width * frame.height
        let height = (area / ratio).squareRoot(), width = height * ratio
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }
}

/// The straightening rule: a line drawn along what should be horizontal or vertical.
public enum Straighten {
    public enum Axis: Sendable, Hashable { case horizontal, vertical }

    /// The angle (degrees, clockwise positive, as `CropSettings.angle`) that
    /// makes the line from `a` to `b` (display coordinates, y down)
    /// horizontal or vertical, whichever is nearer; nil for a line too short.
    public static func correction(from a: CGPoint, to b: CGPoint, minimumLength: Double = 4)
        -> (angle: Double, axis: Axis)? {
        let dx = b.x - a.x, dy = b.y - a.y
        guard (dx * dx + dy * dy).squareRoot() >= minimumLength else { return nil }
        // Direction of the line, in degrees, y down: positive leans clockwise.
        var direction = atan2(dy, dx) * 180 / .pi
        // A line has no arrow: fold into (−90, 90].
        if direction > 90 { direction -= 180 } else if direction <= -90 { direction += 180 }
        if abs(direction) <= 45 {
            return (CropSettings.clampedAngle(-direction), .horizontal)
        }
        let fromVertical = direction > 0 ? direction - 90 : direction + 90
        return (CropSettings.clampedAngle(-fromVertical), .vertical)
    }
}
