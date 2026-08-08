import Foundation

/// 设备标识：持久化在 UserDefaults 中，用于关联后端用户 Profile
struct DeviceID {
    static let shared = DeviceID()

    private let key = "saymark_device_id"

    var id: String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private init() {}
}
