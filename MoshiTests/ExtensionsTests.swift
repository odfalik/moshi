import XCTest
@testable import Moshi

final class ExtensionsTests: XCTestCase {

    // MARK: - Data Extensions Tests

    func testDataHexString() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(data.hexString, "deadbeef")
    }

    func testDataFromHexString() {
        let data = Data(hexString: "deadbeef")
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 4)
        XCTAssertEqual(Array(data!), [0xDE, 0xAD, 0xBE, 0xEF])
    }

    func testDataFromHexStringWithSpaces() {
        let data = Data(hexString: "de ad be ef")
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 4)
    }

    func testDataFromInvalidHexString() {
        let data = Data(hexString: "xyz")
        XCTAssertNil(data)
    }

    func testDataSha256() {
        let data = Data("hello".utf8)
        let hash = data.sha256()
        XCTAssertEqual(hash.count, 32)
    }

    // MARK: - String Extensions Tests

    func testIsValidHostnameWithDomain() {
        XCTAssertTrue("example.com".isValidHostname)
        XCTAssertTrue("sub.example.com".isValidHostname)
        XCTAssertTrue("my-server.local".isValidHostname)
    }

    func testIsValidHostnameWithIP() {
        XCTAssertTrue("192.168.1.1".isValidHostname)
        XCTAssertTrue("10.0.0.1".isValidHostname)
        XCTAssertTrue("127.0.0.1".isValidHostname)
    }

    func testIsValidHostnameInvalid() {
        XCTAssertFalse("".isValidHostname)
        XCTAssertFalse("-invalid.com".isValidHostname)
    }

    func testIsValidUsername() {
        XCTAssertTrue("root".isValidUsername)
        XCTAssertTrue("admin".isValidUsername)
        XCTAssertTrue("user123".isValidUsername)
        XCTAssertTrue("my_user".isValidUsername)
    }

    func testIsValidUsernameInvalid() {
        XCTAssertFalse("123user".isValidUsername)
        XCTAssertFalse("User".isValidUsername) // Uppercase
        XCTAssertFalse("".isValidUsername)
    }

    func testTruncated() {
        let text = "This is a very long string"
        XCTAssertEqual(text.truncated(to: 10), "This is...")
        XCTAssertEqual(text.truncated(to: 100), text)
    }

    func testTruncatedWithCustomTrailing() {
        let text = "Hello World"
        XCTAssertEqual(text.truncated(to: 8, trailing: "~"), "Hello W~")
    }

    func testEscapedForShell() {
        XCTAssertEqual("hello".escapedForShell, "'hello'")
        XCTAssertEqual("it's".escapedForShell, "'it'\\''s'")
        XCTAssertEqual("with space".escapedForShell, "'with space'")
    }

    // MARK: - Color Extensions Tests

    func testColorFromHex6() {
        let color = Color(hex: "#FF0000")
        // We can't easily test the exact color values in SwiftUI
        // but we can verify it doesn't crash
        XCTAssertNotNil(color)
    }

    func testColorFromHex8() {
        let color = Color(hex: "#FF000080")
        XCTAssertNotNil(color)
    }

    func testColorFromHexWithoutHash() {
        let color = Color(hex: "00FF00")
        XCTAssertNotNil(color)
    }

    // MARK: - Date Extensions Tests

    func testRelativeString() {
        let now = Date()
        let oneHourAgo = Date(timeIntervalSinceNow: -3600)

        XCTAssertFalse(now.relativeString.isEmpty)
        XCTAssertFalse(oneHourAgo.relativeString.isEmpty)
    }

    // MARK: - Array Extensions Tests

    func testSafeSubscript() {
        let array = [1, 2, 3]

        XCTAssertEqual(array[safe: 0], 1)
        XCTAssertEqual(array[safe: 2], 3)
        XCTAssertNil(array[safe: 5])
        XCTAssertNil(array[safe: -1])
    }

    // MARK: - URL Extensions Tests

    func testQueryParameters() {
        let url = URL(string: "https://example.com?foo=bar&baz=qux")!
        let params = url.queryParameters

        XCTAssertNotNil(params)
        XCTAssertEqual(params?["foo"], "bar")
        XCTAssertEqual(params?["baz"], "qux")
    }

    func testQueryParametersEmpty() {
        let url = URL(string: "https://example.com")!
        let params = url.queryParameters

        XCTAssertNil(params)
    }
}
