import Foundation
import Network
import Combine

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: ConnectionType = .unknown
    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.moshi.networkmonitor")

    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case unknown = "Unknown"
    }

    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updatePath(path)
            }
        }
        monitor.start(queue: queue)
    }

    private func updatePath(_ path: NWPath) {
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained

        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }

        Logger.network.info("Network status: \(self.isConnected ? "Connected" : "Disconnected") via \(self.connectionType.rawValue)")
    }

    func checkTailscaleAvailability() async -> Bool {
        // Check if Tailscale interface is available
        let tailscaleMonitor = NWPathMonitor(requiredInterfaceType: .other)

        return await withCheckedContinuation { continuation in
            tailscaleMonitor.pathUpdateHandler = { path in
                // Check for tailscale0 or utun interfaces
                let hasTailscale = path.availableInterfaces.contains { interface in
                    interface.name.hasPrefix("utun") || interface.name == "tailscale0"
                }
                tailscaleMonitor.cancel()
                continuation.resume(returning: hasTailscale && path.status == .satisfied)
            }
            tailscaleMonitor.start(queue: queue)

            // Timeout after 2 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                tailscaleMonitor.cancel()
                continuation.resume(returning: false)
            }
        }
    }

    func checkHostReachability(_ hostname: String, port: Int) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(hostname),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)

        return await withCheckedContinuation { continuation in
            var completed = false

            connection.stateUpdateHandler = { state in
                guard !completed else { return }

                switch state {
                case .ready:
                    completed = true
                    connection.cancel()
                    continuation.resume(returning: true)

                case .failed, .cancelled:
                    completed = true
                    continuation.resume(returning: false)

                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                guard !completed else { return }
                completed = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - Network Quality

extension NetworkMonitor {
    struct NetworkQuality {
        var latency: TimeInterval
        var bandwidth: Double // Mbps estimate
        var reliability: Double // 0-1 score

        var isGoodForMosh: Bool {
            // Mosh works well even on poor connections
            return reliability > 0.3
        }

        var description: String {
            if latency < 50 && bandwidth > 10 {
                return "Excellent"
            } else if latency < 150 && bandwidth > 1 {
                return "Good"
            } else if latency < 500 {
                return "Fair"
            } else {
                return "Poor"
            }
        }
    }

    func measureQuality(to hostname: String) async -> NetworkQuality {
        var latencies: [TimeInterval] = []

        // Perform multiple pings
        for _ in 0..<5 {
            let start = Date()
            let reachable = await checkHostReachability(hostname, port: 22)
            let latency = Date().timeIntervalSince(start)

            if reachable {
                latencies.append(latency)
            }

            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between pings
        }

        guard !latencies.isEmpty else {
            return NetworkQuality(latency: .infinity, bandwidth: 0, reliability: 0)
        }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let reliability = Double(latencies.count) / 5.0

        // Rough bandwidth estimate based on connection type
        let bandwidth: Double
        switch connectionType {
        case .wifi:
            bandwidth = isConstrained ? 5 : 50
        case .cellular:
            bandwidth = isExpensive ? 2 : 20
        case .ethernet:
            bandwidth = 100
        case .unknown:
            bandwidth = 1
        }

        return NetworkQuality(
            latency: avgLatency * 1000, // Convert to ms
            bandwidth: bandwidth,
            reliability: reliability
        )
    }
}
