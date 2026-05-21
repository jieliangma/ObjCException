//
//  ObjCExceptionSwiftTests.swift
//  ObjCException_Tests
//
//  Validates that OCEException.catching reaches across Swift frames —
//  the whole point of the siglongjmp tier.
//

import XCTest
import ObjCException

final class ObjCExceptionSwiftTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        let err = OCEException.enable()
        XCTAssertEqual(0, err)
    }

    override func tearDown() {
        OCEException.setCaughtExceptionHandler(nil)
        super.tearDown()
    }

    func testSwiftForceUnwrapNilCaught() {
        let exception = OCEException.catching {
            let optional: String? = nil
            _ = optional!
        }
        XCTAssertNotNil(exception)
        // Swift runtime fatal-error path varies by version: abort()→SIGABRT on
        // older runtimes, __builtin_trap()→SIGTRAP on Swift 5.x+. Either is
        // acceptable; the contract is just that the crash is caught.
        let name = exception?.name.rawValue ?? ""
        XCTAssertTrue(["SIGABRT", "SIGTRAP", "SIGILL"].contains(name),
                      "Unexpected signal name: \(name)")
    }

    func testSwiftCleanBlockReturnsNil() {
        let exception = OCEException.catching {
            _ = (1...10).reduce(0, +)
        }
        XCTAssertNil(exception)
    }

    func testSwiftRaiseSIGABRTCaught() {
        let exception = OCEException.catching {
            raise(SIGABRT)
        }
        XCTAssertNotNil(exception)
        XCTAssertEqual(exception?.name.rawValue, "SIGABRT")
    }

    func testSwiftFinallyRunsOnSignalPath() {
        var ran = false
        let exception = OCEException.catching({
            raise(SIGABRT)
        }, finally: {
            ran = true
        })
        XCTAssertNotNil(exception)
        XCTAssertTrue(ran)
    }

    func testSwiftFinallyRunsOnSuccessPath() {
        var ran = false
        let exception = OCEException.catching({
            // no-op
        }, finally: {
            ran = true
        })
        XCTAssertNil(exception)
        XCTAssertTrue(ran)
    }

    func testSwiftHandlerCallbackFires() {
        var callbackCount = 0
        OCEException.setCaughtExceptionHandler { _ in
            callbackCount += 1
        }
        _ = OCEException.catching {
            raise(SIGABRT)
        }
        XCTAssertEqual(1, callbackCount)
    }
}
