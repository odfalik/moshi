import ActivityKit
import SwiftUI

struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var connectionState: String  // "connected", "connecting", "reconnecting"
        var duration: TimeInterval
        var bytesSent: Int
        var bytesReceived: Int
        var lastActivity: Date
    }

    // Fixed data that doesn't change during the activity
    var hostname: String
    var username: String
    var useMosh: Bool
    var hasTmux: Bool
    var sessionName: String?
}
