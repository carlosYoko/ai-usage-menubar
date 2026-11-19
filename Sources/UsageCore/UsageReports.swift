import Foundation

public struct QuotaWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let durationMinutes: Int
    public let resetsAt: Date?

    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public init(usedPercent: Double, durationMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexResetCredit: Equatable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let status: String
    public let expiresAt: Date?
    public let title: String?
    public let description: String?

    public init(id: String, type: String, status: String, expiresAt: Date?, title: String?, description: String?) {
        self.id = id
        self.type = type
        self.status = status
        self.expiresAt = expiresAt
        self.title = title
        self.description = description
    }
}

public struct CodexUsageReport: Equatable, Sendable {
    public let windows: [QuotaWindow]
    public let availableResetCredits: Int?
    public let resetCredits: [CodexResetCredit]
    public let fetchedAt: Date

    public init(windows: [QuotaWindow], availableResetCredits: Int?, resetCredits: [CodexResetCredit] = [], fetchedAt: Date = .now) {
        self.windows = windows.sorted { $0.durationMinutes < $1.durationMinutes }
        self.availableResetCredits = availableResetCredits
        self.resetCredits = resetCredits
        self.fetchedAt = fetchedAt
    }

    public static func parseAppServerResult(_ data: Data, now: Date = .now) throws -> CodexUsageReport {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let object = root as? [String: Any] else { throw UsageParseError.invalidCodexResponse }
        let codex = (object["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
            ?? object["rateLimits"] as? [String: Any]
        guard let codex else { throw UsageParseError.codexLimitsUnavailable }

        let windows = ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard let item = codex[key] as? [String: Any],
                  let used = (item["usedPercent"] as? NSNumber)?.doubleValue,
                  let duration = (item["windowDurationMins"] as? NSNumber)?.intValue else { return nil }
            let reset = (item["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return QuotaWindow(usedPercent: used, durationMinutes: duration, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw UsageParseError.codexLimitsUnavailable }
        let resetResponse = object["rateLimitResetCredits"] as? [String: Any]
        let credits = (resetResponse?["availableCount"] as? NSNumber)?.intValue
        let resetCredits = (resetResponse?["credits"] as? [[String: Any]] ?? []).compactMap { item -> CodexResetCredit? in
            guard let id = item["id"] as? String, let type = item["resetType"] as? String,
                  let status = item["status"] as? String else { return nil }
            let expiry = (item["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return CodexResetCredit(id: id, type: type, status: status, expiresAt: expiry,
                                    title: item["title"] as? String, description: item["description"] as? String)
        }
        return CodexUsageReport(windows: windows, availableResetCredits: credits, resetCredits: resetCredits, fetchedAt: now)
    }
}

public struct CopilotQuotaMetric: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let remainingPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, remainingPercent: Double, resetsAt: Date?) {
        self.id = id
        self.label = label
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetsAt = resetsAt
    }
}

public struct CopilotQuotaReport: Equatable, Sendable {
    public let plan: String?
    public let metrics: [CopilotQuotaMetric]
    public let creditsUsed: Double?
    public let fetchedAt: Date

    public static func parseInternalResponse(_ data: Data, now: Date = .now) throws -> CopilotQuotaReport {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParseError.invalidCopilotResponse
        }
        let reset = parseCopilotDate(body["quota_reset_date"]) ?? parseCopilotDate(body["limited_user_reset_date"])
        let snapshots = body["quota_snapshots"] as? [String: Any]
        let definitions = [("premium_interactions", "Credits"), ("chat", "Chat"), ("completions", "Completions")]
        var metrics = definitions.compactMap { key, label -> CopilotQuotaMetric? in
            guard let snapshot = snapshots?[key] as? [String: Any] else { return nil }
            let entitlement = (snapshot["entitlement"] as? NSNumber)?.doubleValue
            let remaining = (snapshot["remaining"] as? NSNumber)?.doubleValue
            if (snapshot["unlimited"] as? Bool) == true || entitlement == -1 || remaining == -1 || entitlement == 0 { return nil }
            let percent: Double
            if let value = (snapshot["percent_remaining"] as? NSNumber)?.doubleValue {
                percent = value
            } else if let entitlement, entitlement > 0, let remaining {
                percent = remaining / entitlement * 100
            } else { return nil }
            return CopilotQuotaMetric(id: key, label: label, remainingPercent: percent, resetsAt: reset)
        }
        if metrics.isEmpty {
            let limited = body["limited_user_quotas"] as? [String: Any]
            let monthly = body["monthly_quotas"] as? [String: Any]
            metrics = [("chat", "Chat"), ("completions", "Completions")].compactMap { key, label in
                guard let remaining = (limited?[key] as? NSNumber)?.doubleValue,
                      let total = (monthly?[key] as? NSNumber)?.doubleValue, total > 0 else { return nil }
                return CopilotQuotaMetric(id: key, label: label, remainingPercent: remaining / total * 100, resetsAt: reset)
            }
        }
        let premium = snapshots?["premium_interactions"] as? [String: Any]
        let creditsUsed = (body["token_based_billing"] as? Bool) == true
            ? (premium?["credits_used"] as? NSNumber)?.doubleValue : nil
        guard !metrics.isEmpty || creditsUsed != nil else { throw UsageParseError.copilotQuotaUnavailable }
        return CopilotQuotaReport(plan: body["copilot_plan"] as? String, metrics: metrics, creditsUsed: creditsUsed, fetchedAt: now)
    }

    private static func parseCopilotDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: text)
    }
}

public struct CopilotUsagePeriod: Equatable, Sendable {
    public let year: Int
    public let month: Int
}

public struct CopilotUsageItem: Equatable, Sendable {
    public let product: String
    public let sku: String
    public let model: String?
    public let unitType: String
    public let netQuantity: Double
    public let netAmount: Double

    fileprivate init(json: [String: Any]) throws {
        guard let product = json["product"] as? String,
              let sku = json["sku"] as? String,
              let unitType = json["unitType"] as? String,
              let quantity = (json["netQuantity"] as? NSNumber)?.doubleValue else {
            throw UsageParseError.invalidCopilotItem
        }
        self.product = product
        self.sku = sku
        self.model = json["model"] as? String
        self.unitType = unitType
        self.netQuantity = quantity
        self.netAmount = (json["netAmount"] as? NSNumber)?.doubleValue ?? 0
    }
}

public struct CopilotUsageReport: Equatable, Sendable {
    public let period: CopilotUsagePeriod
    public let items: [CopilotUsageItem]
    public let fetchedAt: Date

    public var totalsByUnit: [String: Double] {
        Dictionary(grouping: items, by: \.unitType).mapValues { $0.reduce(0) { $0 + $1.netQuantity } }
    }

    /// GitHub's documented personal billing usage report does not return an entitlement/allowance.
    public var remainingAllowance: Double? { nil }

    private init(period: CopilotUsagePeriod, items: [CopilotUsageItem], fetchedAt: Date) {
        self.period = period
        self.items = items
        self.fetchedAt = fetchedAt
    }

    public static func parse(_ data: Data, now: Date = .now) throws -> CopilotUsageReport {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let object = root as? [String: Any],
              let timePeriod = object["timePeriod"] as? [String: Any],
              let year = (timePeriod["year"] as? NSNumber)?.intValue,
              let month = (timePeriod["month"] as? NSNumber)?.intValue,
              (1...12).contains(month),
              let rawItems = object["usageItems"] as? [[String: Any]] else {
            throw UsageParseError.invalidCopilotResponse
        }
        let items = try rawItems.map(CopilotUsageItem.init(json:))
        return CopilotUsageReport(period: CopilotUsagePeriod(year: year, month: month), items: items, fetchedAt: now)
    }
}

public enum UsageParseError: Error, Equatable {
    case invalidCodexResponse
    case codexLimitsUnavailable
    case invalidCopilotResponse
    case invalidCopilotItem
    case copilotQuotaUnavailable
}
