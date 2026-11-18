// SPDX-License-Identifier: MIT

/// The code on a holder's leading edge, as one CCD line shows it
/// (docs/protocol.md §13): bright bars of equal width at a regular pitch.
/// Counting slots in pitches from the first bar, slots 0-3, 5, 6 and 16 are
/// bright on every holder seen and slot 4 is dark [confirmed, eight
/// holders]; slots 7-15 carry the code. What the bits mean is a
/// [hypothesis]: callers should only match a code against the codes of
/// known holders, and treat an empty code (frame only, no code bar: never
/// seen) as unknown. There is no redundancy: one bar lost changes the code.
///
/// Meant for the one-line read that follows the detection window of a
/// session (§13), not for image lines.
public struct HolderCode: Sendable, Hashable, CustomStringConvertible {
    /// Bright slots among 7...15.
    public let slots: Set<Int>

    public init(slots: Set<Int>) {
        self.slots = slots
    }

    public static let codeSlots = 7...15
    /// Slots bright on every holder seen.
    public static let frameSlots: Set<Int> = [0, 1, 2, 3, 5, 6, 16]
    /// Largest distance from the grid accepted, in pitches.
    static let gridTolerance = 0.25

    public var description: String { slots.sorted().map(String.init).joined(separator: ",") }

    /// Decodes one line of RGB samples (exactly `pixels` × 3, as read).
    /// Returns nil when the line does not show the code's frame (no holder
    /// edge on that line, or an unknown pattern).
    public static func decode(rgb samples: [UInt16], pixels: Int) -> HolderCode? {
        guard pixels > 0, samples.count == pixels * 3 else { return nil }
        let green = (0..<pixels).map { Double(samples[$0 * 3 + 1]) }
        // 5th and 95th percentiles: one hot or dead pixel does not move the threshold.
        let sorted = green.sorted()
        let low = sorted[sorted.count / 20], high = sorted[sorted.count * 19 / 20]
        guard high > 4 * max(low, 1) else { return nil }
        let threshold = (low + high) / 2

        // Bright runs: (start, length).
        var runs: [(start: Int, length: Int)] = []
        var start: Int?
        for (index, value) in green.enumerated() {
            if value > threshold {
                if start == nil { start = index }
            } else if let first = start {
                runs.append((first, index - first))
                start = nil
            }
        }
        if let first = start { runs.append((first, pixels - first)) }
        // A run much shorter than the typical bar is noise (a hot pixel), not a bar.
        if !runs.isEmpty {
            let median = runs.map(\.length).sorted()[runs.count / 2]
            runs.removeAll { $0.length * 3 < median }
        }
        guard runs.count >= frameSlots.count, runs.count <= 17 else { return nil }

        // The first bar is slot 0 and the last slot 16 (both frame slots):
        // the pitch from the whole span, then every bar must sit on the grid.
        let pitch = Double(runs[runs.count - 1].start - runs[0].start) / 16
        guard pitch > 2 else { return nil }
        let width = runs[0].length
        var bright = Set<Int>()
        for run in runs {
            guard abs(run.length - width) <= max(2, width / 5) else { return nil }
            let position = Double(run.start - runs[0].start) / pitch
            let slot = Int(position.rounded())
            guard abs(position - Double(slot)) < gridTolerance, (0...16).contains(slot),
                  bright.insert(slot).inserted else { return nil }
        }
        guard frameSlots.isSubset(of: bright), !bright.contains(4) else { return nil }
        return HolderCode(slots: bright.intersection(Set(codeSlots)))
    }
}
