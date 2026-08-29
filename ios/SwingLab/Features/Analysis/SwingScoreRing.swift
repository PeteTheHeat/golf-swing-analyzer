import SwiftUI
struct SwingScoreRing: View {
    let score: Double
    var label = "Swing score"

    private var normalizedScore: Double {
        min(100, max(0, score))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 9)
            Circle()
                .trim(from: 0, to: normalizedScore / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 1, green: 0.25, blue: 0.30),
                            Color(red: 1, green: 0.56, blue: 0.34),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(normalizedScore, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ 100")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(normalizedScore)) out of 100")
    }
}
