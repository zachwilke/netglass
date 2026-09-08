import XCTest
@testable import NetglassCore

final class InputValidatorTests: XCTestCase {
    func testHostAcceptsIPv4AndHostname() throws {
        XCTAssertEqual(try InputValidator.host("1.1.1.1"), "1.1.1.1")
        XCTAssertEqual(try InputValidator.host("example.com"), "example.com")
        XCTAssertEqual(try InputValidator.host("[2001:db8::1]"), "2001:db8::1")
    }

    func testHostRejectsShellMetacharacters() {
        XCTAssertThrowsError(try InputValidator.host("example.com;reboot"))
        XCTAssertThrowsError(try InputValidator.host("host$(id)"))
        XCTAssertThrowsError(try InputValidator.host("-n"))
        XCTAssertThrowsError(try InputValidator.host("ex ample.com"))
    }

    func testScanTargetCapsPrefixWidth() throws {
        XCTAssertEqual(try InputValidator.scanTarget("192.168.1.0/24"), "192.168.1.0/24")
        XCTAssertThrowsError(try InputValidator.scanTarget("10.0.0.0/16"))
        XCTAssertThrowsError(try InputValidator.scanTarget("2001:db8::/64"))
    }

    func testURLRejectsCredentialsAndNonHTTP() {
        XCTAssertThrowsError(try InputValidator.httpURL("https://user:pass@example.com/"))
        XCTAssertThrowsError(try InputValidator.httpURL("file:///etc/passwd"))
        XCTAssertThrowsError(try InputValidator.httpURL("javascript:alert(1)"))
        XCTAssertNoThrow(try InputValidator.httpURL("https://example.com/path"))
    }

    func testSecretHeadersAreRejected() {
        XCTAssertThrowsError(try InputValidator.httpHeaders("Authorization: Bearer secret"))
        XCTAssertThrowsError(try InputValidator.httpHeaders("Cookie: a=b"))
        XCTAssertEqual(try InputValidator.httpHeaders("Accept: text/plain"), ["Accept: text/plain"])
    }

    func testBPFFilterRejectsFlagSmuggling() {
        XCTAssertThrowsError(try InputValidator.bpfFilter("-w /tmp/x"))
        XCTAssertThrowsError(try InputValidator.bpfFilter("-F /etc/passwd"))
        XCTAssertThrowsError(try InputValidator.bpfFilter("host; id"))
        XCTAssertEqual(try InputValidator.bpfFilter("port 443"), "port 443")
        XCTAssertEqual(try InputValidator.bpfFilter("host example.com and tcp"), "host example.com and tcp")
    }

    func testUserWritePathRejectsSystemPrefixes() {
        XCTAssertThrowsError(try InputValidator.userWritePath(URL(fileURLWithPath: "/etc/passwd")))
        XCTAssertThrowsError(try InputValidator.userWritePath(URL(fileURLWithPath: "/tmp/capture.pcap")))
        XCTAssertNoThrow(try InputValidator.userWritePath(URL(fileURLWithPath: "/Users/shared/capture.pcap")))
    }
}

final class ArgumentPolicyTests: XCTestCase {
    func testAllowsTameFlags() throws {
        XCTAssertEqual(try ArgumentPolicy.nmapExtras("-v --reason -T3"), ["-v", "--reason", "-T3"])
        XCTAssertEqual(try ArgumentPolicy.nmapExtras("-p 80,443"), ["-p", "80,443"])
        XCTAssertEqual(try ArgumentPolicy.nmapExtras("--top-ports 20"), ["--top-ports", "20"])
    }

    func testBlocksDangerousAndWideScans() {
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("--script vuln"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("-sS"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("-A"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("-oN out.txt"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("-p-"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("-p 1-65535"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("--top-ports 1000"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("--top-ports=65535"))
        XCTAssertThrowsError(try ArgumentPolicy.nmapExtras("-S 1.2.3.4"))
    }
}

final class BinaryLocatorTests: XCTestCase {
    func testExtraRootsMustBeAbsoluteAndNotTemporary() {
        XCTAssertNil(BinaryLocator.sanitizeExtraRoot("opt/homebrew/bin"))
        XCTAssertNil(BinaryLocator.sanitizeExtraRoot("../usr/bin"))
        XCTAssertNil(BinaryLocator.sanitizeExtraRoot("/tmp"))
        XCTAssertNil(BinaryLocator.sanitizeExtraRoot("/private/tmp/tools"))
        XCTAssertEqual(BinaryLocator.sanitizeExtraRoot("/opt/homebrew/bin"), "/opt/homebrew/bin")
    }

    func testRejectedLocations() {
        XCTAssertTrue(BinaryLocator.isRejectedLocation("/tmp/nmap"))
        XCTAssertTrue(BinaryLocator.isRejectedLocation("/var/tmp"))
        XCTAssertFalse(BinaryLocator.isRejectedLocation("/usr/bin"))
        XCTAssertFalse(BinaryLocator.isRejectedLocation("/sbin"))
    }
}

final class ConsoleTextTests: XCTestCase {
    func testStripsANSIAndCapsLength() {
        let colorful = "\u{001B}[31merror\u{001B}[0m"
        XCTAssertEqual(ConsoleText.sanitize(colorful), "error")
        let huge = String(repeating: "a", count: ConsoleText.maxLineCharacters + 50)
        let sanitized = ConsoleText.sanitize(huge)
        XCTAssertTrue(sanitized.hasSuffix("…"))
        XCTAssertLessThanOrEqual(sanitized.count, ConsoleText.maxLineCharacters + 1)
    }

    func testReplacesControlCharacters() {
        XCTAssertEqual(ConsoleText.sanitize("ok\u{0007}go"), "ok go")
    }
}
