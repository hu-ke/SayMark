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
    private func requestEmpty(
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
        try await requestEmpty(path: "/api/folders/\(id)", method: "PUT", body: Body(name: name))
    }

    func deleteFolder(id: String) async throws {
        try await requestEmpty(path: "/api/folders/\(id)", method: "DELETE")
    }

    // MARK: - 文件

    func getFile(id: String) async throws -> NoteFile {
        try await request(path: "/api/files/\(id)", method: "GET")
    }

    func createFile(name: String, content: String, parentId: String) async throws -> NoteFile {
        struct Body: Encodable {
            let name: String; let content: String; let parent_id: String
        }
        return try await request(path: "/api/files", method: "POST",
                                 body: Body(name: name, content: content, parent_id: parentId))
    }

    func renameFile(id: String, name: String?) async throws {
        struct Body: Encodable { let name: String? }
        try await requestEmpty(path: "/api/files/\(id)", method: "PUT", body: Body(name: name))
    }

    func updateFileContent(id: String, content: String) async throws {
        struct Body: Encodable { let content: String }
        try await requestEmpty(path: "/api/files/\(id)/content", method: "PUT",
                               body: Body(content: content))
    }

    func deleteFile(id: String) async throws {
        try await requestEmpty(path: "/api/files/\(id)", method: "DELETE")
    }

    func moveFile(id: String, targetFolderId: String) async throws {
        struct Body: Encodable { let target_folder_id: String }
        try await requestEmpty(path: "/api/files/\(id)/move", method: "POST",
                               body: Body(target_folder_id: targetFolderId))
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
    func sendCommand(text: String) async throws -> CommandResult {
        struct Body: Encodable { let text: String }
        return try await request(path: "/api/ai/command", method: "POST", body: Body(text: text))
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
