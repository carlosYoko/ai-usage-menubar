import SwiftUI
import AppKit
import UsageCore

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            codexSection
            Divider()
            copilotSection
            Divider()
            helmcodeSection
            Divider()
            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            if let message = model.launchAtLoginMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh all") {
                    Task { await model.refreshCodex(); await model.refreshCopilot(); await model.refreshHelmcode() }
                }
                .keyboardShortcut("r")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 380)
        .confirmationDialog("Use one Codex reset credit?", isPresented: $model.showResetConfirmation, titleVisibility: .visible) {
            Button("Confirm and use 1 reset", role: .destructive) {
                Task { await model.confirmReset() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This consumes one real reset credit from your Codex account. It cannot be undone.")
        }
    }

    private var header: some View {
        HStack {
            Label("AI Usage", systemImage: "chart.bar.xaxis").font(.headline)
            Spacer()
            if model.codexLoading || model.copilotLoading || model.helmcodeLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Codex").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh") { Task { await model.refreshCodex() } }.buttonStyle(.link)
            }
            if let report = model.codexReport {
                ForEach(Array(report.windows.enumerated()), id: \.offset) { entry in
                    let window = entry.element
                    HStack {
                        Text("\(windowLabel(window.durationMinutes)): \(Int(window.remainingPercent.rounded()))% remaining")
                        Spacer()
                        if let reset = window.resetsAt { Text(countdown(to: reset)).foregroundStyle(.secondary) }
                    }.font(.caption)
                }
                if let count = report.availableResetCredits {
                    Text("Reset credits available: \(count)").font(.caption2).foregroundStyle(.secondary)
                }
                if let pendingTitle = model.pendingResetTitle {
                    Text("Pending reset: \(pendingTitle). Outcome may be uncertain.")
                        .font(.caption2).foregroundStyle(.orange)
                    Button("Confirm retry with same idempotency key") { model.showResetConfirmation = true }
                        .font(.caption).disabled(model.codexLoading)
                } else {
                    ForEach(report.resetCredits.filter(isRedeemable)) { credit in
                        HStack {
                            Text(credit.title ?? "Codex reset credit").lineLimit(1)
                            Spacer()
                            Button("Use…") { model.requestReset(credit) }
                                .buttonStyle(.link).disabled(model.codexLoading)
                        }.font(.caption)
                    }
                }
                if let message = model.resetMessage {
                    Text("Reset result: \(message)").font(.caption2).foregroundStyle(.secondary)
                }
                if let error = model.resetError { Text(error).font(.caption2).foregroundStyle(.red) }
                Text("Updated \(report.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else if let error = model.codexError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text(model.codexLoading ? "Reading Codex usage…" : "No usage data yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var copilotSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("GitHub Copilot").font(.subheadline.weight(.semibold))
                Spacer()
                if model.githubConnected {
                    Text(model.githubUsesCLI ? "via GitHub CLI" : "linked")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button(model.githubUsesCLI ? "Hide" : "Disconnect") { model.disconnectGitHub() }
                        .buttonStyle(.link)
                }
            }
            ForEach(model.copilotAccounts) { account in
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.login).font(.caption.weight(.medium))
                    if let report = account.report {
                        ForEach(report.metrics) { metric in
                            HStack {
                                Text(metric.label)
                                Spacer()
                                Text("\(Int(metric.remainingPercent.rounded()))% remaining").monospacedDigit()
                                if let reset = metric.resetsAt { Text(countdown(to: reset)).foregroundStyle(.secondary) }
                            }.font(.caption)
                        }
                        Text("Updated \(report.fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else if let error = account.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            if model.copilotAccounts.isEmpty && model.githubConnected && model.copilotLoading {
                Text("Reading Copilot quotas…").font(.caption).foregroundStyle(.secondary)
            } else if !model.githubConnected {
                Text("No GitHub CLI session found. Sign in without an API key.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(model.isGitHubHidden ? "Show GitHub accounts" : "Sign in with GitHub CLI") {
                    model.connectGitHub()
                }
            }
            if model.githubConnected && model.copilotAccounts.isEmpty && !model.copilotLoading {
                Text(model.copilotError ?? "No GitHub accounts available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Quota uses GitHub's undocumented Copilot endpoint and may change without notice.")
                .font(.caption2).foregroundStyle(.secondary)
            if let message = model.githubMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
            if let error = model.copilotError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private var helmcodeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Helmcode").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh") { Task { await model.refreshHelmcode() } }.buttonStyle(.link)
            }
            if let report = model.helmcodeReport {
                ForEach(report.models) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        if case .unlimited = item.usage {
                            Text("Flat rate").font(.caption).foregroundStyle(.secondary)
                        } else if case .quota(let percent, let reset) = item.usage {
                            HStack {
                                Text("\(Int(percent.rounded()))% remaining").monospacedDigit()
                                if let reset = reset { Text(countdown(to: reset)).foregroundStyle(.secondary) }
                            }.font(.caption)
                        }
                    }.font(.caption)
                }
                Text("Updated \(report.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else if let error = model.helmcodeError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text(model.helmcodeLoading ? "Reading Helmcode usage…" : "No usage data yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func isRedeemable(_ credit: CodexResetCredit) -> Bool {
        credit.type == "codexRateLimits" && credit.status == "available" && (credit.expiresAt == nil || credit.expiresAt! > .now)
    }

    private func windowLabel(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440)d window" }
        if minutes % 60 == 0 { return "\(minutes / 60)h window" }
        return "\(minutes)m window"
    }

    private func countdown(to date: Date) -> String {
        let total = max(0, Int(ceil(date.timeIntervalSinceNow / 60)))
        let days = total / 1440, hours = total % 1440 / 60, minutes = total % 60
        return days > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(hours)h \(minutes)m"
    }

    private func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
