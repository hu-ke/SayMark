import SwiftUI

// MARK: - Color Tokens
enum UIConstants {
    static let blue       = Color(red: 0.000, green: 0.478, blue: 1.000)    // #007AFF
    static let orange     = Color(red: 1.000, green: 0.584, blue: 0.000)    // #FF9500
    static let red        = Color(red: 1.000, green: 0.231, blue: 0.188)    // #FF3B30
    static let green      = Color(red: 0.204, green: 0.780, blue: 0.349)    // #34C759
    static let background = Color(red: 0.949, green: 0.949, blue: 0.969)    // #F2F2F7
    static let card       = Color.white
    static let label      = Color.black
    static let label2     = Color(red: 0.235, green: 0.235, blue: 0.263)    // #3C3C43
    static let label3     = Color(red: 0.557, green: 0.557, blue: 0.576)    // #8E8E93
    static let separator  = Color(red: 0.235, green: 0.235, blue: 0.263, opacity: 0.29)
    static let separator2 = Color(red: 0.235, green: 0.235, blue: 0.263, opacity: 0.12)
    static let fill       = Color(red: 0.471, green: 0.471, blue: 0.502, opacity: 0.12)
    static let fill2      = Color(red: 0.471, green: 0.471, blue: 0.502, opacity: 0.16)

    static let folderColors: [Color] = [
        blue,
        orange,
        green,
        Color(red: 0.686, green: 0.322, blue: 0.871),  // #AF52DE purple
        Color(red: 0.353, green: 0.784, blue: 0.980),  // #5AC8FA teal
        Color(red: 1.000, green: 0.176, blue: 0.333),  // #FF2D55 pink
        Color(red: 0.000, green: 0.000, blue: 0.000),  // black
    ]
}

// MARK: - TabBar
struct SayMarkTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(String, String)] = [
        ("doc", "文件"),
        ("cal", "日历"),
        ("bell", "提醒"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HDSeparator()
            HStack(spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { i in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = i
                        }
                    } label: {
                        VStack(spacing: 3) {
                            TabIcon(
                                type: tabs[i].0,
                                size: 26,
                                color: selectedTab == i ? UIConstants.blue : UIConstants.label3,
                                strokeWidth: selectedTab == i ? 2 : 1.6
                            )
                            Text(tabs[i].1)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedTab == i ? UIConstants.blue : UIConstants.label3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 9)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 83)
        .background(
            Color(red: 0.973, green: 0.973, blue: 0.973, opacity: 0.94)
                .background(Material.ultraThin)
        )
    }
}

// MARK: - Custom Tab Icons (matching "iOS App UI Redesign")
struct TabIcon: View {
    let type: String
    let size: CGFloat
    let color: Color
    var strokeWidth: CGFloat = 1.6

    var body: some View {
        Group {
            switch type {
            case "doc":    DocIcon()
            case "cal":    CalIcon()
            case "bell":   BellIcon()
            case "bell-off": BellOffIcon()
            case "folder": FolderIcon()
            case "chat":   ChatIcon()
            case "menu":   MenuIcon()
            case "compose": ComposeIcon()
            case "mic":    MicIcon()
            default:       DocIcon()
            }
        }
        .frame(width: size, height: size)
        .environment(\.tabIconColor, color)
        .environment(\.tabIconStrokeWidth, strokeWidth)
    }
}

// MARK: - Doc Icon (document with lines)
private struct TabIconColorKey: EnvironmentKey {
    static let defaultValue: Color = .black
}
private struct TabIconStrokeWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.6
}
extension EnvironmentValues {
    var tabIconColor: Color {
        get { self[TabIconColorKey.self] }
        set { self[TabIconColorKey.self] = newValue }
    }
    var tabIconStrokeWidth: CGFloat {
        get { self[TabIconStrokeWidthKey.self] }
        set { self[TabIconStrokeWidthKey.self] = newValue }
    }
}

private struct DocIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            Path { path in
                // Document body
                path.move(to: CGPoint(x: 14, y: 2))
                path.addLine(to: CGPoint(x: 6, y: 2))
                path.addCurve(to: CGPoint(x: 4, y: 4),
                              control1: CGPoint(x: 6 - 0.55*2, y: 2),
                              control2: CGPoint(x: 4, y: 4 - 0.55*2))
                path.addLine(to: CGPoint(x: 4, y: 20))
                path.addCurve(to: CGPoint(x: 6, y: 22),
                              control1: CGPoint(x: 4, y: 20 + 0.55*2),
                              control2: CGPoint(x: 6 - 0.55*2, y: 22))
                path.addLine(to: CGPoint(x: 18, y: 22))
                path.addCurve(to: CGPoint(x: 20, y: 20),
                              control1: CGPoint(x: 18 + 0.55*2, y: 22),
                              control2: CGPoint(x: 20, y: 20 + 0.55*2))
                path.addLine(to: CGPoint(x: 20, y: 8))
                path.closeSubpath()
                // Fold corner
                path.move(to: CGPoint(x: 14, y: 2))
                path.addLine(to: CGPoint(x: 14, y: 8))
                path.addLine(to: CGPoint(x: 20, y: 8))
                // Text line 1
                path.move(to: CGPoint(x: 16, y: 13))
                path.addLine(to: CGPoint(x: 8, y: 13))
                // Text line 2
                path.move(to: CGPoint(x: 16, y: 17))
                path.addLine(to: CGPoint(x: 8, y: 17))
                // Text line 3 (shorter)
                path.move(to: CGPoint(x: 10, y: 9))
                path.addLine(to: CGPoint(x: 8, y: 9))
            }
            .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round, lineJoin: .round))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct CalIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            Path { path in
                // Calendar body rounded rect
                path.move(to: CGPoint(x: 3 + 2, y: 4))
                path.addLine(to: CGPoint(x: 21 - 2, y: 4))
                path.addCurve(to: CGPoint(x: 21, y: 4 + 2),
                              control1: CGPoint(x: 21, y: 4),
                              control2: CGPoint(x: 21, y: 4))
                path.addLine(to: CGPoint(x: 21, y: 22 - 2))
                path.addCurve(to: CGPoint(x: 21 - 2, y: 22),
                              control1: CGPoint(x: 21, y: 22),
                              control2: CGPoint(x: 21, y: 22))
                path.addLine(to: CGPoint(x: 3 + 2, y: 22))
                path.addCurve(to: CGPoint(x: 3, y: 22 - 2),
                              control1: CGPoint(x: 3, y: 22),
                              control2: CGPoint(x: 3, y: 22))
                path.addLine(to: CGPoint(x: 3, y: 4 + 2))
                path.addCurve(to: CGPoint(x: 3 + 2, y: 4),
                              control1: CGPoint(x: 3, y: 4),
                              control2: CGPoint(x: 3, y: 4))
                path.closeSubpath()
                // Top pins
                path.move(to: CGPoint(x: 16, y: 2))
                path.addLine(to: CGPoint(x: 16, y: 6))
                path.move(to: CGPoint(x: 8, y: 2))
                path.addLine(to: CGPoint(x: 8, y: 6))
                // Horizontal divider
                path.move(to: CGPoint(x: 3, y: 10))
                path.addLine(to: CGPoint(x: 21, y: 10))
            }
            .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round, lineJoin: .round))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct ChatIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            Path { path in
                path.move(to: CGPoint(x: 21, y: 15))
                path.addCurve(to: CGPoint(x: 19, y: 17),
                              control1: CGPoint(x: 21, y: 15 + 2*0.552),
                              control2: CGPoint(x: 19 + 2*0.552, y: 17))
                path.addLine(to: CGPoint(x: 7, y: 17))
                path.addLine(to: CGPoint(x: 3, y: 21))
                path.addLine(to: CGPoint(x: 3, y: 5))
                path.addCurve(to: CGPoint(x: 5, y: 3),
                              control1: CGPoint(x: 3, y: 5 - 2*0.552),
                              control2: CGPoint(x: 5 - 2*0.552, y: 3))
                path.addLine(to: CGPoint(x: 19, y: 3))
                path.addCurve(to: CGPoint(x: 21, y: 5),
                              control1: CGPoint(x: 19 + 2*0.552, y: 3),
                              control2: CGPoint(x: 21, y: 5 - 2*0.552))
                path.addLine(to: CGPoint(x: 21, y: 15))
                path.closeSubpath()
            }
            .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round, lineJoin: .round))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct MenuIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            Path { path in
                path.move(to: CGPoint(x: 3, y: 7))
                path.addLine(to: CGPoint(x: 21, y: 7))
                path.move(to: CGPoint(x: 3, y: 12))
                path.addLine(to: CGPoint(x: 21, y: 12))
                path.move(to: CGPoint(x: 3, y: 17))
                path.addLine(to: CGPoint(x: 21, y: 17))
            }
            .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct ComposeIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            Path { path in
                // Horizontal line: M12 20h9
                path.move(to: CGPoint(x: 12, y: 20))
                path.addLine(to: CGPoint(x: 21, y: 20))
                // Pencil shape: M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4z
                path.move(to: CGPoint(x: 16.5, y: 3.5))
                path.addCurve(to: CGPoint(x: 19.5, y: 6.5),
                              control1: CGPoint(x: 16.5 + 2.12*0.552, y: 3.5 - 2.12*0.552),
                              control2: CGPoint(x: 19.5, y: 6.5 - 2.12*0.552))
                path.addLine(to: CGPoint(x: 7, y: 19))
                path.addLine(to: CGPoint(x: 3, y: 20))
                path.addLine(to: CGPoint(x: 4, y: 16))
                path.addLine(to: CGPoint(x: 16.5, y: 3.5))
                path.closeSubpath()
            }
            .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round, lineJoin: .round))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct MicIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            ZStack {
                // Mic body (filled rounded rect)
                Path { path in
                    path.move(to: CGPoint(x: 9 + 3, y: 1))
                    path.addLine(to: CGPoint(x: 15 - 3, y: 1))
                    path.addCurve(to: CGPoint(x: 15, y: 1 + 3),
                                  control1: CGPoint(x: 15, y: 1),
                                  control2: CGPoint(x: 15, y: 1))
                    path.addLine(to: CGPoint(x: 15, y: 14 - 3))
                    path.addCurve(to: CGPoint(x: 15 - 3, y: 14),
                                  control1: CGPoint(x: 15, y: 14),
                                  control2: CGPoint(x: 15, y: 14))
                    path.addLine(to: CGPoint(x: 9 + 3, y: 14))
                    path.addCurve(to: CGPoint(x: 9, y: 14 - 3),
                                  control1: CGPoint(x: 9, y: 14),
                                  control2: CGPoint(x: 9, y: 14))
                    path.addLine(to: CGPoint(x: 9, y: 1 + 3))
                    path.addCurve(to: CGPoint(x: 9 + 3, y: 1),
                                  control1: CGPoint(x: 9, y: 1),
                                  control2: CGPoint(x: 9, y: 1))
                    path.closeSubpath()
                }
                .fill(color)
                // Arc and stand (stroke)
                Path { path in
                    path.move(to: CGPoint(x: 19, y: 10))
                    path.addCurve(to: CGPoint(x: 5, y: 10),
                                  control1: CGPoint(x: 19, y: 10 - 2*0.552),
                                  control2: CGPoint(x: 5, y: 10 - 2*0.552))
                    path.move(to: CGPoint(x: 12, y: 19))
                    path.addLine(to: CGPoint(x: 12, y: 23))
                    path.move(to: CGPoint(x: 8, y: 23))
                    path.addLine(to: CGPoint(x: 16, y: 23))
                }
                .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round, lineJoin: .round))
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct BellIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            ZStack {
                // Bell body (filled)
                Path { path in
                    path.move(to: CGPoint(x: 18, y: 8))
                    // Top curve right to left
                    path.addCurve(to: CGPoint(x: 6, y: 8),
                                  control1: CGPoint(x: 18, y: 8 - 6*0.552),
                                  control2: CGPoint(x: 6, y: 8 - 6*0.552))
                    // Bottom left
                    path.addLine(to: CGPoint(x: 6, y: 8))
                    // Drop to bottom left corner
                    path.addLine(to: CGPoint(x: 3, y: 18))
                    // Bottom line
                    path.addLine(to: CGPoint(x: 21, y: 18))
                    // Back up right side
                    path.addLine(to: CGPoint(x: 18, y: 8))
                    path.closeSubpath()
                }
                .fill(color)
                .scaleEffect(x: 0.88, y: 1.08, anchor: .center)
                // Bell bottom curve (stroke)
                Path { path in
                    path.move(to: CGPoint(x: 13.73, y: 21.5))
                    path.addCurve(to: CGPoint(x: 10.27, y: 21.5),
                                  control1: CGPoint(x: 13.73 - 1.73, y: 21.5 + 2*0.552),
                                  control2: CGPoint(x: 10.27 + 1.73, y: 21.5 + 2*0.552))
                }
                .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round))
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct BellOffIcon: View {
    @Environment(\.tabIconColor) var color
    @Environment(\.tabIconStrokeWidth) var sw

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            Path { path in
                // Bottom curve
                path.move(to: CGPoint(x: 13.73, y: 21))
                path.addCurve(to: CGPoint(x: 10.27, y: 21),
                              control1: CGPoint(x: 13.73 - 1.73, y: 21 + 2*0.552),
                              control2: CGPoint(x: 10.27 + 1.73, y: 21 + 2*0.552))
                // Right side going up
                path.move(to: CGPoint(x: 18.63, y: 13))
                path.addCurve(to: CGPoint(x: 18, y: 8),
                              control1: CGPoint(x: 18.63, y: 13 - 5*0.552),
                              control2: CGPoint(x: 18 + 0.63*0.552, y: 8))
                // Left side + bottom
                path.move(to: CGPoint(x: 6.26, y: 6.26))
                path.addCurve(to: CGPoint(x: 6, y: 8),
                              control1: CGPoint(x: 6.26 - 0.26*0.552, y: 6.26 + 1.74*0.552),
                              control2: CGPoint(x: 6, y: 8 - 1.74*0.552))
                path.addLine(to: CGPoint(x: 6, y: 8))
                path.addLine(to: CGPoint(x: 3, y: 17))
                path.addLine(to: CGPoint(x: 17, y: 17))
                // Partial top
                path.move(to: CGPoint(x: 18, y: 8))
                path.addCurve(to: CGPoint(x: 8.67, y: 3),
                              control1: CGPoint(x: 18, y: 8 - 6*0.552),
                              control2: CGPoint(x: 8.67 + 9.33*0.552, y: 3))
                // Strike line
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: 23, y: 23))
            }
            .stroke(color, style: StrokeStyle(lineWidth: sw * scale, lineCap: .round, lineJoin: .round))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

private struct FolderIcon: View {
    @Environment(\.tabIconColor) var color

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let scale = s / 24
            Path { path in
                // M3 7.5A2.5 2.5 0 015.5 5h3.76
                path.move(to: CGPoint(x: 3, y: 7.5))
                path.addCurve(to: CGPoint(x: 5.5, y: 5),
                              control1: CGPoint(x: 3, y: 7.5 - 2.5*0.552),
                              control2: CGPoint(x: 5.5 - 2.5*0.552, y: 5))
                path.addLine(to: CGPoint(x: 9.26, y: 5))
                // a1 1 0 01.707.293l1.12 1.12
                path.addCurve(to: CGPoint(x: 11.794, y: 6.7),
                              control1: CGPoint(x: 9.26 + 1*0.448, y: 5 + 1*0.448),
                              control2: CGPoint(x: 11.794 - 1*0.448, y: 6.7 - 1*0.448))
                // H18.5A2.5 2.5 0 0121 9.2V17.5
                path.addLine(to: CGPoint(x: 18.5, y: 6.7))
                path.addCurve(to: CGPoint(x: 21, y: 9.2),
                              control1: CGPoint(x: 18.5 + 2.5*0.552, y: 6.7),
                              control2: CGPoint(x: 21, y: 9.2 - 2.5*0.552))
                path.addLine(to: CGPoint(x: 21, y: 17.5))
                // A2.5 2.5 0 0118.5 20h-13
                path.addCurve(to: CGPoint(x: 18.5, y: 20),
                              control1: CGPoint(x: 21, y: 17.5 + 2.5*0.552),
                              control2: CGPoint(x: 18.5 + 2.5*0.552, y: 20))
                path.addLine(to: CGPoint(x: 5.5, y: 20))
                // A2.5 2.5 0 013 17.5v-10
                path.addCurve(to: CGPoint(x: 3, y: 17.5),
                              control1: CGPoint(x: 5.5 - 2.5*0.552, y: 20),
                              control2: CGPoint(x: 3, y: 17.5 + 2.5*0.552))
                path.addLine(to: CGPoint(x: 3, y: 7.5))
                path.closeSubpath()
            }
            .fill(color)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (s - 24*scale) / 2, y: (s - 24*scale) / 2)
        }
    }
}

// MARK: - Separator Line
struct HDSeparator: View {
    var body: some View {
        Rectangle()
            .fill(UIConstants.separator)
            .frame(height: 0.5)
    }
}

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(UIConstants.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Standard Row Icon
struct RowIcon: View {
    var systemName: String? = nil
    var iconType: String? = nil   // "doc", "cal", "folder"
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size > 28 ? 8 : 6)
                .fill(color)
                .frame(width: size, height: size)

            if let type = iconType {
                TabIcon(type: type, size: 16, color: .white, strokeWidth: 2)
            } else if let name = systemName {
                Image(systemName: name)
                    .font(.system(size: size > 28 ? 16 : 14))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - FAB Button
struct FABButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TabIcon(type: "mic", size: 28, color: .white, strokeWidth: 2)
                .frame(width: 56, height: 56)
                .background(Circle().fill(UIConstants.blue))
                .shadow(color: UIConstants.blue.opacity(0.45), radius: 10, y: 4)
        }
    }
}

// MARK: - Badge
struct CapsuleBadge: View {
    let text: String
    var color: Color = UIConstants.orange
    var foregroundColor: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Thinking Card (for AI chat)
struct ThinkingCard: View {
    let stepCount: Int
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18))
                        .foregroundColor(UIConstants.orange)

                    Text(isExpanded ? "正在处理..." : "处理完成（\(stepCount)步）")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(UIConstants.orange)

                    Spacer()

                    CapsuleBadge(text: "\(stepCount)步",
                                 color: UIConstants.orange.opacity(0.14),
                                 foregroundColor: UIConstants.orange)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(UIConstants.orange)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(red: 1.000, green: 0.980, blue: 0.961))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(UIConstants.orange.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Standard Section Header
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .textCase(.uppercase)
            .foregroundColor(UIConstants.label3)
            .kerning(0.065)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
    }
}

// MARK: - Sheet Handle
struct SheetHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: 0.235, green: 0.235, blue: 0.263, opacity: 0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
    }
}
