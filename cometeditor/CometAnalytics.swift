import Foundation
import Combine

// MARK: - Event Types

public enum CometEventType: String {
    case pageView       = "pageView"
    case imageConverted = "imageConverted"
    case videoConverted = "videoConverted"
    case ocrUsed        = "ocrUsed"
    case bgRemoved      = "bgRemoved"
    case qrGenerated    = "qrGenerated"
    case pdfEdited      = "pdfEdited"
    case fontDownloaded = "fontDownloaded"
    case stockDownloaded = "stockDownloaded"
}

// MARK: - Config Models

public struct AppConfig {
    public struct MaintenanceInfo {
        public let isEnabled: Bool
        public let message: String
        public let endAt: Date?
    }
    public struct ForceUpdateInfo {
        public let isEnabled: Bool
        public let minVersion: String
        public let message: String
        public let storeUrl: String
    }
    public struct AdInfo: Identifiable {
        public let id: Int
        public let title: String
        public let imageUrl: String
        public let linkUrl: String
        public let type: String      // "modal" | "inline"
        public let targetPage: String?
        public let priority: Int
    }
    public let maintenanceMode: MaintenanceInfo
    public let forceUpdate: ForceUpdateInfo
    public let ads: [AdInfo]

    static let safeDefault = AppConfig(
        maintenanceMode: MaintenanceInfo(isEnabled: false, message: "", endAt: nil),
        forceUpdate: ForceUpdateInfo(isEnabled: false, minVersion: "0.0.0", message: "", storeUrl: ""),
        ads: []
    )
}

// MARK: - SDK

public final class CometAnalytics: @unchecked Sendable {
    public static let shared = CometAnalytics()
    private init() {}

    private(set) var apiKey: String = ""
    private(set) var baseURL: URL?

    // Persistent session ID — same across app launches
    public private(set) lazy var sessionId: String = {
        let key = "comet_analytics_session_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }()

    private var queue: [[String: Any]] = []
    private let queueLock = NSLock()
    private var flushTimer: Foundation.Timer?
    private let maxQueueSize = 20
    private let flushInterval: TimeInterval = 30

    private lazy var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    private lazy var osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
    private lazy var deviceModel: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }()

    // MARK: - Configuration

    public func configure(apiKey: String, baseURL: String) {
        self.apiKey = apiKey
        self.baseURL = URL(string: baseURL)
        _ = sessionId
        _ = appVersion
        _ = osVersion
        _ = deviceModel
        startFlushTimer()
    }

    // MARK: - Track

    public func trackEvent(
        page: String? = nil,
        eventType: CometEventType,
        metadata: [String: Any]? = nil
    ) {
        var event: [String: Any] = [
            "sessionId":   sessionId,
            "eventType":   eventType.rawValue,
            "appVersion":  appVersion,
            "osVersion":   osVersion,
            "deviceModel": deviceModel,
        ]
        if let page { event["page"] = page }
        if let metadata { event["metadata"] = metadata }

        queueLock.lock()
        queue.append(event)
        let shouldFlush = queue.count >= maxQueueSize
        queueLock.unlock()

        if shouldFlush { flush() }
    }

    // MARK: - Fetch Config

    private let configCacheKey    = "comet_cached_config"
    private let configCacheTimeKey = "comet_cached_config_time"
    private let cacheTTL: TimeInterval = 300 // 5 dakika

    /// Cache geçerliyse sunucuya gitmez (TTL: 1 saat).
    /// `forceRefresh: true` ile TTL'i atlayıp sunucudan taze veri çeker.
    /// Sunucuya ulaşılamazsa cache'i, o da yoksa safe default'u döner.
    public func fetchConfig(forceRefresh: Bool = false) async -> AppConfig {
        // Cache hâlâ geçerliyse sunucuya gitme
        if !forceRefresh, let cached = cachedConfig() {
            return cached
        }

        // Sunucudan çek
        if let base = baseURL {
            var req = URLRequest(url: base.appendingPathComponent("/api/sdk/config"))
            req.setValue(apiKey, forHTTPHeaderField: "X-App-Key")
            req.timeoutInterval = 8
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let config = try? parseConfig(from: data) {
                UserDefaults.standard.set(data, forKey: configCacheKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: configCacheTimeKey)
                return config
            }
        }

        // Sunucu yanıt vermedi — süresi dolmuş cache bile olsa kullan
        if let cached = UserDefaults.standard.data(forKey: configCacheKey),
           let config = try? parseConfig(from: cached) {
            return config
        }

        return .safeDefault
    }

    private func cachedConfig() -> AppConfig? {
        let savedAt = UserDefaults.standard.double(forKey: configCacheTimeKey)
        guard savedAt > 0,
              Date().timeIntervalSince1970 - savedAt < cacheTTL,
              let data = UserDefaults.standard.data(forKey: configCacheKey),
              let config = try? parseConfig(from: data) else { return nil }
        return config
    }

    // MARK: - Flush

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushTimer?.invalidate()
            self.flushTimer = Foundation.Timer.scheduledTimer(
                withTimeInterval: self.flushInterval,
                repeats: true
            ) { [weak self] _ in self?.flush() }
        }
    }

    private func flush() {
        queueLock.lock()
        guard !queue.isEmpty else { queueLock.unlock(); return }
        let batch = queue
        queue.removeAll()
        queueLock.unlock()

        Task {
            for event in batch {
                try? await sendEvent(event)
            }
        }
    }

    private func sendEvent(_ event: [String: Any]) async throws {
        guard let base = baseURL else { return }
        var req = URLRequest(url: base.appendingPathComponent("/api/sdk/event"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-App-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: event)
        req.timeoutInterval = 15
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Config Parsing

    private func parseConfig(from data: Data) throws -> AppConfig {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        let mJson = json["maintenanceMode"] as? [String: Any] ?? [:]
        let maintenance = AppConfig.MaintenanceInfo(
            isEnabled: mJson["isEnabled"] as? Bool ?? false,
            message: mJson["message"] as? String ?? "",
            endAt: (mJson["endAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        )

        let fJson = json["forceUpdate"] as? [String: Any] ?? [:]
        let forceUpdate = AppConfig.ForceUpdateInfo(
            isEnabled: fJson["isEnabled"] as? Bool ?? false,
            minVersion: fJson["minVersion"] as? String ?? "1.0.0",
            message: fJson["message"] as? String ?? "",
            storeUrl: fJson["storeUrl"] as? String ?? ""
        )

        let adsJson = json["ads"] as? [[String: Any]] ?? []
        let ads = adsJson.compactMap { a -> AppConfig.AdInfo? in
            guard let id = a["id"] as? Int,
                  let title = a["title"] as? String,
                  let imageUrl = a["imageUrl"] as? String,
                  let linkUrl = a["linkUrl"] as? String,
                  let type = a["type"] as? String else { return nil }
            return AppConfig.AdInfo(
                id: id,
                title: title,
                imageUrl: imageUrl,
                linkUrl: linkUrl,
                type: type,
                targetPage: a["targetPage"] as? String,
                priority: a["priority"] as? Int ?? 0
            )
        }

        return AppConfig(maintenanceMode: maintenance, forceUpdate: forceUpdate, ads: ads)
    }

    // MARK: - Semver Helper

    /// Returns true if `current` is below `minimum`
    public static func isVersionBelow(_ current: String, minimum: String) -> Bool {
        let parse = { (v: String) in v.split(separator: ".").compactMap { Int($0) } }
        let c = parse(current)
        let m = parse(minimum)
        for i in 0..<max(c.count, m.count) {
            let cv = i < c.count ? c[i] : 0
            let mv = i < m.count ? m[i] : 0
            if cv < mv { return true }
            if cv > mv { return false }
        }
        return false
    }
}
