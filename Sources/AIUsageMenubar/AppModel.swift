import Foundation
import Combine
import AppKit
import UsageCore

private struct PendingResetAttempt: Codable {
    let creditID: String
    let title: String
    let idempotencyKey: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var codexReport: CodexUsageReport?
    @Published var codexError: String?
    @Published var codexLoading = false
    @Published var selectedResetCredit: CodexResetCredit?
    @Published var showResetConfirmation = false
    @Published var resetMessage: String?
    @Published var resetError: String?
    @Published var copilotReport: CopilotUsageReport?
    @Published var copilotError: String?
    @Published var copilotLoading = false
    @Published var githubClientID = UserDefaults.standard.string(forKey: "githubClientID") ?? ""
    @Published var githubUser: String?
    @Published var githubConnected = false
    @Published var authorization: DeviceAuthorization?
    @Published var authorizationMessage: String?
    @Published var githubBusy = false

    private let codex = CodexAppServerClient()
    private let deviceFlow = GitHubDeviceFlow()
    private let github = GitHubBillingClient()
    private let tokenStore = GitHubTokenStore()
    private var token: String?
    private var pendingReset: PendingResetAttempt? {
        didSet {
            if let pendingReset, let data = try? JSONEncoder().encode(pendingReset) {
                UserDefaults.standard.set(data, forKey: "codex.pendingReset")
            } else {
                UserDefaults.standard.removeObject(forKey: "codex.pendingReset")
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "codex.pendingReset") {
            pendingReset = try? JSONDecoder().decode(PendingResetAttempt.self, from: data)
        }
        do {
            token = try tokenStore.read()
            githubConnected = token != nil
        } catch {
            copilotError = error.localizedDescription
        }
        Task { await refreshCodex() }
        if token != nil { Task { await refreshCopilot() } }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await refreshCodex()
                await refreshCopilot()
            }
        }
    }

    var pendingResetTitle: String? { pendingReset?.title }

    func requestReset(_ credit: CodexResetCredit) {
        guard pendingReset == nil else { return }
        selectedResetCredit = credit
        resetError = nil
        showResetConfirmation = true
    }

    func confirmReset() async {
        guard !codexLoading else { return }
        let attempt: PendingResetAttempt
        if let pendingReset {
            attempt = pendingReset
        } else if let credit = selectedResetCredit {
            attempt = PendingResetAttempt(creditID: credit.id, title: credit.title ?? "Codex reset", idempotencyKey: UUID().uuidString.lowercased())
            pendingReset = attempt
        } else { return }
        codexLoading = true
        resetError = nil
        defer { codexLoading = false }
        do {
            let outcome = try await codex.consumeReset(creditID: attempt.creditID, idempotencyKey: attempt.idempotencyKey, confirmed: true)
            pendingReset = nil
            selectedResetCredit = nil
            resetMessage = outcome
            codexReport = try await codex.readUsage()
        } catch {
            resetError = "Outcome uncertain; retry only with the same idempotency key. \(error.localizedDescription)"
        }
    }

    func saveClientID() {
        githubClientID = githubClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(githubClientID, forKey: "githubClientID")
    }

    func refreshCodex() async {
        guard !codexLoading else { return }
        codexLoading = true
        codexError = nil
        defer { codexLoading = false }
        do { codexReport = try await codex.readUsage() }
        catch { codexError = error.localizedDescription }
    }

    func refreshCopilot() async {
        guard !copilotLoading else { return }
        guard let token else {
            copilotReport = nil
            copilotError = nil
            return
        }
        copilotLoading = true
        copilotError = nil
        defer { copilotLoading = false }
        do {
            let user = try await github.currentUser(token: token)
            githubUser = user
            copilotReport = try await github.copilotUsage(token: token, username: user)
        } catch {
            copilotError = error.localizedDescription
            if let providerError = error as? ProviderError, case .unauthorized = providerError {
                try? tokenStore.delete()
                self.token = nil
                githubConnected = false
            }
        }
    }

    func connectGitHub() async {
        guard !githubBusy else { return }
        saveClientID()
        githubBusy = true
        authorization = nil
        authorizationMessage = nil
        copilotError = nil
        defer { githubBusy = false }
        do {
            let flow = try await deviceFlow.begin(clientID: githubClientID)
            authorization = flow
            let token = try await deviceFlow.poll(clientID: githubClientID, authorization: flow)
            try tokenStore.save(token.accessToken)
            self.token = token.accessToken
            githubConnected = true
            authorization = nil
            authorizationMessage = "GitHub connected. Token stored in macOS Keychain."
            await refreshCopilot()
        } catch {
            authorization = nil
            copilotError = error.localizedDescription
        }
    }

    func openVerificationPage() {
        guard let url = authorization?.verificationURL else { return }
        NSWorkspace.shared.open(url)
    }

    func disconnectGitHub() {
        do {
            try tokenStore.delete()
            token = nil
            githubUser = nil
            copilotReport = nil
            copilotError = nil
            githubConnected = false
            authorizationMessage = "GitHub disconnected on this Mac. Revoke the app authorization separately in GitHub settings."
        } catch { copilotError = error.localizedDescription }
    }
}
