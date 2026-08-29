import Foundation

struct SwingMeasurementOutput: Sendable {
    var metrics: SwingMetrics
    var evidence: [SwingEvidence]
}

private struct MovementPeak: Sendable {
    var value: Double
    var timestampSeconds: Double
}

enum SwingMetricsCalculator {
    static func calculate(
        track: PoseTrack,
        events: SwingEventTimestamps,
        context: SwingAnalysisContext
    ) throws -> SwingMeasurementOutput {
        let minimumConfidence = context.minimumJointConfidence
        guard let addressFrame = nearestFrame(in: track.frames, to: events.addressSeconds),
              let topFrame = nearestFrame(in: track.frames, to: events.topSeconds),
              let impactFrame = nearestFrame(in: track.frames, to: events.impactSeconds),
              let finishFrame = nearestFrame(in: track.frames, to: events.finishSeconds),
              let leftShoulder = addressFrame[.leftShoulder],
              let rightShoulder = addressFrame[.rightShoulder]
        else {
            throw SwingAnalysisError.lowPoseConfidence
        }

        let shoulderWidth = PoseGeometry.distance(leftShoulder, rightShoulder)
        guard shoulderWidth > 0.025 else { throw SwingAnalysisError.lowPoseConfidence }
        let addressHead = addressFrame.headCenter(minimumConfidence: minimumConfidence)
        let addressPelvis = addressFrame.midpoint(
            .leftHip,
            .rightHip,
            minimumConfidence: minimumConfidence
        )

        var measured: [SwingPhase: SwingEventMetrics] = [:]
        let eventFrames: [(SwingPhase, PoseFrame)] = [
            (.address, addressFrame),
            (.top, topFrame),
            (.impact, impactFrame),
            (.finish, finishFrame),
        ]
        for (phase, frame) in eventFrames {
            measured[phase] = eventMetrics(
                frame: frame,
                addressFrame: addressFrame,
                addressHead: addressHead,
                addressPelvis: addressPelvis,
                addressShoulderWidth: shoulderWidth,
                minimumConfidence: minimumConfidence
            )
        }
        guard let address = measured[.address],
              let top = measured[.top],
              let impact = measured[.impact],
              let finish = measured[.finish]
        else {
            throw SwingAnalysisError.lowPoseConfidence
        }

        let backswing = events.topSeconds - events.addressSeconds
        let downswing = events.impactSeconds - events.topSeconds
        let timing = SwingTimingMetrics(
            backswingSeconds: rounded(backswing, digits: 3),
            downswingSeconds: rounded(downswing, digits: 3),
            tempoRatio: PoseGeometry.safeRatio(backswing, downswing).map { rounded($0, digits: 2) }
        )

        let relevantFrames = track.frames.filter {
            $0.timestampSeconds >= events.addressSeconds &&
                $0.timestampSeconds <= events.finishSeconds
        }
        let maximumHeadMovement = maximumMovement(
            frames: relevantFrames,
            reference: addressHead,
            firstJoint: nil,
            secondJoint: nil,
            shoulderWidth: shoulderWidth,
            minimumConfidence: minimumConfidence
        )
        let maximumPelvisMovement = maximumMovement(
            frames: relevantFrames,
            reference: addressPelvis,
            firstJoint: .leftHip,
            secondJoint: .rightHip,
            shoulderWidth: shoulderWidth,
            minimumConfidence: minimumConfidence
        )
        let postureChange: Double?
        if let addressTorso = address.torsoInclinationDegrees,
           let impactTorso = impact.torsoInclinationDegrees {
            postureChange = rounded(addressTorso - impactTorso, digits: 1)
        } else {
            postureChange = nil
        }

        let handPath = handPathMetrics(
            track: track,
            events: events,
            addressShoulderWidth: shoulderWidth,
            minimumConfidence: minimumConfidence,
            cameraView: context.cameraView
        )
        let movement = SwingMovementMetrics(
            maximumHeadMovementShoulders: maximumHeadMovement.map {
                rounded($0.value, digits: 2)
            },
            maximumHeadMovementTimestampSeconds: maximumHeadMovement?.timestampSeconds,
            maximumPelvisMovementShoulders: maximumPelvisMovement.map {
                rounded($0.value, digits: 2)
            },
            addressToImpactTorsoChangeDegrees: postureChange,
            handPath: handPath
        )
        let metrics = SwingMetrics(
            timing: timing,
            address: address,
            top: top,
            impact: impact,
            finish: finish,
            movement: movement,
            measurementScope: "2D image-plane body geometry from one camera; not club or ball data"
        )

        var evidence = eventFrames.map { phase, frame in
            SwingEvidence(
                id: "event-\(phase.rawValue)",
                phase: phase,
                timestampSeconds: frame.timestampSeconds,
                joints: frame.joints,
                measurements: evidenceMeasurements(metrics[phase])
            )
        }
        if let maximumHeadMovement,
           let frame = nearestFrame(
               in: track.frames,
               to: maximumHeadMovement.timestampSeconds
           ) {
            evidence.append(
                SwingEvidence(
                    id: "head-peak",
                    label: "Peak head movement",
                    phase: .impact,
                    timestampSeconds: frame.timestampSeconds,
                    joints: frame.joints,
                    measurements: [
                        "maximumHeadMovementShoulders": rounded(
                            maximumHeadMovement.value,
                            digits: 2
                        ),
                    ]
                )
            )
        }
        let takeawayTime = handPath.takeawaySampleSeconds
            ?? events.addressSeconds + (events.topSeconds - events.addressSeconds) * 0.35
        if let frame = nearestFrame(in: track.frames, to: takeawayTime),
           let inward = handPath.takeawayInwardMovementShoulders {
            evidence.append(
                SwingEvidence(
                    id: "hand-takeaway",
                    label: "Early takeaway",
                    phase: .address,
                    timestampSeconds: frame.timestampSeconds,
                    joints: frame.joints,
                    measurements: ["takeawayInwardMovementShoulders": inward]
                )
            )
        }
        let transitionTime = handPath.transitionDownswingSeconds
            ?? events.topSeconds + (events.impactSeconds - events.topSeconds) * 0.35
        if let matchedBackswingSeconds = handPath.matchedBackswingSeconds,
           let frame = nearestFrame(in: track.frames, to: matchedBackswingSeconds),
           let outward = handPath.transitionOutwardLoopShoulders {
            evidence.append(
                SwingEvidence(
                    id: "hand-transition-backswing",
                    label: "Matched backswing hand height",
                    phase: .top,
                    timestampSeconds: frame.timestampSeconds,
                    joints: frame.joints,
                    measurements: ["transitionOutwardLoopShoulders": outward]
                )
            )
        }
        if let frame = nearestFrame(in: track.frames, to: transitionTime),
           let outward = handPath.transitionOutwardLoopShoulders {
            evidence.append(
                SwingEvidence(
                    id: "hand-transition",
                    label: "Early downswing",
                    phase: .top,
                    timestampSeconds: frame.timestampSeconds,
                    joints: frame.joints,
                    measurements: ["transitionOutwardLoopShoulders": outward]
                )
            )
        }
        return SwingMeasurementOutput(metrics: metrics, evidence: evidence)
    }

    private static func eventMetrics(
        frame: PoseFrame,
        addressFrame: PoseFrame,
        addressHead: PosePoint?,
        addressPelvis: PosePoint?,
        addressShoulderWidth: Double,
        minimumConfidence: Double
    ) -> SwingEventMetrics {
        let shoulderMidpoint = frame.midpoint(
            .leftShoulder,
            .rightShoulder,
            minimumConfidence: minimumConfidence
        )
        let pelvisMidpoint = frame.midpoint(
            .leftHip,
            .rightHip,
            minimumConfidence: minimumConfidence
        )
        let head = frame.headCenter(minimumConfidence: minimumConfidence)

        let leftKnee = jointAngle(
            frame,
            .leftHip,
            .leftKnee,
            .leftAnkle,
            minimumConfidence: minimumConfidence
        )
        let rightKnee = jointAngle(
            frame,
            .rightHip,
            .rightKnee,
            .rightAnkle,
            minimumConfidence: minimumConfidence
        )
        let leftElbow = jointAngle(
            frame,
            .leftShoulder,
            .leftElbow,
            .leftWrist,
            minimumConfidence: minimumConfidence
        )
        let rightElbow = jointAngle(
            frame,
            .rightShoulder,
            .rightElbow,
            .rightWrist,
            minimumConfidence: minimumConfidence
        )

        let torso: Double?
        if let pelvisMidpoint, let shoulderMidpoint {
            torso = PoseGeometry.inclinationFromVertical(lower: pelvisMidpoint, upper: shoulderMidpoint)
        } else {
            torso = nil
        }
        let shoulderLine = lineAngle(
            frame,
            .leftShoulder,
            .rightShoulder,
            minimumConfidence: minimumConfidence
        )
        let hipLine = lineAngle(
            frame,
            .leftHip,
            .rightHip,
            minimumConfidence: minimumConfidence
        )

        var stanceRatio: Double?
        if let leftAnkle = validPoint(frame[.leftAnkle], minimumConfidence),
           let rightAnkle = validPoint(frame[.rightAnkle], minimumConfidence),
           let leftShoulder = validPoint(frame[.leftShoulder], minimumConfidence),
           let rightShoulder = validPoint(frame[.rightShoulder], minimumConfidence) {
            stanceRatio = PoseGeometry.safeRatio(
                PoseGeometry.distance(leftAnkle, rightAnkle),
                PoseGeometry.distance(leftShoulder, rightShoulder)
            )
        }

        let headShift: Double?
        if let addressHead, let head {
            headShift = (head.x - addressHead.x) / addressShoulderWidth
        } else {
            headShift = nil
        }
        let pelvisShift: Double?
        if let addressPelvis, let pelvisMidpoint {
            pelvisShift = (pelvisMidpoint.x - addressPelvis.x) / addressShoulderWidth
        } else {
            pelvisShift = nil
        }

        var metricJoints: Set<PoseJoint> = []
        var addressReferenceJoints: Set<PoseJoint> = []
        if leftKnee != nil {
            metricJoints.formUnion([.leftHip, .leftKnee, .leftAnkle])
        }
        if rightKnee != nil {
            metricJoints.formUnion([.rightHip, .rightKnee, .rightAnkle])
        }
        if leftElbow != nil {
            metricJoints.formUnion([.leftShoulder, .leftElbow, .leftWrist])
        }
        if rightElbow != nil {
            metricJoints.formUnion([.rightShoulder, .rightElbow, .rightWrist])
        }
        if torso != nil {
            metricJoints.formUnion([.leftShoulder, .rightShoulder, .leftHip, .rightHip])
        }
        if shoulderLine != nil {
            metricJoints.formUnion([.leftShoulder, .rightShoulder])
        }
        if hipLine != nil {
            metricJoints.formUnion([.leftHip, .rightHip])
        }
        if stanceRatio != nil {
            metricJoints.formUnion([.leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder])
        }
        if headShift != nil {
            metricJoints.formUnion(
                headJoints(in: frame, minimumConfidence: minimumConfidence)
            )
            addressReferenceJoints.formUnion(
                headJoints(in: addressFrame, minimumConfidence: minimumConfidence)
            )
            addressReferenceJoints.formUnion([.leftShoulder, .rightShoulder])
        }
        if pelvisShift != nil {
            metricJoints.formUnion([.leftHip, .rightHip])
            addressReferenceJoints.formUnion([
                .leftHip,
                .rightHip,
                .leftShoulder,
                .rightShoulder,
            ])
        }
        let poseConfidence = metricConfidence(
            frame: frame,
            joints: metricJoints,
            addressFrame: addressFrame,
            addressReferenceJoints: addressReferenceJoints
        )

        return SwingEventMetrics(
            timestampSeconds: frame.timestampSeconds,
            leftKneeDegrees: leftKnee.map { rounded($0, digits: 1) },
            rightKneeDegrees: rightKnee.map { rounded($0, digits: 1) },
            leftElbowDegrees: leftElbow.map { rounded($0, digits: 1) },
            rightElbowDegrees: rightElbow.map { rounded($0, digits: 1) },
            torsoInclinationDegrees: torso.map { rounded($0, digits: 1) },
            shoulderLineDegrees: shoulderLine.map { rounded($0, digits: 1) },
            hipLineDegrees: hipLine.map { rounded($0, digits: 1) },
            stanceToShoulders: stanceRatio.map { rounded($0, digits: 2) },
            headShiftShoulders: headShift.map { rounded($0, digits: 2) },
            pelvisShiftShoulders: pelvisShift.map { rounded($0, digits: 2) },
            poseConfidence: rounded(poseConfidence, digits: 2)
        )
    }

    private static func headJoints(
        in frame: PoseFrame,
        minimumConfidence: Double
    ) -> Set<PoseJoint> {
        Set([PoseJoint.nose, .leftEye, .rightEye, .leftEar, .rightEar].filter {
            (frame[$0]?.confidence ?? 0) >= minimumConfidence
        })
    }

    private static func metricConfidence(
        frame: PoseFrame,
        joints: Set<PoseJoint>,
        addressFrame: PoseFrame,
        addressReferenceJoints: Set<PoseJoint>
    ) -> Double {
        var samples: [Double] = []
        if frame.timestampSeconds == addressFrame.timestampSeconds {
            samples = joints.union(addressReferenceJoints).compactMap {
                frame[$0]?.confidence
            }
        } else {
            samples = joints.compactMap { frame[$0]?.confidence }
            samples.append(contentsOf: addressReferenceJoints.compactMap {
                addressFrame[$0]?.confidence
            })
        }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private static func handPathMetrics(
        track: PoseTrack,
        events: SwingEventTimestamps,
        addressShoulderWidth: Double,
        minimumConfidence: Double,
        cameraView: SwingCameraView
    ) -> SwingHandPathMetrics {
        let samples = BodyTrajectory.samples(
            from: track.frames,
            minimumConfidence: minimumConfidence
        )
        guard let address = nearestSample(samples, events.addressSeconds),
              let top = nearestSample(samples, events.topSeconds),
              let impact = nearestSample(samples, events.impactSeconds),
              let addressPelvis = address.pelvis
        else {
            return unavailableHandPath(cameraView: cameraView)
        }

        let takeawayTime = address.timestamp + (top.timestamp - address.timestamp) * 0.35
        let downswingTime = top.timestamp + (impact.timestamp - top.timestamp) * 0.35
        guard let takeaway = nearestSample(samples, takeawayTime),
              let takeawayPelvis = takeaway.pelvis,
              let downswing = nearestSample(samples, downswingTime),
              let downswingPelvis = downswing.pelvis
        else {
            return unavailableHandPath(cameraView: cameraView)
        }

        let addressRadius = abs(address.hands.x - addressPelvis.x)
        let takeawayRadius = abs(takeaway.hands.x - takeawayPelvis.x)
        let inward = (addressRadius - takeawayRadius) / addressShoulderWidth

        let backswingSamples = samples.filter {
            $0.timestamp >= address.timestamp && $0.timestamp <= top.timestamp && $0.pelvis != nil
        }
        let matchedBackswing = backswingSamples.min {
            abs($0.relativeHandY - downswing.relativeHandY) <
                abs($1.relativeHandY - downswing.relativeHandY)
        }
        let outward: Double?
        if let matchedBackswing, let backswingPelvis = matchedBackswing.pelvis {
            let backswingRadius = abs(matchedBackswing.hands.x - backswingPelvis.x)
            let downswingRadius = abs(downswing.hands.x - downswingPelvis.x)
            outward = (downswingRadius - backswingRadius) / addressShoulderWidth
        } else {
            outward = nil
        }

        var confidenceSamples = [address, takeaway, downswing]
        if let matchedBackswing {
            confidenceSamples.append(matchedBackswing)
        }
        let confidence = confidenceSamples
            .map { min($0.hands.confidence, $0.pelvis?.confidence ?? 0) }
            .reduce(0, +) / Double(confidenceSamples.count)
        return SwingHandPathMetrics(
            takeawayInwardMovementShoulders: rounded(inward, digits: 2),
            transitionOutwardLoopShoulders: outward.map { rounded($0, digits: 2) },
            takeawaySampleSeconds: takeaway.timestamp,
            matchedBackswingSeconds: matchedBackswing?.timestamp,
            transitionDownswingSeconds: downswing.timestamp,
            measurementConfidence: rounded(confidence, digits: 2),
            scope: handPathScope(cameraView)
        )
    }

    private static func maximumMovement(
        frames: [PoseFrame],
        reference: PosePoint?,
        firstJoint: PoseJoint?,
        secondJoint: PoseJoint?,
        shoulderWidth: Double,
        minimumConfidence: Double
    ) -> MovementPeak? {
        guard let reference else { return nil }
        let samples: [(timestamp: Double, point: PosePoint)]
        if let firstJoint, let secondJoint {
            samples = frames.compactMap { frame in
                frame.midpoint(
                    firstJoint,
                    secondJoint,
                    minimumConfidence: minimumConfidence
                ).map { (timestamp: frame.timestampSeconds, point: $0) }
            }
        } else {
            samples = frames.compactMap { frame in
                frame.headCenter(minimumConfidence: minimumConfidence).map {
                    (timestamp: frame.timestampSeconds, point: $0)
                }
            }
        }
        guard let peak = samples.max(by: {
            PoseGeometry.distance($0.point, reference)
                < PoseGeometry.distance($1.point, reference)
        }) else { return nil }
        return MovementPeak(
            value: PoseGeometry.distance(peak.point, reference) / shoulderWidth,
            timestampSeconds: peak.timestamp
        )
    }

    private static func nearestFrame(in frames: [PoseFrame], to timestamp: Double) -> PoseFrame? {
        frames.min {
            abs($0.timestampSeconds - timestamp) < abs($1.timestampSeconds - timestamp)
        }
    }

    private static func nearestSample(
        _ samples: [BodyTrajectorySample],
        _ timestamp: Double
    ) -> BodyTrajectorySample? {
        samples.min { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }
    }

    private static func jointAngle(
        _ frame: PoseFrame,
        _ first: PoseJoint,
        _ vertex: PoseJoint,
        _ third: PoseJoint,
        minimumConfidence: Double
    ) -> Double? {
        guard let firstPoint = validPoint(frame[first], minimumConfidence),
              let vertexPoint = validPoint(frame[vertex], minimumConfidence),
              let thirdPoint = validPoint(frame[third], minimumConfidence)
        else {
            return nil
        }
        return PoseGeometry.jointAngle(first: firstPoint, vertex: vertexPoint, third: thirdPoint)
    }

    private static func lineAngle(
        _ frame: PoseFrame,
        _ first: PoseJoint,
        _ second: PoseJoint,
        minimumConfidence: Double
    ) -> Double? {
        guard let firstPoint = validPoint(frame[first], minimumConfidence),
              let secondPoint = validPoint(frame[second], minimumConfidence)
        else {
            return nil
        }
        return PoseGeometry.lineAngle(first: firstPoint, second: secondPoint)
    }

    private static func validPoint(_ point: PosePoint?, _ minimumConfidence: Double) -> PosePoint? {
        guard let point, point.confidence >= minimumConfidence else { return nil }
        return point
    }

    private static func unavailableHandPath(cameraView: SwingCameraView) -> SwingHandPathMetrics {
        SwingHandPathMetrics(
            takeawayInwardMovementShoulders: nil,
            transitionOutwardLoopShoulders: nil,
            measurementConfidence: 0,
            scope: handPathScope(cameraView)
        )
    }

    private static func handPathScope(_ cameraView: SwingCameraView) -> String {
        switch cameraView {
        case .downTheLine:
            "Projected hand path from a down-the-line body-pose view; the club is not measured"
        case .faceOn:
            "Projected hand path from a face-on view; do not infer inside/outside club path"
        case .unknown:
            "Projected hand path from an unverified camera view; directional coaching is disabled"
        }
    }

    private static func evidenceMeasurements(_ metrics: SwingEventMetrics) -> [String: Double] {
        var values: [String: Double] = ["poseConfidence": metrics.poseConfidence]
        let optionalValues: [(String, Double?)] = [
            ("leftKneeDegrees", metrics.leftKneeDegrees),
            ("rightKneeDegrees", metrics.rightKneeDegrees),
            ("leftElbowDegrees", metrics.leftElbowDegrees),
            ("rightElbowDegrees", metrics.rightElbowDegrees),
            ("torsoInclinationDegrees", metrics.torsoInclinationDegrees),
            ("shoulderLineDegrees", metrics.shoulderLineDegrees),
            ("hipLineDegrees", metrics.hipLineDegrees),
            ("stanceToShoulders", metrics.stanceToShoulders),
            ("headShiftShoulders", metrics.headShiftShoulders),
            ("pelvisShiftShoulders", metrics.pelvisShiftShoulders),
        ]
        for (key, value) in optionalValues {
            if let value { values[key] = value }
        }
        return values
    }

    private static func rounded(_ value: Double, digits: Int) -> Double {
        let scale = pow(10, Double(digits))
        return (value * scale).rounded() / scale
    }
}
