import XCTest
@testable import BonsaiCore
final class FoundationTests: XCTestCase { func testBoundaries() { XCTAssertTrue(within("/tmp/a/file","/tmp/a")); XCTAssertFalse(within("/tmp/ab","/tmp/a")) } }
