import Foundation
import SwiftUI

// MARK: - App Config

enum AppConfig {
    static let baseURL = "http://localhost:8000"
}

// MARK: - SayMark Design System

enum DesignTokens {
    enum Color {
        static let primary       = SwiftUI.Color(red: 0.17, green: 0.36, blue: 0.80)
        static let primaryLight  = SwiftUI.Color(red: 0.28, green: 0.51, blue: 0.95)
        static let primaryBg     = SwiftUI.Color(red: 0.93, green: 0.95, blue: 0.99)
        static let accent        = SwiftUI.Color(red: 1.00, green: 0.58, blue: 0.00)
        static let accentLight   = SwiftUI.Color(red: 1.00, green: 0.71, blue: 0.30)
        static let accentBg      = SwiftUI.Color(red: 1.00, green: 0.95, blue: 0.88)
        static let success       = SwiftUI.Color(red: 0.20, green: 0.78, blue: 0.35)
        static let warning       = SwiftUI.Color(red: 1.00, green: 0.58, blue: 0.00)
        static let error         = SwiftUI.Color(red: 1.00, green: 0.23, blue: 0.19)
        static let textPrimary   = SwiftUI.Color(.label)
        static let textSecondary = SwiftUI.Color(.secondaryLabel)
        static let textTertiary  = SwiftUI.Color(.tertiaryLabel)
        static let textOnPrimary = SwiftUI.Color.white
        static let bgBase        = SwiftUI.Color(.systemBackground)
        static let bgGrouped     = SwiftUI.Color(.systemGroupedBackground)
        static let bgSecondary   = SwiftUI.Color(.secondarySystemBackground)
        static let bgTertiary    = SwiftUI.Color(.tertiarySystemBackground)
        static let divider       = SwiftUI.Color(.separator)
        static let dividerLight  = SwiftUI.Color(.separator).opacity(0.5)
    }

    enum Font {
        static let largeTitle  = SwiftUI.Font.largeTitle.weight(.bold)
        static let title       = SwiftUI.Font.title.weight(.semibold)
        static let title2      = SwiftUI.Font.title2.weight(.semibold)
        static let title3      = SwiftUI.Font.title3.weight(.medium)
        static let headline    = SwiftUI.Font.headline
        static let body        = SwiftUI.Font.body
        static let callout     = SwiftUI.Font.callout
        static let subheadline = SwiftUI.Font.subheadline
        static let footnote    = SwiftUI.Font.footnote
        static let caption     = SwiftUI.Font.caption
        static let caption2    = SwiftUI.Font.caption2
        static let monoDigit   = SwiftUI.Font.system(.body, design: .rounded).monospacedDigit()
    }

    enum Spacing {
        static let xs:   CGFloat = 4
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 20
        static let xxl:  CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    enum CornerRadius {
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 20
        static let full: CGFloat = 99
    }

    enum Shadow {
        static let sm  = (color: SwiftUI.Color.black.opacity(0.06), radius: CGFloat(4),  y: CGFloat(2))
        static let md  = (color: SwiftUI.Color.black.opacity(0.08), radius: CGFloat(8),  y: CGFloat(4))
        static let lg  = (color: SwiftUI.Color.black.opacity(0.10), radius: CGFloat(16), y: CGFloat(8))
    }

    enum IconSize {
        static let sm:  CGFloat = 16
        static let md:  CGFloat = 22
        static let lg:  CGFloat = 28
        static let xl:  CGFloat = 36
        static let xxl: CGFloat = 48
    }
}

struct CardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: (color: Color, radius: CGFloat, y: CGFloat)
    init(cornerRadius: CGFloat = DesignTokens.CornerRadius.md,
         shadow: (color: Color, radius: CGFloat, y: CGFloat) = DesignTokens.Shadow.sm) {
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }
    func body(content: Content) -> some View {
        content.background(DesignTokens.Color.bgBase)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

struct BadgeStyle: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content.font(DesignTokens.Font.caption2).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color).clipShape(Capsule())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = DesignTokens.CornerRadius.md,
                   shadow: (color: Color, radius: CGFloat, y: CGFloat) = DesignTokens.Shadow.sm) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, shadow: shadow))
    }
    func badgeStyle(_ color: Color = DesignTokens.Color.accent) -> some View {
        modifier(BadgeStyle(color: color))
    }
}
