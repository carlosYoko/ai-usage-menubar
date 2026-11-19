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
}
