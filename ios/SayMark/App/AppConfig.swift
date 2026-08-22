import Foundation

enum AppConfig {
    // 模拟器（Mac 上调试）走本机；真机走远程服务器
    #if targetEnvironment(simulator)
    static let baseURL = "http://localhost:8000/saymark-service"
    #else
    static let baseURL = "https://scenelingo.today/saymark-service"
    #endif
}
