import SwiftUI

struct SwingCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SwingTheme.Spacing.medium)
            .background(SwingTheme.surface, in: RoundedRectangle(
                cornerRadius: SwingTheme.Radius.large,
                style: .continuous
            ))
            .overlay {
                RoundedRectangle(cornerRadius: SwingTheme.Radius.large, style: .continuous)
                    .stroke(SwingTheme.hairline, lineWidth: 1)
            }
    }
}

struct SwingPill: View {
    let text: String
    var tint: Color = SwingTheme.elevated

    var body: some View {
        Text(text)
            .font(SwingTheme.Typography.caption.weight(.medium))
            .foregroundStyle(SwingTheme.cream)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint, in: Capsule())
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var trailingText: String? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: SwingTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: SwingTheme.Spacing.xSmall) {
                Text(eyebrow.uppercased())
                    .font(SwingTheme.Typography.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(SwingTheme.coral)
                Text(title)
                    .font(SwingTheme.Typography.title)
                    .foregroundStyle(SwingTheme.cream)
            }

            Spacer(minLength: 0)

            if let trailingText {
                Text(trailingText)
                    .font(SwingTheme.Typography.caption)
                    .foregroundStyle(SwingTheme.subtleText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScoreBadge: View {
    let score: Double?

    private var normalizedScore: Double {
        min(max((score ?? 0) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(SwingTheme.elevated, lineWidth: 5)
            Circle()
                .trim(from: 0, to: score == nil ? 0 : normalizedScore)
                .stroke(
                    SwingTheme.coral,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if let score {
                Text(score.formatted(.number.precision(.fractionLength(0))))
                    .font(SwingTheme.Typography.score)
                    .foregroundStyle(SwingTheme.cream)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SwingTheme.subtleText)
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityLabel(score.map { "Swing score \($0.formatted()) out of 100" } ?? "Swing not analyzed")
    }
}

struct SwingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SwingTheme.Typography.headline)
            .foregroundStyle(SwingTheme.deepCanvas)
            .padding(.horizontal, SwingTheme.Spacing.medium)
            .padding(.vertical, 14)
            .background(
                configuration.isPressed ? SwingTheme.coralPressed : SwingTheme.coral,
                in: RoundedRectangle(cornerRadius: SwingTheme.Radius.medium, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
