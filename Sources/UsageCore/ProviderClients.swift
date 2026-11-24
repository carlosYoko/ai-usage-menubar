import Foundation
import Security
import Darwin

public enum ProviderError: Error, LocalizedError {
    case codexNotFound
    case codexTimedOut
    case codexExited
    case codexProtocol(String)
    case unauthorized
    case forbidden
    case httpStatus(Int)
    case malformedResponse
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .codexNotFound: "Codex CLI not found. Install it or set CODEX_BINARY."
        case .codexTimedOut: "Codex app-server timed out."
        case .codexExited: "Codex app-server exited before returning quota data."
        case .codexProtocol(let message): "Codex app-server error: \(message)"
        case .unauthorized: "GitHub authorization expired. Reconnect the account."
        case .forbidden: "GitHub denied access to the internal Copilot quota endpoint. The endpoint may be unavailable for this account or may have changed."
        case .httpStatus(let code): "GitHub API returned HTTP \(code)."
        case .malformedResponse: "The provider returned an unsupported response."
        case .keychain(let status): "Keychain error (\(status))."
        }
    }
}

public struct GitHubCLIAccount: Sendable, Identifiable {
    public let login: String
    public let accessToken: String
    public var id: String { login }
}

public final class GitHubCLIAuthClient: @unchecked Sendable {
    private let executableURL: URL?

    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.findGitHubCLI()
    }

    public func accounts() async -> [GitHubCLIAccount] {
        guard let executableURL else { return [] }
        return await Task.detached(priority: .utility) {
            guard let status = Self.run(executableURL, arguments: ["auth", "status", "--hostname", "github.com", "--json", "hosts"]),
                  let json = try? JSONSerialization.jsonObject(with: status) as? [String: Any],
                  let hosts = json["hosts"] as? [String: Any],
                  let users = hosts["github.com"] as? [[String: Any]] else { return [] }
            let validUsers = users.compactMap { user -> (String, Bool)? in
                guard user["state"] as? String == "success", let login = user["login"] as? String else { return nil }
                return (login, user["active"] as? Bool ?? false)
            }.sorted { $0.1 && !$1.1 || $0.1 == $1.1 && $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
            return validUsers.compactMap { login, _ in
                guard let data = Self.run(executableURL, arguments: ["auth", "token", "--hostname", "github.com", "--user", login]),
                      let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !token.isEmpty else { return nil }
                return GitHubCLIAccount(login: login, accessToken: token)
            }
        }.value
    }

    private static func run(_ executableURL: URL, arguments: [String]) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func findGitHubCLI() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "\(home)/.local/bin/gh"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/gh" }
        }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

public final class GitHubCopilotClient: @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func copilotQuota(token: String, date: Date = .now) async throws -> CopilotQuotaReport {
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.malformedResponse }
        if http.statusCode == 401 { throw ProviderError.unauthorized }
        if http.statusCode == 403 { throw ProviderError.forbidden }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError.httpStatus(http.statusCode) }
        return try CopilotQuotaReport.parseInternalResponse(data, now: date)
    }

}

public final class GitHubTokenStore: @unchecked Sendable {
    private let service = "com.carlosYoko.ai-usage-menubar.github"
    private let account = "user-access-token"
    public init() {}

    public func read() throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw ProviderError.keychain(status)
        }
        return token
    }

    public func save(_ token: String) throws {
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: account]
        let data = Data(token.utf8)
        let update = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = key
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw ProviderError.keychain(status) }
        } else if update != errSecSuccess { throw ProviderError.keychain(update) }
    }

    public func delete() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProviderError.keychain(status) }
    }
}

public final class CodexAppServerClient: @unchecked Sendable {
    private let executableURL: URL?
    private let timeoutSeconds: TimeInterval
    public init(executableURL: URL? = nil, timeoutSeconds: TimeInterval = 20) {
        self.executableURL = executableURL ?? Self.findCodex()
        self.timeoutSeconds = timeoutSeconds
    }

    public func readUsage() async throws -> CodexUsageReport {
        try await Task.detached(priority: .utility) {
            let result = try self.callSynchronously(method: "account/rateLimits/read", params: ["excludeResetCreditDetails": false])
            let data = try JSONSerialization.data(withJSONObject: result)
            return try CodexUsageReport.parseAppServerResult(data)
        }.value
    }

    public func consumeReset(creditID: String, idempotencyKey: String, confirmed: Bool) async throws -> String {
        guard confirmed, !creditID.isEmpty, idempotencyKey.range(of: "^[A-Za-z0-9-]{16,120}$", options: .regularExpression) != nil else {
            throw ProviderError.codexProtocol("Reset consumption requires explicit confirmation and an idempotency key.")
        }
        return try await Task.detached(priority: .userInitiated) {
            let result = try self.callSynchronously(method: "account/rateLimitResetCredit/consume", params: ["creditId": creditID, "idempotencyKey": idempotencyKey])
            guard let outcome = result["outcome"] as? String,
                  ["reset", "nothingToReset", "noCredit", "alreadyRedeemed"].contains(outcome) else {
                throw ProviderError.codexProtocol("Unknown reset consumption outcome.")
            }
            return outcome
        }.value
    }

    private func callSynchronously(method: String, params: [String: Any]) throws -> [String: Any] {
        signal(SIGPIPE, SIG_IGN)
        guard ["account/rateLimits/read", "account/rateLimitResetCredit/consume"].contains(method) else {
            throw ProviderError.codexProtocol("Protocol method is not allowlisted.")
        }
        guard let executableURL else { throw ProviderError.codexNotFound }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw ProviderError.codexNotFound }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        var reader = JSONLineReader(handle: output.fileHandleForReading)
        do {
            try writeToPipe(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "ai_usage_menubar", "title": "AI Usage Menubar", "version": "0.1.0"], "capabilities": NSNull()]], to: input)
        } catch { throw ProviderError.codexProtocol("app-server closed stdin during initialize") }
        let initialized = try reader.response(id: 1)
        if let error = initialized["error"] { throw ProviderError.codexProtocol(String(describing: error)) }
        do { try writeToPipe(["method": "initialized"], to: input) }
        catch { throw ProviderError.codexProtocol("app-server closed stdin on initialized notification (running: \(process.isRunning), status: \(process.terminationStatus))") }
        do { try writeToPipe(["id": 2, "method": method, "params": params], to: input) }
        catch { throw ProviderError.codexProtocol("app-server closed stdin on usage request") }
        let response = try reader.response(id: 2)
        if let error = response["error"] { throw ProviderError.codexProtocol(String(describing: error)) }
        guard let result = response["result"] as? [String: Any] else { throw ProviderError.malformedResponse }
        return result
    }

    private func writeToPipe(_ object: [String: Any], to pipe: Pipe) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw ProviderError.malformedResponse }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(pipe.fileHandleForWriting.fileDescriptor, base.advanced(by: offset), bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw ProviderError.codexExited
                }
                offset += written
            }
        }
    }

    private static func findCodex() -> URL? {
        if let configured = ProcessInfo.processInfo.environment["CODEX_BINARY"], FileManager.default.isExecutableFile(atPath: configured) {
            return URL(fileURLWithPath: configured)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }
        #if arch(arm64)
        let vscodeArch = "aarch64"
        #else
        let vscodeArch = "x86_64"
        #endif
        for root in ["\(home)/.vscode/extensions", "\(home)/.vscode-insiders/extensions"] {
            if let extensions = try? FileManager.default.contentsOfDirectory(atPath: root) {
                candidates += extensions.filter { $0.hasPrefix("openai.chatgpt-") }.sorted().reversed().map {
                    "\(root)/\($0)/bin/macos-\(vscodeArch)/codex"
                }
            }
        }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

public final class HelmcodeClient: @unchecked Sendable {
    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.helmcode.com/v1/usage")! // <--- CAMBIAR POR EL REAL

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func fetchUsage() async throws -> HelmcodeUsageReport {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderError.malformedResponse
        }
        
        return try HelmcodeUsageReport.parse(data)
    }
}

private struct JSONLineReader {
    let handle: FileHandle
    var buffer = Data()

    mutating func response(id: Int) throws -> [String: Any] {
        while let line = try nextLine() {
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if (object["id"] as? NSNumber)?.intValue == id { return object }
        }
        throw ProviderError.codexExited
    }

    private mutating func nextLine() throws -> Data? {
        while true {
            if let newline = buffer.firstRange(of: Data([10])) {
                let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<newline.upperBound)
                if !line.isEmpty { return line }
                continue
            }
            let chunk = try handle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
