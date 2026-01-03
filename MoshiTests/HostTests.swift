import XCTest
@testable import Moshi

final class HostTests: XCTestCase {

    // MARK: - Host Initialization Tests

    func testHostDefaultInitialization() {
        let host = Host()

        XCTAssertNotNil(host.id)
        XCTAssertEqual(host.name, "")
        XCTAssertEqual(host.hostname, "")
        XCTAssertEqual(host.port, 22)
        XCTAssertEqual(host.username, "")
        XCTAssertEqual(host.authMethod, .password)
        XCTAssertTrue(host.useMosh)
        XCTAssertTrue(host.autoTmux)
        XCTAssertFalse(host.isFavorite)
    }

    func testHostCustomInitialization() {
        let host = Host(
            name: "Production Server",
            hostname: "prod.example.com",
            port: 2222,
            username: "admin",
            authMethod: .key,
            useMosh: false,
            autoTmux: false,
            isFavorite: true
        )

        XCTAssertEqual(host.name, "Production Server")
        XCTAssertEqual(host.hostname, "prod.example.com")
        XCTAssertEqual(host.port, 2222)
        XCTAssertEqual(host.username, "admin")
        XCTAssertEqual(host.authMethod, .key)
        XCTAssertFalse(host.useMosh)
        XCTAssertFalse(host.autoTmux)
        XCTAssertTrue(host.isFavorite)
    }

    // MARK: - Display Name Tests

    func testDisplayNameWithName() {
        let host = Host(name: "My Server", hostname: "server.local")
        XCTAssertEqual(host.displayName, "My Server")
    }

    func testDisplayNameWithoutName() {
        let host = Host(hostname: "server.local")
        XCTAssertEqual(host.displayName, "server.local")
    }

    func testDisplayNameWithEmptyName() {
        let host = Host(name: "", hostname: "server.local")
        XCTAssertEqual(host.displayName, "server.local")
    }

    // MARK: - Connection String Tests

    func testConnectionString() {
        let host = Host(hostname: "example.com", port: 22, username: "user")
        XCTAssertEqual(host.connectionString, "user@example.com:22")
    }

    func testConnectionStringCustomPort() {
        let host = Host(hostname: "example.com", port: 2222, username: "admin")
        XCTAssertEqual(host.connectionString, "admin@example.com:2222")
    }

    // MARK: - Effective Tmux Session Name Tests

    func testEffectiveTmuxSessionNameWithCustom() {
        let host = Host(hostname: "server.local", tmuxSessionName: "my-session")
        XCTAssertEqual(host.effectiveTmuxSessionName, "my-session")
    }

    func testEffectiveTmuxSessionNameWithDefault() {
        let host = Host(hostname: "server.local")
        XCTAssertEqual(host.effectiveTmuxSessionName, "moshi-server-local")
    }

    // MARK: - Codable Tests

    func testHostEncodingDecoding() throws {
        let host = Host(
            name: "Test Server",
            hostname: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .key,
            useMosh: true,
            autoTmux: true,
            group: "Development",
            isFavorite: true,
            colorTag: .blue
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(host)

        let decoder = JSONDecoder()
        let decodedHost = try decoder.decode(Host.self, from: data)

        XCTAssertEqual(decodedHost.id, host.id)
        XCTAssertEqual(decodedHost.name, host.name)
        XCTAssertEqual(decodedHost.hostname, host.hostname)
        XCTAssertEqual(decodedHost.port, host.port)
        XCTAssertEqual(decodedHost.username, host.username)
        XCTAssertEqual(decodedHost.authMethod, host.authMethod)
        XCTAssertEqual(decodedHost.useMosh, host.useMosh)
        XCTAssertEqual(decodedHost.autoTmux, host.autoTmux)
        XCTAssertEqual(decodedHost.group, host.group)
        XCTAssertEqual(decodedHost.isFavorite, host.isFavorite)
        XCTAssertEqual(decodedHost.colorTag, host.colorTag)
    }

    // MARK: - Hashable Tests

    func testHostHashable() {
        let host1 = Host(hostname: "server1.local", username: "user1")
        let host2 = Host(hostname: "server2.local", username: "user2")

        var set = Set<Host>()
        set.insert(host1)
        set.insert(host2)

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(host1))
        XCTAssertTrue(set.contains(host2))
    }

    // MARK: - Mosh Port Range Tests

    func testMoshPortRangeDefault() {
        let range = MoshPortRange()
        XCTAssertEqual(range.start, 60000)
        XCTAssertEqual(range.end, 61000)
    }

    func testMoshPortRangeCustom() {
        let range = MoshPortRange(start: 50000, end: 50100)
        XCTAssertEqual(range.start, 50000)
        XCTAssertEqual(range.end, 50100)
        XCTAssertEqual(range.description, "50000-50100")
    }
}
