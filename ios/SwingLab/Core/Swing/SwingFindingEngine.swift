import Foundation

public enum SwingFindingEngine {
    public static func findings(
        metrics: SwingMetrics,
        events: SwingEventTimestamps,
        context: SwingAnalysisContext
    ) -> [SwingFinding] {
        var findings: [SwingFinding] = []
        findings.append(contentsOf: tempoFinding(metrics: metrics, events: events))
        findings.append(contentsOf: headFinding(metrics: metrics, events: events))
        findings.append(contentsOf: setupFinding(metrics: metrics))
        findings.append(contentsOf: postureFinding(metrics: metrics, context: context))
        findings.append(contentsOf: takeawayFinding(metrics: metrics, context: context))
        findings.append(contentsOf: transitionFinding(metrics: metrics, context: context))

        let order: [SwingFindingSeverity: Int] = [
            .priority: 0,
            .watch: 1,
            .good: 2,
            .info: 3,
        ]
        return findings.sorted {
            let left = order[$0.severity] ?? 4
            let right = order[$1.severity] ?? 4
            return left == right ? $0.id < $1.id : left < right
        }
    }

    public static func score(
        metrics: SwingMetrics,
        context: SwingAnalysisContext
    ) -> SwingScore {
        var components: [SwingScoreComponent] = []

        if let ratio = metrics.timing.tempoRatio {
            let distanceFromBand: Double
            if ratio < 2.2 {
                distanceFromBand = 2.2 - ratio
            } else if ratio > 4.0 {
                distanceFromBand = ratio - 4.0
            } else {
                distanceFromBand = 0
            }
            let points = max(8, 25 - distanceFromBand * 10)
            components.append(
                SwingScoreComponent(
                    id: "tempo",
                    title: "Measured rhythm",
                    earnedPoints: points,
                    availablePoints: 25,
                    explanation: distanceFromBand == 0
                        ? "Tempo is inside the broad 2.2:1 to 4.0:1 screening band."
                        : "Tempo is outside the broad screening band; strike quality still decides whether this matters."
                )
            )
        }

        if let movement = metrics.movement.maximumHeadMovementShoulders {
            let points: Double
            if movement <= 0.25 {
                points = 25
            } else if movement <= 0.65 {
                points = 25 - (movement - 0.25) / 0.40 * 15
            } else {
                points = 6
            }
            components.append(
                SwingScoreComponent(
                    id: "head-stability",
                    title: "Projected head stability",
                    earnedPoints: points,
                    availablePoints: 25,
                    explanation: "Peak movement was \(format(movement, 2)) address shoulder widths."
                )
            )
        }

        if context.cameraView == .downTheLine,
           let postureChange = metrics.movement.addressToImpactTorsoChangeDegrees {
            let concerningChange = max(0, postureChange - 5)
            let points = max(6, 25 - concerningChange * 1.25)
            components.append(
                SwingScoreComponent(
                    id: "posture",
                    title: "Projected posture retention",
                    earnedPoints: points,
                    availablePoints: 25,
                    explanation: "Torso inclination changed by \(format(postureChange, 1))° from address to impact."
                )
            )
        }

        if let stance = metrics.address.stanceToShoulders,
           let leftKnee = metrics.address.leftKneeDegrees,
           let rightKnee = metrics.address.rightKneeDegrees {
            let kneeDifference = abs(leftKnee - rightKnee)
            var points = 15.0
            if stance < 0.65 || stance > 2.0 { points -= 4 }
            if kneeDifference > 15 { points -= min(6, (kneeDifference - 15) * 0.25) }
            components.append(
                SwingScoreComponent(
                    id: "setup",
                    title: "Setup geometry",
                    earnedPoints: points,
                    availablePoints: 15,
                    explanation: "Stance was \(format(stance, 2)) shoulder widths; projected knee angles differed by \(format(kneeDifference, 0))°."
                )
            )
        }

        let handPath = metrics.movement.handPath
        if context.cameraView == .downTheLine, handPath.measurementConfidence >= 0.60 {
            var points = 10.0
            var reasons: [String] = []
            if let inward = handPath.takeawayInwardMovementShoulders {
                if inward >= 0.28 { points -= min(5, (inward - 0.18) * 12) }
                reasons.append("takeaway inward \(format(inward, 2))")
            }
            if let outward = handPath.transitionOutwardLoopShoulders {
                if outward >= 0.22 { points -= min(5, (outward - 0.12) * 12) }
                reasons.append("transition outward \(format(outward, 2))")
            }
            components.append(
                SwingScoreComponent(
                    id: "projected-hand-path",
                    title: "Projected hand-path screen",
                    earnedPoints: max(0, points),
                    availablePoints: 10,
                    explanation: reasons.isEmpty
                        ? "There was not enough directional evidence for a deduction."
                        : reasons.joined(separator: "; ") + " shoulder widths. The club was not measured."
                )
            )
        }

        let earned = components.map(\.earnedPoints).reduce(0, +)
        let available = components.map(\.availablePoints).reduce(0, +)
        let value = available > 0 ? Int((earned / available * 100).rounded()) : 0
        return SwingScore(
            value: max(0, min(value, 100)),
            label: "Body-movement screen",
            components: components,
            explanation: "\(format(earned, 1)) of \(format(available, 1)) available points, normalized to 100. This screen grades only measured 2D body patterns, not contact or ball flight."
        )
    }

    private static func tempoFinding(
        metrics: SwingMetrics,
        events: SwingEventTimestamps
    ) -> [SwingFinding] {
        guard let ratio = metrics.timing.tempoRatio,
              metrics.top.poseConfidence >= 0.50,
              metrics.impact.poseConfidence >= 0.50
        else {
            return []
        }
        let severity: SwingFindingSeverity
        let title: String
        let tip: String
        if ratio < 2.2 {
            severity = .watch
            title = "Backswing rhythm is quick"
            tip = "Test one rehearsal with a calmer takeaway. Keep the change only if strike quality improves."
        } else if ratio > 4.0 {
            severity = .watch
            title = "Backswing rhythm is long"
            tip = "Check for a pause or extra motion at the top, then compare strike pattern."
        } else {
            severity = .good
            title = "Rhythm is in a broad coaching band"
            tip = "Use repeatability across several swings as the next useful check."
        }
        return [
            SwingFinding(
                id: "tempo",
                title: title,
                observation: "Backswing \(format(metrics.timing.backswingSeconds, 2))s, downswing \(format(metrics.timing.downswingSeconds, 2))s, ratio \(format(ratio, 2)):1.",
                coachingTip: tip,
                phase: .top,
                severity: severity,
                confidence: min(events.confidence, min(metrics.top.poseConfidence, metrics.impact.poseConfidence)),
                evidenceIDs: ["event-address", "event-top", "event-impact"],
                caveat: "Tempo is descriptive; there is no single correct ratio for every golfer."
            ),
        ]
    }

    private static func headFinding(
        metrics: SwingMetrics,
        events: SwingEventTimestamps
    ) -> [SwingFinding] {
        guard let movement = metrics.movement.maximumHeadMovementShoulders,
              metrics.address.poseConfidence >= 0.50,
              metrics.impact.poseConfidence >= 0.50
        else {
            return []
        }
        if movement >= 0.45 {
            return [
                SwingFinding(
                    id: "head-movement",
                    title: "Head movement is worth checking",
                    observation: "Peak projected movement was \(format(movement, 2)) address shoulder widths.",
                    coachingTip: "Check whether the movement repeats and whether it changes strike location. Do not try to freeze your head in place.",
                    phase: .impact,
                    severity: .priority,
                    confidence: min(events.confidence, metrics.impact.poseConfidence),
                    evidenceIDs: ["event-address", "event-impact", "event-finish"],
                    caveat: "A single 2D view cannot distinguish lateral sway, depth, rotation, or camera parallax."
                ),
            ]
        }
        return [
            SwingFinding(
                id: "head-contained",
                title: "Head position stays fairly contained",
                observation: "Peak projected movement was \(format(movement, 2)) address shoulder widths.",
                coachingTip: "Keep this as a repeatability marker instead of forcing the head to stay still.",
                phase: .impact,
                severity: .good,
                confidence: min(events.confidence, metrics.impact.poseConfidence),
                evidenceIDs: ["event-address", "event-impact"],
                caveat: "This does not measure pressure shift or true depth."
            ),
        ]
    }

    private static func setupFinding(metrics: SwingMetrics) -> [SwingFinding] {
        guard let left = metrics.address.leftKneeDegrees,
              let right = metrics.address.rightKneeDegrees,
              metrics.address.poseConfidence >= 0.50
        else {
            return []
        }
        let difference = abs(left - right)
        return [
            SwingFinding(
                id: "setup-knees",
                title: "Address knee geometry",
                observation: "Projected knee angles are \(format(left, 0))° left and \(format(right, 0))° right (\(format(difference, 0))° apart).",
                coachingTip: "Use this as a setup-repeatability marker across swings.",
                phase: .address,
                severity: difference >= 15 ? .watch : .info,
                confidence: metrics.address.poseConfidence,
                evidenceIDs: ["event-address"],
                caveat: "Perspective changes joint angles, so asymmetry alone is not a fault."
            ),
        ]
    }

    private static func postureFinding(
        metrics: SwingMetrics,
        context: SwingAnalysisContext
    ) -> [SwingFinding] {
        guard context.cameraView == .downTheLine,
              let change = metrics.movement.addressToImpactTorsoChangeDegrees,
              change >= 10,
              metrics.address.poseConfidence >= 0.58,
              metrics.impact.poseConfidence >= 0.58
        else {
            return []
        }
        return [
            SwingFinding(
                id: "posture-loss-hypothesis",
                title: "Loss-of-posture pattern to verify",
                observation: "Projected torso inclination changed from \(format(metrics.address.torsoInclinationDegrees ?? 0, 0))° at address to \(format(metrics.impact.torsoInclinationDegrees ?? 0, 0))° at impact (\(format(change, 0))° more upright).",
                coachingTip: "Check a stable, true down-the-line recording for hip depth and strike pattern before changing the motion.",
                phase: .impact,
                severity: .priority,
                confidence: min(metrics.address.poseConfidence, metrics.impact.poseConfidence) * 0.88,
                evidenceIDs: ["event-address", "event-impact"],
                caveat: "This is an early-extension hypothesis only. Rotation and perspective can create the same 2D torso change."
            ),
        ]
    }

    private static func takeawayFinding(
        metrics: SwingMetrics,
        context: SwingAnalysisContext
    ) -> [SwingFinding] {
        let handPath = metrics.movement.handPath
        guard context.cameraView == .downTheLine,
              handPath.measurementConfidence >= 0.60,
              let inward = handPath.takeawayInwardMovementShoulders,
              inward >= 0.28
        else {
            return []
        }
        return [
            SwingFinding(
                id: "hands-inside-pattern",
                title: "Hands move sharply inward in the takeaway",
                observation: "The projected hand center moved \(format(inward, 2)) shoulder widths toward the torso center early in the backswing.",
                coachingTip: "Compare one rehearsal where hands and sternum start together. Keep it only if the strike and start line improve.",
                phase: .address,
                severity: .watch,
                confidence: handPath.measurementConfidence * 0.86,
                evidenceIDs: ["event-address", "hand-takeaway"],
                caveat: "This is a hands-too-inside body-pose pattern, not a measurement of clubhead or club path."
            ),
        ]
    }

    private static func transitionFinding(
        metrics: SwingMetrics,
        context: SwingAnalysisContext
    ) -> [SwingFinding] {
        let handPath = metrics.movement.handPath
        guard context.cameraView == .downTheLine,
              handPath.measurementConfidence >= 0.68,
              let outward = handPath.transitionOutwardLoopShoulders,
              outward >= 0.22
        else {
            return []
        }
        return [
            SwingFinding(
                id: "projected-transition-loop",
                title: "Projected hands loop outward in transition",
                observation: "At matched hand height, the early-downswing hands were \(format(outward, 2)) shoulder widths farther from the torso center than on the backswing.",
                coachingTip: "Use a high-frame-rate down-the-line view that includes the full club before deciding whether transition work is needed.",
                phase: .top,
                severity: .watch,
                confidence: handPath.measurementConfidence * 0.72,
                evidenceIDs: ["event-top", "hand-transition"],
                caveat: "This body-pose loop can be consistent with an over-the-top pattern, but it does not prove club path, shaft plane, or face direction."
            ),
        ]
    }

    private static func format(_ value: Double, _ digits: Int) -> String {
        String(format: "%.*f", digits, value)
    }
}
