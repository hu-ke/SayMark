import SwiftUI

struct SettingsView: View {
    @State private var notificationsEnabled = true
    @State private var autoSave = true
    @State private var hapticFeedback = false
    @State private var locationService = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Spacer()
                    Text("设置")
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.82)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) { HDSeparator() }

                ScrollView {
                    VStack(spacing: 10) {
                        // 通用
                        Group {
                            SectionHeader(title: "通用")
                                .padding(.top, 20)
                            VStack(spacing: 0) {
                                SettingsToggleRow(icon: "bell.fill", iconColor: UIConstants.red,
                                                  title: "通知提醒", isOn: $notificationsEnabled)
                                Divider().padding(.leading, 56)
                                SettingsToggleRow(iconType: "doc", iconColor: UIConstants.blue,
                                                  title: "自动保存", isOn: $autoSave)
                                Divider().padding(.leading, 56)
                                SettingsToggleRow(icon: "repeat", iconColor: UIConstants.purple,
                                                  title: "震动反馈", isOn: $hapticFeedback)
                                Divider().padding(.leading, 56)
                                SettingsToggleRow(icon: "mappin.and.ellipse", iconColor: UIConstants.green,
                                                  title: "位置服务", isOn: $locationService)
                            }
                            .cardStyle()
                        }

                        // AI 助手
                        Group {
                            SectionHeader(title: "AI 助手")
                                .padding(.top, 10)
                            VStack(spacing: 0) {
                                SettingsLinkRow(icon: "brain.head.profile", iconColor: UIConstants.orange,
                                                title: "思考模式", subtitle: "推理时展示思考步骤")
                                Divider().padding(.leading, 56)
                                SettingsLinkRow(iconType: "chat", iconColor: UIConstants.teal,
                                                title: "历史记录", subtitle: "管理 AI 对话历史")
                            }
                            .cardStyle()
                        }

                        // 归档
                        Group {
                            SectionHeader(title: "归档")
                                .padding(.top, 10)
                            VStack(spacing: 0) {
                                NavigationLink {
                                    ArchiveView()
                                } label: {
                                    HStack(spacing: 12) {
                                        RowIcon(systemName: "archivebox", color: UIConstants.orange)
                                        Text("归档")
                                            .font(.system(size: 17))
                                            .foregroundColor(UIConstants.label)
                                            .kerning(-0.41)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(UIConstants.label3)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .cardStyle()
                        }

                        // 关于
                        Group {
                            SectionHeader(title: "关于")
                                .padding(.top, 10)
                            VStack(spacing: 0) {
                                SettingsInfoRow(icon: "mic.fill", iconColor: UIConstants.blue,
                                                title: "SayMark 语音记事本")
                                Divider().padding(.leading, 56)
                                SettingsValueRow(title: "版本", value: "1.0.0")
                                Divider().padding(.leading, 16)
                                SettingsLinkRow(title: "隐私政策")
                                Divider().padding(.leading, 16)
                                SettingsLinkRow(title: "用户协议")
                            }
                            .cardStyle()
                        }

                        // App 图标
                        VStack(spacing: 10) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 38))
                                .foregroundColor(.white)
                                .frame(width: 72, height: 72)
                                .background(UIConstants.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .shadow(color: UIConstants.blue.opacity(0.33), radius: 24, y: 8)
                            Text("SayMark")
                                .font(.system(size: 13))
                                .foregroundColor(UIConstants.label3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    }
                    .padding(.horizontal, 16)

                    Color.clear.frame(height: 40)
                }
                .background(UIConstants.background)
            }
            .background(UIConstants.background)
        }
    }
}

// MARK: - 带图标 + 开关的行
private struct SettingsToggleRow: View {
    var icon: String? = nil
    var iconType: String? = nil
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: icon, iconType: iconType, color: iconColor)
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(UIConstants.label)
                .kerning(-0.41)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(UIConstants.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - 带图标（可选）+ 副标题 + 右箭头的行
private struct SettingsLinkRow: View {
    var icon: String? = nil
    var iconType: String? = nil
    var iconColor: Color = .clear
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if icon != nil || iconType != nil {
                RowIcon(systemName: icon, iconType: iconType, color: iconColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.41)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(UIConstants.label3)
                        .kerning(-0.08)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(UIConstants.label3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - 带图标 + 标题（无右箭头，用于「SayMark 语音记事本」）
private struct SettingsInfoRow: View {
    var icon: String? = nil
    var iconType: String? = nil
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: icon, iconType: iconType, color: iconColor)
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(UIConstants.label)
                .kerning(-0.41)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - 标题（次要色）+ 值（用于「版本」）
private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(UIConstants.label3)
                .kerning(-0.41)
            Spacer()
            Text(value)
                .font(.system(size: 16))
                .foregroundColor(UIConstants.label3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
