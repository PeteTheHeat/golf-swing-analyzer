import AVFoundation
import Foundation

/// A frame-snapped, bounded section of one imported video.
///
/// All mutation methods preserve these invariants:
/// `0 <= start < end <= assetDuration` and
/// `minimumDuration <= duration <= maximumDuration` whenever the asset is not
/// empty. If an asset is shorter than the requested minimum, the whole asset is
/// the only valid selection.
public struct TrimSelection: Equatable, Sendable {
    public static let defaultMinimumDuration: TimeInterval = 1
    public static let defaultMaximumDuration: TimeInterval = 12

    public let assetDuration: TimeInterval
    public let frameDuration: TimeInterval
    public let minimumDuration: TimeInterval
    public let maximumDuration: TimeInterval

    public private(set) var start: TimeInterval
    public private(set) var end: TimeInterval

    public init(
        assetDuration: TimeInterval,
        frameDuration: TimeInterval = 1 / 30,
        minimumDuration requestedMinimum: TimeInterval = Self.defaultMinimumDuration,
        maximumDuration requestedMaximum: TimeInterval = Self.defaultMaximumDuration,
        start requestedStart: TimeInterval = 0,
        end requestedEnd: TimeInterval? = nil
    ) {
        let safeAssetDuration = Self.nonnegativeFinite(assetDuration)
        let safeFrameDuration = Self.positiveFinite(frameDuration) ?? (1 / 30)
        let safeMinimum = Self.nonnegativeFinite(requestedMinimum)
        let safeMaximum = max(Self.nonnegativeFinite(requestedMaximum), safeMinimum)

        self.assetDuration = safeAssetDuration
        self.frameDuration = safeFrameDuration

        if safeAssetDuration == 0 {
            self.minimumDuration = 0
            self.maximumDuration = 0
            self.start = 0
            self.end = 0
            return
        }

        let minimumOnFrameGrid = ceil(safeMinimum / safeFrameDuration) * safeFrameDuration
        let effectiveMinimum = min(
            safeAssetDuration,
            max(minimumOnFrameGrid, min(safeFrameDuration, safeAssetDuration))
        )
        let maximumOnFrameGrid = floor(safeMaximum / safeFrameDuration) * safeFrameDuration
        let effectiveMaximum = min(
            safeAssetDuration,
            max(effectiveMinimum, maximumOnFrameGrid)
        )

        self.minimumDuration = effectiveMinimum
        self.maximumDuration = effectiveMaximum
        self.start = 0
        self.end = min(safeAssetDuration, effectiveMaximum)

        setRange(
            start: requestedStart,
            end: requestedEnd ?? min(safeAssetDuration, effectiveMaximum)
        )
    }

    public init(
        video: ImportedVideo,
        minimumDuration: TimeInterval = Self.defaultMinimumDuration,
        maximumDuration: TimeInterval = Self.defaultMaximumDuration
    ) {
        self.init(
            assetDuration: video.durationSeconds,
            frameDuration: video.frameDurationSeconds,
            minimumDuration: minimumDuration,
            maximumDuration: maximumDuration
        )
    }

    public var duration: TimeInterval {
        max(0, end - start)
    }

    public var startTime: CMTime {
        CMTime(seconds: start, preferredTimescale: 60_000)
    }

    public var endTime: CMTime {
        CMTime(seconds: end, preferredTimescale: 60_000)
    }

    public var timeRange: CMTimeRange {
        CMTimeRange(start: startTime, end: endTime)
    }

    public var normalizedStart: Double {
        guard assetDuration > 0 else { return 0 }
        return start / assetDuration
    }

    public var normalizedEnd: Double {
        guard assetDuration > 0 else { return 0 }
        return end / assetDuration
    }

    public var isValid: Bool {
        guard assetDuration > 0 else { return false }
        let tolerance = max(0.000_001, frameDuration / 1_000)
        return start >= -tolerance
            && end <= assetDuration + tolerance
            && start < end
            && duration >= minimumDuration - tolerance
            && duration <= maximumDuration + tolerance
    }

    /// Moves only the leading handle. The trailing handle stays fixed.
    public mutating func setStart(_ proposedStart: TimeInterval) {
        guard assetDuration > 0 else { return }
        let lowerBound = max(0, end - maximumDuration)
        let upperBound = max(lowerBound, end - minimumDuration)
        start = clamp(snapped(proposedStart), lowerBound, upperBound)
    }

    /// Moves only the trailing handle. The leading handle stays fixed.
    public mutating func setEnd(_ proposedEnd: TimeInterval) {
        guard assetDuration > 0 else { return }
        let lowerBound = min(assetDuration, start + minimumDuration)
        let upperBound = min(assetDuration, start + maximumDuration)
        end = clamp(snapped(proposedEnd), lowerBound, upperBound)
    }

    /// Replaces both handles and clamps the result to the valid duration range.
    public mutating func setRange(start proposedStart: TimeInterval, end proposedEnd: TimeInterval) {
        guard assetDuration > 0 else { return }

        var lower = snapped(min(proposedStart, proposedEnd))
        var upper = snapped(max(proposedStart, proposedEnd))

        lower = clamp(lower, 0, assetDuration)
        upper = clamp(upper, 0, assetDuration)

        if upper - lower < minimumDuration {
            upper = min(assetDuration, lower + minimumDuration)
            lower = max(0, upper - minimumDuration)
        }

        if upper - lower > maximumDuration {
            upper = min(assetDuration, lower + maximumDuration)
            lower = max(0, upper - maximumDuration)
        }

        start = lower
        end = upper
    }

    /// Slides the selected window without changing its duration.
    public mutating func moveRange(toStart proposedStart: TimeInterval) {
        guard assetDuration > 0 else { return }
        let preservedDuration = duration
        let boundedStart = clamp(snapped(proposedStart), 0, assetDuration - preservedDuration)
        start = boundedStart
        end = boundedStart + preservedDuration
    }

    public mutating func moveRange(by offset: TimeInterval) {
        moveRange(toStart: start + offset)
    }

    public func clampedTime(_ seconds: TimeInterval) -> TimeInterval {
        clamp(seconds, start, end)
    }

    public func progress(for seconds: TimeInterval) -> Double {
        guard assetDuration > 0 else { return 0 }
        return clamp(seconds / assetDuration, 0, 1)
    }

    private func snapped(_ seconds: TimeInterval) -> TimeInterval {
        let safeSeconds = Self.nonnegativeFinite(seconds)
        if safeSeconds >= assetDuration { return assetDuration }
        let frameIndex = (safeSeconds / frameDuration).rounded()
        return min(max(frameIndex * frameDuration, 0), assetDuration)
    }

    private func clamp(
        _ value: TimeInterval,
        _ lowerBound: TimeInterval,
        _ upperBound: TimeInterval
    ) -> TimeInterval {
        min(max(value, lowerBound), upperBound)
    }

    private static func nonnegativeFinite(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    private static func positiveFinite(_ value: TimeInterval) -> TimeInterval? {
        guard value.isFinite, value > 0 else { return nil }
        return value
    }
}
