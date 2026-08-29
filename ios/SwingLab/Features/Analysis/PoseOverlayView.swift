import SwiftUI

/// Draws the same normalized pose coordinate space used by the analysis engine.
/// The parent should give this view the full player bounds and the source video's aspect ratio.
struct PoseOverlayView: View {
    let pose: PoseFrame?
    let videoAspectRatio: CGFloat
    var highlightedJoints: Set<PoseJoint> = []
    var findingOverlay: SwingFindingOverlay?
    var baselinePose: PoseFrame?
    /// A metric-specific evidence frame used for the finding guide while the
    /// skeleton remains attached to the visible video frame.
    var guidePose: PoseFrame? = nil
    var handTrail: [PoseFrame] = []
    var showsJointDots = true
    var skeletonColor: Color = .white
    var highlightColor: Color = Color(red: 1, green: 0.28, blue: 0.31)

    private let bones: [(PoseJoint, PoseJoint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        (.neck, .nose),
    ]

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let contentRect = aspectFitRect(aspectRatio: videoAspectRatio, in: size)

            drawFindingGuide(
                in: &context,
                pose: pose,
                contentRect: contentRect
            )

            for (firstJoint, secondJoint) in bones {
                guard let first = visiblePoint(firstJoint, in: pose),
                      let second = visiblePoint(secondJoint, in: pose)
                else { continue }

                var path = Path()
                path.move(to: displayPoint(first, in: contentRect))
                path.addLine(to: displayPoint(second, in: contentRect))
                let highlighted = highlightedJoints.contains(firstJoint)
                    || highlightedJoints.contains(secondJoint)
                context.stroke(
                    path,
                    with: .color(highlighted ? highlightColor : skeletonColor),
                    style: StrokeStyle(lineWidth: highlighted ? 4 : 2.5, lineCap: .round)
                )
            }

            guard showsJointDots else { return }
            for (joint, point) in pose.joints where point.confidence >= 0.25 {
                let center = displayPoint(point, in: contentRect)
                let highlighted = highlightedJoints.contains(joint)
                let radius: CGFloat = highlighted ? 8 : 4.5
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(highlighted ? highlightColor : skeletonColor)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func visiblePoint(_ joint: PoseJoint, in pose: PoseFrame) -> PosePoint? {
        guard let point = pose.joints[joint], point.confidence >= 0.25 else { return nil }
        return point
    }

    private func drawFindingGuide(
        in context: inout GraphicsContext,
        pose: PoseFrame,
        contentRect: CGRect
    ) {
        guard let findingOverlay else { return }
        switch findingOverlay.kind {
        case .tempo:
            break
        case .headMovement:
            if let guidePose {
                drawHeadGuide(
                    in: &context,
                    pose: guidePose,
                    contentRect: contentRect
                )
            }
        case .kneeGeometry:
            drawKneeGuides(in: &context, pose: pose, contentRect: contentRect)
        case .torsoPosture:
            drawTorsoGuide(in: &context, pose: pose, contentRect: contentRect)
        case .takeawayHandPath, .transitionHandPath:
            drawHandPathGuide(in: &context, pose: pose, contentRect: contentRect)
        }
    }

    private func drawHeadGuide(
        in context: inout GraphicsContext,
        pose: PoseFrame,
        contentRect: CGRect
    ) {
        guard let current = headPoint(in: pose) else { return }
        let currentPoint = displayPoint(current, in: contentRect)
        drawRing(
            center: currentPoint,
            radius: 17,
            color: highlightColor,
            lineWidth: 4,
            in: &context
        )

        guard let baselinePose, let baseline = headPoint(in: baselinePose) else { return }
        let baselinePoint = displayPoint(baseline, in: contentRect)
        var delta = Path()
        delta.move(to: baselinePoint)
        delta.addLine(to: currentPoint)
        context.stroke(
            delta,
            with: .color(highlightColor.opacity(0.9)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 5])
        )
        drawCrosshair(center: baselinePoint, color: .white.opacity(0.82), in: &context)
    }

    private func drawKneeGuides(
        in context: inout GraphicsContext,
        pose: PoseFrame,
        contentRect: CGRect
    ) {
        for joint in [PoseJoint.leftKnee, .rightKnee] {
            guard let point = visiblePoint(joint, in: pose) else { continue }
            drawRing(
                center: displayPoint(point, in: contentRect),
                radius: 14,
                color: highlightColor,
                lineWidth: 3.5,
                in: &context
            )
        }
    }

    private func drawTorsoGuide(
        in context: inout GraphicsContext,
        pose: PoseFrame,
        contentRect: CGRect
    ) {
        if let baselinePose {
            drawTorsoLine(
                in: &context,
                pose: baselinePose,
                contentRect: contentRect,
                color: .white.opacity(0.72),
                lineWidth: 3,
                dashed: true,
                showsVertical: false
            )
        }
        drawTorsoLine(
            in: &context,
            pose: pose,
            contentRect: contentRect,
            color: highlightColor,
            lineWidth: 5,
            dashed: false,
            showsVertical: true
        )
    }

    private func drawTorsoLine(
        in context: inout GraphicsContext,
        pose: PoseFrame,
        contentRect: CGRect,
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool,
        showsVertical: Bool
    ) {
        guard let shoulders = midpoint(.leftShoulder, .rightShoulder, in: pose),
              let hips = midpoint(.leftHip, .rightHip, in: pose) else { return }
        let shoulderPoint = displayPoint(shoulders, in: contentRect)
        let hipPoint = displayPoint(hips, in: contentRect)

        var torso = Path()
        torso.move(to: hipPoint)
        torso.addLine(to: shoulderPoint)
        context.stroke(
            torso,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                dash: dashed ? [8, 6] : []
            )
        )

        if showsVertical {
            var vertical = Path()
            vertical.move(to: CGPoint(
                x: hipPoint.x,
                y: max(contentRect.minY, hipPoint.y - contentRect.height * 0.34)
            ))
            vertical.addLine(to: CGPoint(
                x: hipPoint.x,
                y: min(contentRect.maxY, hipPoint.y + contentRect.height * 0.08)
            ))
            context.stroke(
                vertical,
                with: .color(.white.opacity(0.72)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5])
            )
        }
    }

    private func drawHandPathGuide(
        in context: inout GraphicsContext,
        pose: PoseFrame,
        contentRect: CGRect
    ) {
        if let shoulders = midpoint(.leftShoulder, .rightShoulder, in: pose),
           let hips = midpoint(.leftHip, .rightHip, in: pose) {
            let top = displayPoint(shoulders, in: contentRect)
            let bottom = displayPoint(hips, in: contentRect)
            var centerLine = Path()
            centerLine.move(to: top)
            centerLine.addLine(to: bottom)
            context.stroke(
                centerLine,
                with: .color(.white.opacity(0.58)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5])
            )
        }

        let trailPoints = handTrail.compactMap { handCenter(in: $0) }
            .map { displayPoint($0, in: contentRect) }
        if trailPoints.count >= 2 {
            var trail = Path()
            trail.move(to: trailPoints[0])
            for point in trailPoints.dropFirst() {
                trail.addLine(to: point)
            }
            context.stroke(
                trail,
                with: .color(highlightColor.opacity(0.9)),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
        }

        if let baselinePose, let baseline = handCenter(in: baselinePose) {
            let baselinePoint = displayPoint(baseline, in: contentRect)
            drawRing(
                center: baselinePoint,
                radius: 13,
                color: .white.opacity(0.84),
                lineWidth: 3,
                in: &context
            )
        }
        if let current = handCenter(in: pose) {
            let currentPoint = displayPoint(current, in: contentRect)
            drawRing(
                center: currentPoint,
                radius: 16,
                color: highlightColor,
                lineWidth: 4,
                in: &context
            )
        }
    }

    private func drawRing(
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        lineWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth)
        )
    }

    private func drawCrosshair(
        center: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: CGPoint(x: center.x - 10, y: center.y))
        path.addLine(to: CGPoint(x: center.x + 10, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - 10))
        path.addLine(to: CGPoint(x: center.x, y: center.y + 10))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5))
    }

    private func midpoint(
        _ first: PoseJoint,
        _ second: PoseJoint,
        in pose: PoseFrame
    ) -> PosePoint? {
        guard let firstPoint = visiblePoint(first, in: pose),
              let secondPoint = visiblePoint(second, in: pose) else { return nil }
        return PosePoint(
            x: (firstPoint.x + secondPoint.x) / 2,
            y: (firstPoint.y + secondPoint.y) / 2,
            confidence: min(firstPoint.confidence, secondPoint.confidence)
        )
    }

    private func headPoint(in pose: PoseFrame) -> PosePoint? {
        pose.headCenter(minimumConfidence: 0.25) ?? visiblePoint(.neck, in: pose)
    }

    private func handCenter(in pose: PoseFrame) -> PosePoint? {
        if let center = midpoint(.leftWrist, .rightWrist, in: pose) { return center }
        return visiblePoint(.leftWrist, in: pose) ?? visiblePoint(.rightWrist, in: pose)
    }

    private func displayPoint(_ point: PosePoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(point.x) * rect.width,
            y: rect.minY + CGFloat(point.y) * rect.height
        )
    }

    private func aspectFitRect(aspectRatio: CGFloat, in size: CGSize) -> CGRect {
        guard aspectRatio.isFinite, aspectRatio > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let containerRatio = size.width / size.height
        if containerRatio > aspectRatio {
            let width = size.height * aspectRatio
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / aspectRatio
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }
}

#Preview {
    PoseOverlayView(
        pose: PoseFrame(
            timestampSeconds: 1,
            joints: [
                .leftShoulder: PosePoint(x: 0.40, y: 0.28, confidence: 1),
                .rightShoulder: PosePoint(x: 0.58, y: 0.30, confidence: 1),
                .leftElbow: PosePoint(x: 0.36, y: 0.42, confidence: 1),
                .rightElbow: PosePoint(x: 0.61, y: 0.43, confidence: 1),
                .leftWrist: PosePoint(x: 0.48, y: 0.48, confidence: 1),
                .rightWrist: PosePoint(x: 0.50, y: 0.49, confidence: 1),
                .leftHip: PosePoint(x: 0.44, y: 0.54, confidence: 1),
                .rightHip: PosePoint(x: 0.56, y: 0.54, confidence: 1),
            ]
        ),
        videoAspectRatio: 9 / 16,
        highlightedJoints: [.leftWrist, .rightWrist]
    )
    .background(.black)
}
