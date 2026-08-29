import Foundation

public enum SwingAnalysisPhase: String, Codable, Sendable {
    case preparing
    case extractingPose
    case smoothing
    case detectingEvents
    case measuring
    case generatingFindings
    case complete
    case cancelled
}

public struct SwingAnalysisProgressSnapshot: Codable, Hashable, Sendable {
    public var phase: SwingAnalysisPhase
    public var fractionCompleted: Double
    public var processedFrameCount: Int
    public var message: String
    public var isCancelled: Bool

    public init(
        phase: SwingAnalysisPhase,
        fractionCompleted: Double,
        processedFrameCount: Int,
        message: String,
        isCancelled: Bool = false
    ) {
        self.phase = phase
        self.fractionCompleted = max(0, min(fractionCompleted, 1))
        self.processedFrameCount = max(0, processedFrameCount)
        self.message = message
        self.isCancelled = isCancelled
    }
}

/// UI-owned progress and cooperative cancellation state.
public actor SwingAnalysisProgress {
    private var snapshot = SwingAnalysisProgressSnapshot(
        phase: .preparing,
        fractionCompleted: 0,
        processedFrameCount: 0,
        message: "Preparing video"
    )
    private var cancelled = false

    public init() {}

    public func currentSnapshot() -> SwingAnalysisProgressSnapshot {
        snapshot
    }

    public func cancel() {
        cancelled = true
        snapshot.phase = .cancelled
        snapshot.isCancelled = true
        snapshot.message = "Analysis cancelled"
    }

    public func checkCancellation() throws {
        if cancelled {
            throw CancellationError()
        }
    }

    func reset() {
        cancelled = false
        snapshot = SwingAnalysisProgressSnapshot(
            phase: .preparing,
            fractionCompleted: 0,
            processedFrameCount: 0,
            message: "Preparing video"
        )
    }

    func update(
        phase: SwingAnalysisPhase,
        fractionCompleted: Double,
        processedFrameCount: Int? = nil,
        message: String
    ) {
        guard !cancelled else { return }
        snapshot = SwingAnalysisProgressSnapshot(
            phase: phase,
            fractionCompleted: max(snapshot.fractionCompleted, fractionCompleted),
            processedFrameCount: processedFrameCount ?? snapshot.processedFrameCount,
            message: message
        )
    }
}
