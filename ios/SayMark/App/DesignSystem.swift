import SwiftUI

// MARK: - SayMark 设计系统 (基于 Figma 原型精确色彩)
// 来源: https://www.figma.com/make/NIbM1STnLt5mxS2XccykrV

enum DesignColor {
    /// iOS 系统蓝 #007AFF - 主色调、链接、选中态
    static let blue = Color(red: 0, green: 122/255, blue: 1)

    /// iOS 系统橙 #FF9500 - 提醒、事件标记
    static let orange = Color(red: 1, green: 149/255, blue: 0)

    /// iOS 系统红 #FF3B30 - 删除、取消、错误
    static let red = Color(red: 1, green: 59/255, blue: 48/255)

    /// iOS 系统绿 #34C759 - 成功、确认
    static let green = Color(red: 52/255, green: 199/255, blue: 89/255)

    /// 页面背景 #F2F2F7
    static let background = Color(red: 242/255, green: 242/255, blue: 247/255)

    /// 卡片背景 #FFFFFF
    static let card = Color.white

    /// 主文字 #000000
    static let label = Color.black

    /// 次文字 #3C3C43 (呈现为约60%透明度效果)
    static let label2 = Color(red: 60/255, green: 60/255, blue: 67/255)

    /// 三级文字/占位符 #8E8E93
    static let label3 = Color(red: 142/255, green: 142/255, blue: 147/255)

    /// 分割线 rgba(60,60,67,0.29)
    static let separator = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.29)

    /// 浅分割线 rgba(60,60,67,0.12)
    static let separatorLight = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.12)

    /// 填充色 rgba(120,120,128,0.12)
    static let fill = Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.12)

    /// 二级填充 rgba(120,120,128,0.16)
    static let fill2 = Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.16)

    /// AI 气泡灰 #E5E5EA
    static let bubbleGray = Color(red: 229/255, green: 229/255, blue: 234/255)

    /// Tab Bar 背景
    static let tabBarBg = Color(red: 248/255, green: 248/255, blue: 248/255)
}
