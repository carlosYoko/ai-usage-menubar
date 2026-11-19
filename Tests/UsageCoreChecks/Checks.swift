import Foundation
import UsageCore

@main
struct UsageCoreChecks {
    static func main() async throws {
        let codexPayload = #"""
        {
          "rateLimitsByLimitId": {"codex": {
            "primary": {"usedPercent": 26, "windowDurationMins": 300, "resetsAt": 1800000000},
            "secondary": {"usedPercent": 41, "windowDurationMins": 10080, "resetsAt": 1800100000}
          }},
          "rateLimitResetCredits": {"availableCount": 2, "credits": [
            {"id":"mock-credit", "resetType":"codexRateLimits", "status":"available", "expiresAt":1800200000, "title":"Test reset", "description":"Mock only"}
          ]}
        }
        """#
        let codex = try CodexUsageReport.parseAppServerResult(Data(codexPayload.utf8))
        check(codex.windows.map(\.usedPercent) == [26, 41], "Codex usage windows decode")
        check(codex.windows.map(\.durationMinutes) == [300, 10080], "Codex window lengths decode dynamically")
        check(codex.availableResetCredits == 2, "Codex available reset credits decode")
        check(codex.resetCredits.first?.id == "mock-credit", "Codex reset details decode")
        check(codex.resetCredits.first?.type == "codexRateLimits", "Reset type is preserved for allowlisting")

        let copilotPayload = #"""
        {
          "timePeriod": {"year": 2026, "month": 11},
          "user": "sample-user",
          "usageItems": [
            {"product":"Copilot AI Credits", "sku":"AI Credit", "model":"Model A", "unitType":"ai-credits", "grossQuantity":12, "netQuantity":10, "netAmount":0.10},
            {"product":"Copilot AI Credits", "sku":"AI Credit", "model":"Model B", "unitType":"ai-credits", "grossQuantity":3, "netQuantity":3, "netAmount":0.03},
            {"product":"Copilot", "sku":"Premium Request", "model":"Model C", "unitType":"requests", "grossQuantity":2, "netQuantity":2, "netAmount":0.08}
          ]
        }
        """#
        let copilot = try CopilotUsageReport.parse(Data(copilotPayload.utf8))
        check(copilot.period.year == 2026 && copilot.period.month == 11, "Copilot report period decodes")
        check(copilot.totalsByUnit["ai-credits"] == 13, "AI credits aggregate independently")
        check(copilot.totalsByUnit["requests"] == 2, "legacy premium requests remain separate")
        check(copilot.remainingAllowance == nil, "Documented billing report has no remaining allowance")

        let quotaPayload = #"""
        {
          "copilot_plan":"individual",
          "quota_reset_date":"2026-12-01T00:00:00Z",
          "quota_snapshots": {
            "premium_interactions":{"entitlement":300,"remaining":216,"percent_remaining":72},
            "chat":{"unlimited":true,"entitlement":-1,"remaining":-1}
          }
        }
        """#
        let quota = try CopilotQuotaReport.parseInternalResponse(Data(quotaPayload.utf8))
        check(quota.metrics.count == 1, "Unlimited Copilot quotas are suppressed")
        check(quota.metrics.first?.id == "premium_interactions", "Premium quota decodes")
        check(quota.metrics.first?.remainingPercent == 72, "Copilot remaining percentage decodes")
        check(quota.metrics.first?.resetsAt != nil, "Copilot reset date decodes")
        do {
            _ = try await CodexAppServerClient().consumeReset(creditID: "mock-credit", idempotencyKey: UUID().uuidString, confirmed: false)
            fatalError("FAIL: Codex reset consumption must reject missing confirmation")
        } catch let error as ProviderError {
            guard case .codexProtocol = error else { throw error }
        }
        print("Passed: Codex quota/reset decoding; unconfirmed reset blocked; Copilot billing aggregation and quota percentage decoding.")

        if CommandLine.arguments.contains("--live-codex") {
            let report = try await CodexAppServerClient().readUsage()
            print("Codex read-only integration passed: \(report.windows.count) windows; reset-credit count \(report.availableResetCredits.map(String.init) ?? "unavailable"). No credits consumed.")
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }
}
