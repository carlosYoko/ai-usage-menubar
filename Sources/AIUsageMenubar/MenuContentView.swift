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
            HStack {
                Button("Refresh all") {
                    Task { await model.refreshCodex(); await model.refreshCopilot() }
                }
                .keyboardShortcut("r")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 360)
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
            if model.codexLoading || model.copilotLoading || model.githubBusy {
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
                    Button("Disconnect") { model.disconnectGitHub() }.buttonStyle(.link)
                }
            }
            if let report = model.copilotReport {
                Text("Reported usage · \(monthName(report.period.month)) \(report.period.year)")
                    .font(.caption).foregroundStyle(.secondary)
                if report.items.isEmpty {
                    Text("No Copilot usage items reported for this period.").font(.caption)
                } else {
                    ForEach(report.totalsByUnit.keys.sorted(), id: \.self) { unit in
                        HStack {
                            Text(unit)
                            Spacer()
                            Text(quantity(report.totalsByUnit[unit] ?? 0)).monospacedDigit()
                        }.font(.caption)
                    }
                }
                Text("Consumption only; GitHub's report doesn't include remaining allowance.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Updated \(report.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else if let error = model.copilotError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if model.githubConnected {
                Text(model.copilotLoading ? "Reading Copilot usage…" : "No report loaded")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Connect GitHub to read personal billing usage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.githubConnected {
                TextField("GitHub App Client ID", text: $model.githubClientID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.saveClientID() }
                HStack {
                    Button(model.githubBusy ? "Waiting for GitHub…" : "Connect with GitHub") {
                        Task { await model.connectGitHub() }
                    }
                    .disabled(model.githubBusy || model.githubClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let authorization = model.authorization {
                        Text(authorization.userCode).font(.system(.caption, design: .monospaced).weight(.bold))
                        Button("Open verification") { model.openVerificationPage() }
                    }
                }
                Text("Requires a device-flow-enabled GitHub App with Plan: read permission.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if let message = model.authorizationMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
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

    private func monthName(_ month: Int) -> String {
        Calendar.current.monthSymbols.indices.contains(month - 1) ? Calendar.current.monthSymbols[month - 1] : "Month \(month)"
    }

    private func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
