import SwiftUI

struct SettingsView: View {
    @State private var notificationsEnabled = true
    @State private var autoSave = true

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
                        Group {
                            SectionHeader(title: "通用")
                                .padding(.top, 20)
                            VStack(spacing: 0) {
                                ToggleRow(title: "通知提醒", isOn: $notificationsEnabled)
                                Divider().padding(.leading, 16)
                                ToggleRow(title: "自动保存", isOn: $autoSave)
                            }
                            .cardStyle()
                        }

                        Group {
                            SectionHeader(title: "关于")
                                .padding(.top, 10)
                            VStack(spacing: 0) {
                                InfoRow(title: "版本", value: "1.0.0")
                                Divider().padding(.leading, 16)
                                InfoRow(title: "SayMark", value: "语音记事本")
                            }
                            .cardStyle()
                        }
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

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
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

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(UIConstants.label)
                .kerning(-0.41)
            Spacer()
            Text(value)
                .font(.system(size: 17))
                .foregroundColor(UIConstants.label3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
