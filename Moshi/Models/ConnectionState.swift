import Foundation
import SwiftUI

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case reconnecting
    case disconnecting
    case error(String)

    var isActive: Bool {
        switch self {
        case .connected, .reconnecting:
            return true
        default:
            return false
        }
    }

    var isConnecting: Bool {
        switch self {
        case .connecting, .authenticating:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .authenticating:
            return "Authenticating..."
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting..."
        case .disconnecting:
            return "Disconnecting..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var color: Color {
        switch self {
        case .disconnected:
            return .gray
        case .connecting, .authenticating:
            return .yellow
        case .connected:
            return .green
        case .reconnecting:
            return .orange
        case .disconnecting:
            return .yellow
        case .error:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .disconnected:
            return "circle"
        case .connecting, .authenticating:
            return "circle.dotted"
        case .connected:
            return "circle.fill"
        case .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .disconnecting:
            return "circle.dotted"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }
}
