import AVFoundation
import CoreVideo
import Foundation
import Vision

/// Reads and evaluates only the range selected in the trim UI.
actor VideoPoseExtractor {
    private static let visionJoints: [(PoseJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose),
        (.neck, .neck),
        (.root, .root),
        (.leftEye, .leftEye),
        (.rightEye, .rightEye),
        (.leftEar, .leftEar),
        (.rightEar, .rightEar),
        (.leftShoulder, .leftShoulder),
        (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow),
        (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist),
        (.rightWrist, .rightWrist),
        (.leftHip, .leftHip),
        (.rightHip, .rightHip),
        (.leftKnee, .leftKnee),
        (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle),
        (.rightAnkle, .rightAnkle),
    ]

    func extract(
        videoURL: URL,
        selectedRange: CMTimeRange,
        sampleRate: Double,
        minimumJointConfidence: Double,
        orientationOverride: PoseVideoOrientation?,
        progress: SwingAnalysisProgress?
    ) async throws -> PoseTrack {
        let asset = AVURLAsset(url: videoURL)
        let assetDuration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw PoseExtractionError.noVideoTrack
        }

        let validRange = try Self.clampedRange(selectedRange, assetDuration: assetDuration)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let orientation = orientationOverride ?? Self.orientation(for: preferredTransform)
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw PoseExtractionError.cannotCreateReader(error.localizedDescription)
        }
        reader.timeRange = validRange

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw PoseExtractionError.cannotCreateReader("The video track cannot provide pixel buffers.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw PoseExtractionError.cannotStartReader(
                reader.error?.localizedDescription ?? "Unknown media-reader error"
            )
        }

        let request = VNDetectHumanBodyPoseRequest()
        let sequenceHandler = VNSequenceRequestHandler()
        let interval = 1 / max(1, min(sampleRate, 60))
        let startSeconds = validRange.start.seconds
        let durationSeconds = validRange.duration.seconds
        let endSeconds = startSeconds + durationSeconds
        var nextSampleSeconds = startSeconds
        var frames: [PoseFrame] = []
        var processedFrameCount = 0

        await progress?.update(
            phase: .extractingPose,
            fractionCompleted: 0,
            processedFrameCount: 0,
            message: "Finding body points in the selected swing"
        )

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            if let progress {
                try await progress.checkCancellation()
            }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite, timestamp >= startSeconds - 0.01, timestamp <= endSeconds + 0.01 else {
                continue
            }
            guard timestamp + 0.000_5 >= nextSampleSeconds else { continue }
            nextSampleSeconds = timestamp + interval
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            do {
                try sequenceHandler.perform(
                    [request],
                    on: pixelBuffer,
                    orientation: orientation.cgImagePropertyOrientation
                )
            } catch {
                if Self.isUnrecoverableVisionError(error) {
                    throw PoseExtractionError.visionUnavailable(
                        error.localizedDescription
                    )
                }
                // A bad frame must not discard otherwise usable pose evidence.
                continue
            }

            processedFrameCount += 1
            if let observation = request.results?.first {
                let frame = Self.poseFrame(
                    observation: observation,
                    timestampSeconds: timestamp,
                    orientation: orientation,
                    minimumJointConfidence: minimumJointConfidence
                )
                if !frame.joints.isEmpty {
                    frames.append(frame)
                }
            }

            let fraction = max(0, min(0.78, ((timestamp - startSeconds) / durationSeconds) * 0.78))
            await progress?.update(
                phase: .extractingPose,
                fractionCompleted: fraction,
                processedFrameCount: processedFrameCount,
                message: "Finding body points in the selected swing"
            )
        }

        if reader.status == .failed {
            throw PoseExtractionError.readerFailed(
                reader.error?.localizedDescription ?? "Unknown media-reader error"
            )
        }

        let minimumFrames = max(8, Int(min(2, durationSeconds) * min(sampleRate, 10) * 0.5))
        guard frames.count >= minimumFrames else {
            throw PoseExtractionError.insufficientPoseFrames(found: frames.count)
        }

        return PoseTrack(
            selectedRangeStartSeconds: startSeconds,
            selectedRangeDurationSeconds: durationSeconds,
            nominalSampleRate: sampleRate,
            orientation: orientation,
            frames: frames
        )
    }

    private static func poseFrame(
        observation: VNHumanBodyPoseObservation,
        timestampSeconds: Double,
        orientation: PoseVideoOrientation,
        minimumJointConfidence: Double
    ) -> PoseFrame {
        var joints: [PoseJoint: PosePoint] = [:]
        for (joint, visionName) in visionJoints {
            guard let point = try? observation.recognizedPoint(visionName) else { continue }
            let confidence = Double(point.confidence)
            guard confidence >= minimumJointConfidence else { continue }
            joints[joint] = PosePoint(
                x: Double(point.location.x),
                y: 1 - Double(point.location.y),
                confidence: confidence
            )
        }
        return PoseFrame(
            timestampSeconds: timestampSeconds,
            orientation: orientation,
            joints: joints
        )
    }

    private static func clampedRange(
        _ requestedRange: CMTimeRange,
        assetDuration: CMTime
    ) throws -> CMTimeRange {
        let assetSeconds = assetDuration.seconds
        let requestedStart = requestedRange.start.seconds
        let requestedDuration = requestedRange.duration.seconds
        guard assetSeconds.isFinite, assetSeconds > 0,
              requestedStart.isFinite, requestedDuration.isFinite,
              requestedDuration > 0
        else {
            throw PoseExtractionError.invalidRange
        }

        let start = max(0, min(requestedStart, assetSeconds))
        let end = max(start, min(requestedStart + requestedDuration, assetSeconds))
        guard end - start >= 1 else {
            throw PoseExtractionError.invalidRange
        }
        let timescale: CMTimeScale = 600
        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            duration: CMTime(seconds: end - start, preferredTimescale: timescale)
        )
    }

    private static func orientation(for transform: CGAffineTransform) -> PoseVideoOrientation {
        let tolerance = 0.01
        func near(_ first: CGFloat, _ second: CGFloat) -> Bool {
            abs(first - second) < tolerance
        }

        switch (transform.a, transform.b, transform.c, transform.d) {
        case let (a, b, c, d) where near(a, 0) && near(b, 1) && near(c, -1) && near(d, 0):
            return .right
        case let (a, b, c, d) where near(a, 0) && near(b, -1) && near(c, 1) && near(d, 0):
            return .left
        case let (a, b, c, d) where near(a, -1) && near(b, 0) && near(c, 0) && near(d, -1):
            return .down
        case let (a, b, c, d) where near(a, -1) && near(b, 0) && near(c, 0) && near(d, 1):
            return .upMirrored
        case let (a, b, c, d) where near(a, 1) && near(b, 0) && near(c, 0) && near(d, -1):
            return .downMirrored
        case let (a, b, c, d) where near(a, 0) && near(b, 1) && near(c, 1) && near(d, 0):
            return .rightMirrored
        case let (a, b, c, d) where near(a, 0) && near(b, -1) && near(c, -1) && near(d, 0):
            return .leftMirrored
        default:
            return .up
        }
    }

    private static func isUnrecoverableVisionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == VNErrorDomain,
              let code = VNErrorCode(rawValue: nsError.code)
        else {
            return false
        }

        switch code {
        case .internalError,
             .invalidModel,
             .dataUnavailable,
             .notImplemented,
             .unsupportedRequest,
             .unsupportedComputeDevice,
             .unsupportedComputeStage:
            return true
        default:
            return false
        }
    }
}
