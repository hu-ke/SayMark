import Foundation

/// API 错误类型
enum APIError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case decodingError(Error)
    case networkError(Error)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的请求地址"
        case .httpError(let code, let message):
            return "请求失败(\(code)): \(message)"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .unknown(let message):
            return message
        }
    }
}

/// 空响应占位类型（DELETE / PUT 等无返回体使用）
struct EmptyResponse: Decodable {}

/// 后端 REST API 客户端（async/await + URLSession）
final class APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession

    init(baseURL: String = AppConfig.baseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - 通用请求

    /// 发送请求并返回原始数据
    private func sendRequest(
        path: String,
        method: String,
        body: Encodable? = nil
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        do {
            let (data, response) = try await session.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.unknown("无效的响应")
            }
            if !(200...299).contains(httpResponse.statusCode) {
                let message = parseErrorMessage(data: data) ?? "未知错误"
                throw APIError.httpError(httpResponse.statusCode, message)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// 请求并解码为指定类型
    private func request<T: Decodable>(
        path: String,
        method: String,
        body: Encodable? = nil
    ) async throws -> T {
        let data = try await sendRequest(path: path, method: method, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 请求无返回体
    func requestEmpty(
        path: String,
        method: String,
        body: Encodable? = nil
    ) async throws {
        _ = try await sendRequest(path: path, method: method, body: body)
    }

    private func parseErrorMessage(data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (json["detail"] as? String) ?? (json["message"] as? String)
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 文件夹

    func getFolderTree() async throws -> [TreeNode] {
        try await request(path: "/api/folders/tree", method: "GET")
    }

    func createFolder(name: String, parentId: String?) async throws -> Folder {
        struct Body: Encodable { let name: String; let parent_id: String? }
        return try await request(path: "/api/folders", method: "POST",
                                 body: Body(name: name, parent_id: parentId))
    }

    func renameFolder(id: String, name: String) async throws {
        struct Body: Encodable { let name: String }
        try await requestEmpty(path: "/api/folders/\(id)", method: "PATCH", body: Body(name: name))
    }

    func deleteFolder(id: String) async throws {
        try await requestEmpty(path: "/api/folders/\(id)", method: "DELETE")
    }

    // MARK: - 文件

    func getFile(id: String) async throws -> NoteFile {
        try await request(path: "/api/files/\(id)", method: "GET")
    }

    func createFile(name: String, content: String, parentId: String, type: String = "note", schedule: SchedulePayload? = nil) async throws -> NoteFile {
        struct Body: Encodable {
            let name: String; let content: String; let parent_id: String
            let type: String
            let schedule: SchedulePayload?
        }
        return try await request(path: "/api/files", method: "POST",
                                 body: Body(name: name, content: content, parent_id: parentId, type: type, schedule: schedule))
    }

    func renameFile(id: String, name: String?) async throws {
        struct Body: Encodable { let name: String? }
        try await requestEmpty(path: "/api/files/\(id)", method: "PATCH", body: Body(name: name))
    }

    func updateFileContent(id: String, content: String) async throws {
        struct Body: Encodable { let content: String }
        try await requestEmpty(path: "/api/files/\(id)", method: "PATCH",
                               body: Body(content: content))
    }

    func deleteFile(id: String) async throws {
        try await requestEmpty(path: "/api/files/\(id)", method: "DELETE")
    }

    func moveFile(id: String, targetFolderId: String) async throws {
        struct Body: Encodable { let target_folder_id: String }
        try await requestEmpty(path: "/api/files/\(id)/move", method: "PUT",
                               body: Body(target_folder_id: targetFolderId))
    }

    func moveFolder(id: String, targetFolderId: String?) async throws {
        struct Body: Encodable { let target_folder_id: String? }
        try await requestEmpty(path: "/api/folders/\(id)/move", method: "PUT",
                               body: Body(target_folder_id: targetFolderId))
    }

    func reorder(type: String, sourceId: String, targetId: String) async throws {
        struct Body: Encodable {
            let type: String
            let source_id: String
            let target_id: String
        }
        try await requestEmpty(path: "/api/reorder", method: "PUT",
                               body: Body(type: type, source_id: sourceId, target_id: targetId))
    }

    // MARK: - 笔记与 AI 指令

    /// 语音转笔记（POST /api/notes）
    func createNote(transcript: String, targetFolderId: String?) async throws -> NoteFile {
        struct Body: Encodable {
            let transcript: String; let target_folder_id: String?
        }
        return try await request(path: "/api/notes", method: "POST",
                                 body: Body(transcript: transcript, target_folder_id: targetFolderId))
    }

    /// 发送 AI 指令（POST /api/ai/command）
    func sendCommand(text: String, targetFileId: String? = nil) async throws -> CommandResult {
        struct Body: Encodable {
            let text: String
            let target_file_id: String?
        }
        return try await request(path: "/api/ai/command", method: "POST", body: Body(text: text, target_file_id: targetFileId))
    }

    /// 确认/取消待确认指令（POST /api/ai/command/confirm）
    func confirmCommand(confirmationId: String, confirmed: Bool) async throws -> CommandResult {
        struct Body: Encodable {
            let confirmation_id: String
            let confirmed: Bool
        }
        return try await request(path: "/api/ai/command/confirm", method: "POST",
                                 body: Body(confirmation_id: confirmationId, confirmed: confirmed))
    }

    // MARK: - 日程（Events）

    /// 获取某月有日程的日期（GET /api/events/month/{year}/{month}）
    func getMonthSummary(year: Int, month: Int) async throws -> [MonthSummaryItem] {
        try await request(path: "/api/events/month/\(year)/\(month)", method: "GET")
    }

    /// 获取某天的所有日程（GET /api/events/date/{date}）
    func getEventsByDate(_ date: String) async throws -> [CalendarEvent] {
        try await request(path: "/api/events/date/\(date)", method: "GET")
    }

    /// 删除日程（DELETE /api/events/{id}）
    func deleteEvent(id: String) async throws {
        try await requestEmpty(path: "/api/events/\(id)", method: "DELETE")
    }

    // MARK: - 提醒（Reminders）

    /// 获取所有带提醒的日程（GET /api/reminders）
    func getReminders() async throws -> [CalendarEvent] {
        try await request(path: "/api/reminders", method: "GET")
    }

    /// 获取所有提醒（返回 NoteFile 列表，用于通知调度）
    func getReminderNotes() async throws -> [NoteFile] {
        try await request(path: "/api/reminders", method: "GET")
    }

    /// 取消提醒（PATCH /api/reminders/{id}）
    func cancelReminder(id: String) async throws {
        try await requestEmpty(path: "/api/reminders/\(id)", method: "PATCH")
    }
}

/// 用于编码任意 Encodable 的类型擦除包装
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self._encode = { try wrapped.encode(to: $0) }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
