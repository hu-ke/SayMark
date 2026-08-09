import SwiftUI

@main
struct SayMarkApp: App {
    init() {
        // Figma 颜色映射为 UIColor
        let navBg = UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)
        let label = UIColor.black
        let label3 = UIColor(red: 142/255, green: 142/255, blue: 147/255, alpha: 1)
        let blue = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)

        // 导航栏样式（匹配 Figma 原型）
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundColor = navBg
        navAppearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: label
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: label
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // Tab Bar 样式（匹配 Figma：rgba(248,248,248,.94) + blur + 分隔线）
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = UIColor(red: 248/255, green: 248/255, blue: 248/255, alpha: 0.94)

        // 顶部分隔线（Figma: border-top: .5px solid rgba(60,60,67,0.29)）
        tabAppearance.shadowColor = UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.29)
        tabAppearance.shadowImage = UIImage()

        // 文字样式（Figma: 10px, weight 500, letter-spacing -0.24）
        let itemFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: itemFont,
            .foregroundColor: label3
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: itemFont,
            .foregroundColor: blue
        ]

        // 纵向布局外观（Figma: 26px 图标 + 3px 间距 + 10px 文字）
        let itemAppearance = tabAppearance.stackedLayoutAppearance
        itemAppearance.normal.titleTextAttributes = normalAttrs
        itemAppearance.selected.titleTextAttributes = selectedAttrs
        itemAppearance.normal.iconColor = label3
        itemAppearance.selected.iconColor = blue

        // inline / compact 布局
        tabAppearance.inlineLayoutAppearance.normal.titleTextAttributes = normalAttrs
        tabAppearance.inlineLayoutAppearance.selected.titleTextAttributes = selectedAttrs
        tabAppearance.inlineLayoutAppearance.normal.iconColor = label3
        tabAppearance.inlineLayoutAppearance.selected.iconColor = blue

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // 全局列表/表格背景
        UITableView.appearance().backgroundColor = navBg
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(DesignColor.blue)
        }
    }
}
