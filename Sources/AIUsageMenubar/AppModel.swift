import Foundation
import Combine
import AppKit
import UsageCore

struct CopilotAccountStatus: Sendable, Identifiable {
    let login: String
    let report: CopilotQuotaReport?
    let error: String?
    var id: String { login }
}

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
    @Published var copilotAccounts: [CopilotAccountStatus] = []
    @Published var copilotError: String?
    @Published var copilotLoading = false
    @Published var githubConnected = false
    @Published var githubUsesCLI = false
    @Published var githubMessage: String?

    private let codex = CodexAppServerClient()
    private let githubCLI = GitHubCLIAuthClient()
    private let github = GitHubCopilotClient()
    private let tokenStore = GitHubTokenStore()
    private var token: String?
    private var githubHidden = UserDefaults.standard.bool(forKey: "github.hiddenInApp")
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
        Task { await refreshCopilot() }
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
    var isGitHubHidden: Bool { githubHidden }

    var codexMenuBarText: String? {
        guard let report = codexReport, !report.windows.isEmpty,
              let window = report.windows.first(where: { $0.durationMinutes == 300 }) ?? report.windows.first else { return nil }
        let percent = Int(window.remainingPercent.rounded())
        guard let reset = window.resetsAt else { return "\(percent)%" }
        let minutes = max(0, Int(ceil(reset.timeIntervalSinceNow / 60)))
        let hours = minutes / 60
        let remainder = minutes % 60
        let time = remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        return "\(percent)% \(time)"
    }

    var copilotMenuBarText: String? {
        let accounts = copilotAccounts.compactMap { account -> String? in
            guard let metric = account.report?.metrics.first else { return nil }
            let percent = "M \(Int(metric.remainingPercent.rounded()))%"
            return copilotAccounts.count == 1 ? percent : "\(account.login) \(percent)"
        }
        return accounts.isEmpty ? nil : accounts.joined(separator: " ")
    }

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
        guard !githubHidden else {
            copilotAccounts = []
            githubConnected = false
            return
        }
        copilotLoading = true
        copilotError = nil
        defer { copilotLoading = false }

        let cliAccounts = await githubCLI.accounts()
        if !cliAccounts.isEmpty {
            githubUsesCLI = true
            var reports: [CopilotAccountStatus] = []
            for account in cliAccounts {
                do {
                    let report = try await github.copilotQuota(token: account.accessToken)
                    reports.append(CopilotAccountStatus(login: account.login, report: report, error: nil))
                } catch {
                    reports.append(CopilotAccountStatus(login: account.login, report: nil, error: error.localizedDescription))
                }
            }
            copilotAccounts = reports
            githubConnected = true
            return
        }

        githubUsesCLI = false
        guard let token else {
            copilotAccounts = []
            githubConnected = false
            return
        }
        do {
            let report = try await github.copilotQuota(token: token)
            copilotAccounts = [CopilotAccountStatus(login: "GitHub account", report: report, error: nil)]
            githubConnected = true
        } catch {
            copilotAccounts = [CopilotAccountStatus(login: "GitHub account", report: nil, error: error.localizedDescription)]
            copilotError = error.localizedDescription
            if let providerError = error as? ProviderError, case .unauthorized = providerError {
                try? tokenStore.delete()
                self.token = nil
                githubConnected = false
            }
        }
    }

    func connectGitHub() {
        if githubHidden {
            githubHidden = false
            UserDefaults.standard.set(false, forKey: "github.hiddenInApp")
            githubMessage = nil
            Task { await refreshCopilot() }
            return
        }
        githubMessage = nil
        let source = #"tell application "Terminal" to do script "gh auth login --hostname github.com --git-protocol https --web""#
        var errorInfo: NSDictionary?
        if NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) == nil {
            githubMessage = "Could not open Terminal for GitHub sign-in. Run `gh auth login --hostname github.com --web` there."
        } else {
            githubMessage = "Finish GitHub sign-in in Terminal, then choose Refresh all. No API key is needed."
        }
    }

    func disconnectGitHub() {
        copilotAccounts = []
        githubConnected = false
        copilotError = nil
        if githubUsesCLI {
            githubHidden = true
            UserDefaults.standard.set(true, forKey: "github.hiddenInApp")
            githubMessage = "Hidden in this app; your GitHub CLI login remains available to other tools."
        } else {
            do {
                try tokenStore.delete()
                token = nil
                githubMessage = "GitHub token removed from this app."
            } catch { copilotError = error.localizedDescription }
        }
    }
}
