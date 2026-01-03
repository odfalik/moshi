import XCTest
import SwiftUI
@testable import Moshi

final class ConnectionStateTests: XCTestCase {

    // MARK: - isActive Tests

    func testIsActiveConnected() {
        let state = ConnectionState.connected
        XCTAssertTrue(state.isActive)
    }

    func testIsActiveReconnecting() {
        let state = ConnectionState.reconnecting
        XCTAssertTrue(state.isActive)
    }

    func testIsActiveDisconnected() {
        let state = ConnectionState.disconnected
        XCTAssertFalse(state.isActive)
    }

    func testIsActiveConnecting() {
        let state = ConnectionState.connecting
        XCTAssertFalse(state.isActive)
    }

    func testIsActiveError() {
        let state = ConnectionState.error("Test error")
        XCTAssertFalse(state.isActive)
    }

    // MARK: - isConnecting Tests

    func testIsConnectingConnecting() {
        let state = ConnectionState.connecting
        XCTAssertTrue(state.isConnecting)
    }

    func testIsConnectingAuthenticating() {
        let state = ConnectionState.authenticating
        XCTAssertTrue(state.isConnecting)
    }

    func testIsConnectingConnected() {
        let state = ConnectionState.connected
        XCTAssertFalse(state.isConnecting)
    }

    func testIsConnectingDisconnected() {
        let state = ConnectionState.disconnected
        XCTAssertFalse(state.isConnecting)
    }

    // MARK: - displayName Tests

    func testDisplayNameDisconnected() {
        let state = ConnectionState.disconnected
        XCTAssertEqual(state.displayName, "Disconnected")
    }

    func testDisplayNameConnecting() {
        let state = ConnectionState.connecting
        XCTAssertEqual(state.displayName, "Connecting...")
    }

    func testDisplayNameAuthenticating() {
        let state = ConnectionState.authenticating
        XCTAssertEqual(state.displayName, "Authenticating...")
    }

    func testDisplayNameConnected() {
        let state = ConnectionState.connected
        XCTAssertEqual(state.displayName, "Connected")
    }

    func testDisplayNameReconnecting() {
        let state = ConnectionState.reconnecting
        XCTAssertEqual(state.displayName, "Reconnecting...")
    }

    func testDisplayNameDisconnecting() {
        let state = ConnectionState.disconnecting
        XCTAssertEqual(state.displayName, "Disconnecting...")
    }

    func testDisplayNameError() {
        let state = ConnectionState.error("Connection refused")
        XCTAssertEqual(state.displayName, "Error: Connection refused")
    }

    // MARK: - color Tests

    func testColorDisconnected() {
        let state = ConnectionState.disconnected
        XCTAssertEqual(state.color, Color.gray)
    }

    func testColorConnecting() {
        let state = ConnectionState.connecting
        XCTAssertEqual(state.color, Color.yellow)
    }

    func testColorConnected() {
        let state = ConnectionState.connected
        XCTAssertEqual(state.color, Color.green)
    }

    func testColorReconnecting() {
        let state = ConnectionState.reconnecting
        XCTAssertEqual(state.color, Color.orange)
    }

    func testColorError() {
        let state = ConnectionState.error("Test")
        XCTAssertEqual(state.color, Color.red)
    }

    // MARK: - icon Tests

    func testIconDisconnected() {
        let state = ConnectionState.disconnected
        XCTAssertEqual(state.icon, "circle")
    }

    func testIconConnecting() {
        let state = ConnectionState.connecting
        XCTAssertEqual(state.icon, "circle.dotted")
    }

    func testIconConnected() {
        let state = ConnectionState.connected
        XCTAssertEqual(state.icon, "circle.fill")
    }

    func testIconReconnecting() {
        let state = ConnectionState.reconnecting
        XCTAssertEqual(state.icon, "arrow.triangle.2.circlepath")
    }

    func testIconError() {
        let state = ConnectionState.error("Test")
        XCTAssertEqual(state.icon, "exclamationmark.circle.fill")
    }

    // MARK: - Equatable Tests

    func testEquatableConnected() {
        let state1 = ConnectionState.connected
        let state2 = ConnectionState.connected
        XCTAssertEqual(state1, state2)
    }

    func testEquatableError() {
        let state1 = ConnectionState.error("Error 1")
        let state2 = ConnectionState.error("Error 1")
        let state3 = ConnectionState.error("Error 2")

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testEquatableDifferentStates() {
        let state1 = ConnectionState.connected
        let state2 = ConnectionState.disconnected
        XCTAssertNotEqual(state1, state2)
    }
}
