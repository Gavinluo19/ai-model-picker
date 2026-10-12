import Foundation
import Security

enum KeyVault {
    static let service = "local.gavin.taskrouter.jev"
    static let account = "personal-api-key"
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    static func load() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw RouterError("无法读取本应用的钥匙串项目，请确认钥匙串已解锁。")
        }
        return value
    }
    static func save(_ raw: String) throws {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 4096, !value.contains("\n"), !value.contains("\r") else { throw RouterError("请输入有效的单行 API Key。") }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; attributes.forEach { add[$0.key] = $0.value }
            add[kSecAttrLabel as String] = "任务选模 · JEV"
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw RouterError("密钥未保存。请检查钥匙串权限。") }
        } else if update != errSecSuccess { throw RouterError("密钥未保存。请检查钥匙串权限。") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RouterError("无法删除钥匙串中的密钥。") }
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class JevClient {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    init(transport: Transport? = nil) {
        if let transport = transport { self.transport = transport; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6; configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        self.transport = { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RouterError("JEV 返回了无法识别的网络响应。") }
            return (data, http)
        }
    }
    static func errorMessage(status: Int) -> String {
        switch status {
        case 401: return "JEV 密钥无效或已失效，请在设置中更新。"
        case 403: return "当前 JEV 账户无访问权限，请检查账户。"
        case 404: return "当前 JEV 型号或接口不可用，请检查规则版本。"
        case 413, 422: return "JEV 未接受请求，可能是规则、输入长度或型号不匹配；可先使用本地选类。"
        case 429: return "JEV 请求较多或账户额度受限，请稍后重试。"
        case 529, 503: return "JEV 暂时繁忙，请稍后重试。"
        case 300..<400: return "JEV 返回了重定向，已停止发送鉴权信息。"
        default: return "JEV 暂时不可用（\(status)），可先使用本地选类。"
        }
    }
    private func call(path: String, key: String, body: [String: Any]?) async throws -> Data {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4096, !trimmed.contains("\n"), !trimmed.contains("\r") else { throw RouterError("请先在设置中保存 JEV API Key。") }
        guard path == "/v1/systemone" || path == "/v1/models" else { throw RouterError("不支持的接口。") }
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai" + path)!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer " + trimmed, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let deadline = Date().addingTimeInterval(8)
        for attempt in 0...2 {
            try Task.checkCancellation()
            request.timeoutInterval = max(0.1, deadline.timeIntervalSinceNow)
            let data: Data, response: HTTPURLResponse
            do { (data, response) = try await transport(request) }
            catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            catch { throw RouterError("无法连接 JEV，请检查网络后重试；输入内容已保留。") }
            try Task.checkCancellation()
            guard data.count <= 1_048_576 else { throw RouterError("JEV 响应过大，已停止处理。") }
            if (200..<300).contains(response.statusCode) { return data }
            if [429, 529, 503].contains(response.statusCode), attempt < 2 {
                var wait = pow(2, Double(attempt)) * 0.5
                if let header = response.value(forHTTPHeaderField: "Retry-After") {
                    if let seconds = Double(header), seconds.isFinite { wait = max(0.2, seconds) }
                    else {
                        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                        if let date = formatter.date(from: header) { wait = max(0.2, date.timeIntervalSinceNow) }
                    }
                }
                guard wait < deadline.timeIntervalSinceNow - 0.4 else { throw RouterError(Self.errorMessage(status: response.statusCode)) }
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)); continue
            }
            // Do not display remote bodies: they could echo user text or credentials.
            throw RouterError(Self.errorMessage(status: response.statusCode))
        }
        throw RouterError("JEV 暂时无法连接。")
    }
    func testConnection(key: String) async throws -> String {
        let data = try await call(path: "/v1/models", key: key, body: nil)
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw RouterError("已连接，但模型列表响应格式不正确。") }
        return "连接成功。已通过认证；尚未运行真实任务分类。"
    }
    func classify(task: String, book: RuleBook, key: String) async throws -> Classification {
        let data = try await call(path: "/v1/systemone", key: key, body: book.request(for: task))
        return try ResponseValidator.parse(data, book: book)
    }
}

struct AuditEvent: Encodable {
    let date: String
    let action: String
    let ruleVersion: String
    let client: String?
    let model: String?
    let effort: String?
    let outcome: String
}
final class AuditLog {
    let url: URL
    init(directory: URL) { url = directory.appendingPathComponent("events.jsonl") }
    func record(action: String, version: String, recommendation: Recommendation? = nil, outcome: String) {
        let event = AuditEvent(date: ISO8601DateFormatter().string(from: Date()), action: action, ruleVersion: version,
                               client: recommendation?.model.client.rawValue, model: recommendation?.model.key,
                               effort: recommendation?.effort.rawValue, outcome: outcome)
        guard var line = try? JSONEncoder().encode(event) else { return }; line.append(10)
        let previous = (try? Data(contentsOf: url)) ?? Data()
        let data = previous.count > 512_000 ? line : previous + line
        try? data.write(to: url, options: .atomic)
    }
}
