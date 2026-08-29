import SwiftUI

/// Draws the same normalized pose coordinate space used by the analysis engine.
/// The parent should give this view the full player bounds and the source video's aspect ratio.
struct PoseOverlayView: View {
    let pose: PoseFrame?
    let videoAspectRatio: CGFloat
    var highlightedJoints: Set<PoseJoint> = []
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
