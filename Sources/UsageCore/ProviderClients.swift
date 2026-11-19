import Foundation
import Security
import Darwin

public enum ProviderError: Error, LocalizedError {
    case codexNotFound
    case codexTimedOut
    case codexExited
    case codexProtocol(String)
    case missingGitHubClientID
    case unauthorized
    case forbidden
    case httpStatus(Int)
    case malformedResponse
    case deviceAuthorization(String)
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .codexNotFound: "Codex CLI not found. Install it or set CODEX_BINARY."
        case .codexTimedOut: "Codex app-server timed out."
        case .codexExited: "Codex app-server exited before returning quota data."
        case .codexProtocol(let message): "Codex app-server error: \(message)"
        case .missingGitHubClientID: "Enter the Client ID of your GitHub App."
        case .unauthorized: "GitHub authorization expired. Reconnect the account."
        case .forbidden: "GitHub denied billing usage access. Check the App's Plan: read permission and account billing eligibility."
        case .httpStatus(let code): "GitHub API returned HTTP \(code)."
        case .malformedResponse: "The provider returned an unsupported response."
        case .deviceAuthorization(let message): "GitHub authorization: \(message)"
        case .keychain(let status): "Keychain error (\(status))."
        }
    }
}

public struct DeviceAuthorization: Sendable {
    fileprivate let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresIn: TimeInterval
    public let interval: TimeInterval
}

public struct GitHubDeviceToken: Sendable {
    public let accessToken: String
    public let expiresIn: TimeInterval?
}

public final class GitHubDeviceFlow: @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func begin(clientID: String) async throws -> DeviceAuthorization {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProviderError.missingGitHubClientID }
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientID])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verification = json["verification_uri"] as? String,
              let verificationURL = URL(string: verification), verificationURL.host == "github.com",
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue else {
            throw ProviderError.malformedResponse
        }
        return DeviceAuthorization(deviceCode: deviceCode, userCode: userCode, verificationURL: verificationURL,
                                   expiresIn: expiresIn, interval: (json["interval"] as? NSNumber)?.doubleValue ?? 5)
    }

    public func poll(clientID: String, authorization: DeviceAuthorization) async throws -> GitHubDeviceToken {
        let deadline = Date.now.addingTimeInterval(authorization.expiresIn)
        var interval = max(authorization.interval, 1)
        while Date.now < deadline {
            try await Task.sleep(for: .seconds(interval))
            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody([
                "client_id": clientID,
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProviderError.malformedResponse
            }
            if let token = json["access_token"] as? String {
                return GitHubDeviceToken(accessToken: token, expiresIn: (json["expires_in"] as? NSNumber)?.doubleValue)
            }
            switch json["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw ProviderError.deviceAuthorization("Access was denied.")
            case "expired_token": throw ProviderError.deviceAuthorization("The device code expired. Start again.")
            case let other?: throw ProviderError.deviceAuthorization(other)
            case nil: throw ProviderError.malformedResponse
            }
        }
        throw ProviderError.deviceAuthorization("The device code expired. Start again.")
    }

    private func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

public final class GitHubBillingClient: @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func currentUser(token: String) async throws -> String {
        let json = try await getJSON(path: "/user", token: token)
        guard let login = json["login"] as? String else { throw ProviderError.malformedResponse }
        return login
    }

    public func copilotUsage(token: String, username: String, date: Date = .now) async throws -> CopilotUsageReport {
        var components = URLComponents(string: "https://api.github.com/users/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)/settings/billing/ai_credit/usage")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        components.queryItems = [
            URLQueryItem(name: "year", value: String(calendar.component(.year, from: date))),
            URLQueryItem(name: "month", value: String(calendar.component(.month, from: date)))
        ]
        guard let url = components.url else { throw ProviderError.malformedResponse }
        let data = try await getData(url: url, token: token)
        return try CopilotUsageReport.parse(data, now: date)
    }

    private func getJSON(path: String, token: String) async throws -> [String: Any] {
        let data = try await getData(url: URL(string: "https://api.github.com\(path)")!, token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError.malformedResponse }
        return json
    }

    private func getData(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.malformedResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw ProviderError.unauthorized
        case 403: throw ProviderError.forbidden
        default: throw ProviderError.httpStatus(http.statusCode)
        }
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
    public init(executableURL: URL? = nil) { self.executableURL = executableURL ?? Self.findCodex() }

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
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        var reader = JSONLineReader(handle: output.fileHandleForReading)
        do {
            try write(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "ai_usage_menubar", "title": "AI Usage Menubar", "version": "0.1.0"], "capabilities": NSNull()]], to: input)
        } catch { throw ProviderError.codexProtocol("app-server closed stdin during initialize") }
        let initialized = try reader.response(id: 1)
        if let error = initialized["error"] { throw ProviderError.codexProtocol(String(describing: error)) }
        do { try write(["method": "initialized"], to: input) }
        catch { throw ProviderError.codexProtocol("app-server closed stdin on initialized notification (running: \(process.isRunning), status: \(process.terminationStatus))") }
        do { try write(["id": 2, "method": method, "params": params], to: input) }
        catch { throw ProviderError.codexProtocol("app-server closed stdin on usage request") }
        let response = try reader.response(id: 2)
        if let error = response["error"] { throw ProviderError.codexProtocol(String(describing: error)) }
        guard let result = response["result"] as? [String: Any] else { throw ProviderError.malformedResponse }
        return result
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

    private func write(_ object: [String: Any], to pipe: Pipe) throws {
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
