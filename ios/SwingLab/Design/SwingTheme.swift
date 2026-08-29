import SwiftUI
enum SwingTheme {
    static let canvas = Color(red: 0.043, green: 0.051, blue: 0.049)
    static let deepCanvas = Color(red: 0.024, green: 0.028, blue: 0.027)
    static let surface = Color(red: 0.090, green: 0.102, blue: 0.096)
    static let elevated = Color(red: 0.126, green: 0.137, blue: 0.129)
    static let cream = Color(red: 0.965, green: 0.941, blue: 0.871)
    static let mutedText = Color(red: 0.710, green: 0.712, blue: 0.672)
    static let subtleText = Color(red: 0.470, green: 0.480, blue: 0.452)
    static let coral = Color(red: 0.957, green: 0.353, blue: 0.290)
    static let coralPressed = Color(red: 0.824, green: 0.254, blue: 0.216)
    static let success = Color(red: 0.361, green: 0.776, blue: 0.596)
    static let hairline = Color.white.opacity(0.08)

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 36
        static let screen: CGFloat = 20
    }

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum Typography {
        static let hero = Font.system(size: 42, weight: .bold, design: .rounded)
        static let title = Font.system(size: 25, weight: .bold, design: .rounded)
        static let headline = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 13, weight: .regular, design: .rounded)
        static let eyebrow = Font.system(size: 12, weight: .bold, design: .rounded)
        static let score = Font.system(size: 20, weight: .bold, design: .rounded)
    }
}

private struct SwingScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                LinearGradient(
                    colors: [SwingTheme.canvas, SwingTheme.deepCanvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
    }
}

extension View {
    func swingScreenBackground() -> some View {
        modifier(SwingScreenBackground())
    }
}
