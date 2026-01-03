import Foundation
import os.log

enum Logger {
    static let network = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.moshi", category: "Network")
    static let session = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.moshi", category: "Session")
    static let terminal = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.moshi", category: "Terminal")
    static let security = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.moshi", category: "Security")
    static let tmux = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.moshi", category: "Tmux")
    static let general = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.moshi", category: "General")
}

// MARK: - Logging Extensions

extension OSLog {
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        os_log(.debug, log: self, "%{public}@", formatMessage(message, file: file, function: function, line: line))
        #endif
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log(.info, log: self, "%{public}@", formatMessage(message, file: file, function: function, line: line))
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log(.default, log: self, "⚠️ %{public}@", formatMessage(message, file: file, function: function, line: line))
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log(.error, log: self, "❌ %{public}@", formatMessage(message, file: file, function: function, line: line))
    }

    func fault(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log(.fault, log: self, "💥 %{public}@", formatMessage(message, file: file, function: function, line: line))
    }

    private func formatMessage(_ message: String, file: String, function: String, line: Int) -> String {
        let fileName = (file as NSString).lastPathComponent
        return "[\(fileName):\(line)] \(function) - \(message)"
    }
}

// MARK: - Debug Logger

#if DEBUG
final class DebugLogger {
    static let shared = DebugLogger()

    private var logs: [LogEntry] = []
    private let maxLogs = 1000
    private let queue = DispatchQueue(label: "com.moshi.debuglogger")

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String

        enum Level: String {
            case debug = "DEBUG"
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
        }
    }

    private init() {}

    func log(_ level: LogEntry.Level, category: String, message: String) {
        queue.async { [weak self] in
            let entry = LogEntry(
                timestamp: Date(),
                level: level,
                category: category,
                message: message
            )

            self?.logs.append(entry)

            if let count = self?.logs.count, count > self!.maxLogs {
                self?.logs.removeFirst(count - self!.maxLogs)
            }
        }
    }

    func getLogs() -> [LogEntry] {
        queue.sync { logs }
    }

    func clear() {
        queue.async { [weak self] in
            self?.logs.removeAll()
        }
    }

    func export() -> String {
        let entries = getLogs()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
#endif

// MARK: - Performance Logging

final class PerformanceLogger {
    static let shared = PerformanceLogger()

    private var timers: [String: CFAbsoluteTime] = [:]
    private let queue = DispatchQueue(label: "com.moshi.perflogger")

    private init() {}

    func start(_ identifier: String) {
        queue.async { [weak self] in
            self?.timers[identifier] = CFAbsoluteTimeGetCurrent()
        }
    }

    func end(_ identifier: String) -> TimeInterval? {
        queue.sync { [weak self] in
            guard let startTime = self?.timers.removeValue(forKey: identifier) else {
                return nil
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            #if DEBUG
            Logger.general.debug("⏱ \(identifier): \(String(format: "%.3f", elapsed * 1000))ms")
            #endif

            return elapsed
        }
    }

    @discardableResult
    func measure<T>(_ identifier: String, block: () throws -> T) rethrows -> T {
        start(identifier)
        defer { _ = end(identifier) }
        return try block()
    }

    @discardableResult
    func measure<T>(_ identifier: String, block: () async throws -> T) async rethrows -> T {
        start(identifier)
        defer { _ = end(identifier) }
        return try await block()
    }
}

// MARK: - Network Logger

#if DEBUG
final class NetworkLogger {
    static let shared = NetworkLogger()

    private var requests: [NetworkLogEntry] = []
    private let maxEntries = 100
    private let queue = DispatchQueue(label: "com.moshi.networklogger")

    struct NetworkLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: EntryType
        let message: String
        let data: Data?

        enum EntryType: String {
            case sent = "→"
            case received = "←"
            case error = "✗"
            case info = "ℹ"
        }
    }

    private init() {}

    func logSent(_ message: String, data: Data? = nil) {
        log(.sent, message: message, data: data)
    }

    func logReceived(_ message: String, data: Data? = nil) {
        log(.received, message: message, data: data)
    }

    func logError(_ message: String) {
        log(.error, message: message, data: nil)
    }

    func logInfo(_ message: String) {
        log(.info, message: message, data: nil)
    }

    private func log(_ type: NetworkLogEntry.EntryType, message: String, data: Data?) {
        queue.async { [weak self] in
            let entry = NetworkLogEntry(
                timestamp: Date(),
                type: type,
                message: message,
                data: data
            )

            self?.requests.append(entry)

            if let count = self?.requests.count, count > self!.maxEntries {
                self?.requests.removeFirst(count - self!.maxEntries)
            }
        }
    }

    func getEntries() -> [NetworkLogEntry] {
        queue.sync { requests }
    }

    func clear() {
        queue.async { [weak self] in
            self?.requests.removeAll()
        }
    }
}
#endif
