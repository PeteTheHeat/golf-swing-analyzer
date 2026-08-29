import SwiftUI

public struct TrimTimelineView: View {
    @Binding private var selection: TrimSelection
    private let thumbnails: [VideoThumbnail]
    private let currentTime: TimeInterval
    private let onSeek: (TimeInterval) -> Void
    private let onScrubbingChanged: (Bool) -> Void

    @State private var startDragOrigin: TimeInterval?
    @State private var endDragOrigin: TimeInterval?
    @State private var rangeDragOrigin: TimeInterval?
    @State private var isTimelineScrubbing = false

    private let railHeight: CGFloat = 68
    private let handleWidth: CGFloat = 28

    public init(
        selection: Binding<TrimSelection>,
        thumbnails: [VideoThumbnail],
        currentTime: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void,
        onScrubbingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._selection = selection
        self.thumbnails = thumbnails
        self.currentTime = currentTime
        self.onSeek = onSeek
        self.onScrubbingChanged = onScrubbingChanged
    }

    public var body: some View {
        GeometryReader { proxy in
            let inset = handleWidth / 2
            let timelineWidth = max(1, proxy.size.width - handleWidth)
            let startX = inset + (timelineWidth * selection.normalizedStart)
            let endX = inset + (timelineWidth * selection.normalizedEnd)
            let playheadX = inset + (
                timelineWidth * selection.progress(for: currentTime)
            )

            ZStack(alignment: .topLeading) {
                filmstrip(width: timelineWidth)
                    .frame(width: timelineWidth, height: railHeight)
                    .offset(x: inset)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                unselectedShade(width: max(0, startX - inset))
                    .offset(x: inset)

                unselectedShade(width: max(0, inset + timelineWidth - endX))
                    .offset(x: endX)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(red: 1, green: 0.42, blue: 0.34), lineWidth: 3)
                    .frame(width: max(0, endX - startX), height: railHeight)
                    .offset(x: startX)
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: timelineWidth, height: railHeight)
                    .offset(x: inset)
                    .gesture(timelineGesture(timelineWidth: timelineWidth))
                    .accessibilityLabel("Video timeline")
                    .accessibilityValue(
                        "Playhead at \(Self.formatTime(currentTime))"
                    )

                selectedRangeMover(
                    width: max(1, endX - startX),
                    timelineWidth: timelineWidth
                )
                .offset(x: startX)

                playhead
                    .offset(x: playheadX - 1)
                    .allowsHitTesting(false)

                trimHandle(edge: .leading)
                    .offset(x: startX - (handleWidth / 2))
                    .gesture(startHandleGesture(timelineWidth: timelineWidth))
                    .accessibilityLabel("Trim start")
                    .accessibilityValue(Self.formatTime(selection.start))
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment
                            ? selection.frameDuration
                            : -selection.frameDuration
                        selection.setStart(selection.start + delta)
                        onSeek(selection.start)
                    }

                trimHandle(edge: .trailing)
                    .offset(x: endX - (handleWidth / 2))
                    .gesture(endHandleGesture(timelineWidth: timelineWidth))
                    .accessibilityLabel("Trim end")
                    .accessibilityValue(Self.formatTime(selection.end))
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment
                            ? selection.frameDuration
                            : -selection.frameDuration
                        selection.setEnd(selection.end + delta)
                        onSeek(selection.end)
                    }
            }
        }
        .frame(height: railHeight)
    }

    @ViewBuilder
    private func filmstrip(width: CGFloat) -> some View {
        if thumbnails.isEmpty {
            ZStack {
                Color.white.opacity(0.08)
                ProgressView()
                    .tint(.white)
            }
        } else {
            HStack(spacing: 0) {
                ForEach(thumbnails) { thumbnail in
                    Image(decorative: thumbnail.image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: width / CGFloat(thumbnails.count),
                            height: railHeight
                        )
                        .clipped()
                }
            }
        }
    }

    private func unselectedShade(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.62))
            .frame(width: width, height: railHeight)
            .allowsHitTesting(false)
    }

    private var playhead: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.white)
                .frame(width: 2, height: railHeight + 8)
                .shadow(color: .black.opacity(0.5), radius: 2)
            Circle()
                .fill(.white)
                .frame(width: 9, height: 9)
                .offset(y: -4)
        }
    }

    private func selectedRangeMover(
        width: CGFloat,
        timelineWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())

            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.top, 4)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: railHeight)
        .gesture(rangeGesture(timelineWidth: timelineWidth))
        .accessibilityLabel("Move selected clip")
        .accessibilityValue(
            "\(Self.formatTime(selection.start)) to \(Self.formatTime(selection.end))"
        )
        .accessibilityHint("Drag left or right to move the full trim window")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.5 : -0.5
            selection.moveRange(by: delta)
            onSeek(selection.start)
        }
    }

    private enum HandleEdge {
        case leading
        case trailing
    }

    private func trimHandle(edge: HandleEdge) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: edge == .leading ? 9 : 3,
                bottomLeadingRadius: edge == .leading ? 9 : 3,
                bottomTrailingRadius: edge == .trailing ? 9 : 3,
                topTrailingRadius: edge == .trailing ? 9 : 3,
                style: .continuous
            )
            .fill(Color(red: 1, green: 0.42, blue: 0.34))

            HStack(spacing: 2) {
                Capsule().fill(.white.opacity(0.9)).frame(width: 2, height: 18)
                Capsule().fill(.white.opacity(0.9)).frame(width: 2, height: 18)
            }
        }
        .frame(width: handleWidth, height: railHeight)
        .contentShape(Rectangle())
    }

    private func timelineGesture(timelineWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTimelineScrubbing {
                    isTimelineScrubbing = true
                    onScrubbingChanged(true)
                }
                let progress = min(max(value.location.x / timelineWidth, 0), 1)
                onSeek(selection.assetDuration * progress)
            }
            .onEnded { _ in
                isTimelineScrubbing = false
                onScrubbingChanged(false)
            }
    }

    private func startHandleGesture(timelineWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if startDragOrigin == nil {
                    startDragOrigin = selection.start
                    onScrubbingChanged(true)
                }
                let secondsDelta = TimeInterval(
                    value.translation.width / timelineWidth
                ) * selection.assetDuration
                selection.setStart((startDragOrigin ?? selection.start) + secondsDelta)
                onSeek(selection.start)
            }
            .onEnded { _ in
                startDragOrigin = nil
                onScrubbingChanged(false)
            }
    }

    private func endHandleGesture(timelineWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if endDragOrigin == nil {
                    endDragOrigin = selection.end
                    onScrubbingChanged(true)
                }
                let secondsDelta = TimeInterval(
                    value.translation.width / timelineWidth
                ) * selection.assetDuration
                selection.setEnd((endDragOrigin ?? selection.end) + secondsDelta)
                onSeek(selection.end)
            }
            .onEnded { _ in
                endDragOrigin = nil
                onScrubbingChanged(false)
            }
    }

    private func rangeGesture(timelineWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if rangeDragOrigin == nil {
                    rangeDragOrigin = selection.start
                    onScrubbingChanged(true)
                }
                let secondsDelta = TimeInterval(
                    value.translation.width / timelineWidth
                ) * selection.assetDuration
                selection.moveRange(
                    toStart: (rangeDragOrigin ?? selection.start) + secondsDelta
                )
                onSeek(selection.start)
            }
            .onEnded { _ in
                rangeDragOrigin = nil
                onScrubbingChanged(false)
            }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = Int(safeSeconds) / 60
        let remainingSeconds = safeSeconds - (Double(minutes) * 60)
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
    }
}
