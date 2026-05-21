//
//  ObjCExceptionTests.mm
//  ObjCException_Tests
//
//  Covers both API tiers:
//   - OCEException class (Swift-safe, siglongjmp escape)
//   - oce_try_catch* C functions (ObjC/C++ only, real exception unwind)
//

#import <XCTest/XCTest.h>
#import <ObjCException/ObjCException.h>

#include <atomic>
#include <pthread.h>
#include <signal.h>

#pragma mark - C++ destructor probe

namespace {
struct DestructorProbe {
    std::atomic<int> *count;
    explicit DestructorProbe(std::atomic<int> *c) noexcept : count(c) {}
    ~DestructorProbe() noexcept { count->fetch_add(1, std::memory_order_relaxed); }
    DestructorProbe(const DestructorProbe &) = delete;
    DestructorProbe &operator=(const DestructorProbe &) = delete;
};
}  // namespace

#pragma mark -

@interface ObjCExceptionTests : XCTestCase
@end

@implementation ObjCExceptionTests

+ (void)setUp {
    [super setUp];
    // App delegate already enabled it; idempotent call covers headless test runs too.
    int err = [OCEException enable];
    XCTAssertEqual(0, err, @"OCEException enable failed: %d", err);
}

- (void)tearDown {
    // Tests below replace the global handler; reset to nil so subsequent tests
    // see a clean slate and the live host app doesn't keep a stale block.
    [OCEException setCaughtExceptionHandler:nil];
    [super tearDown];
}

#pragma mark - Tier 1: OCEException class — happy path

- (void)testCatchingReturnsNilOnSuccess {
    NSException *e = [OCEException catching:^{
        // no-op
    }];
    XCTAssertNil(e);
}

- (void)testCatchingForwardsNSException {
    NSException *e = [OCEException catching:^{
        [NSException raise:@"TierOneTest" format:@"reason %d", 42];
    }];
    XCTAssertNotNil(e);
    XCTAssertEqualObjects(@"TierOneTest", e.name);
    XCTAssertEqualObjects(@"reason 42", e.reason);
}

#pragma mark - Tier 1: signal capture

- (void)testCatchingSIGABRT {
    NSException *e = [OCEException catching:^{
        raise(SIGABRT);
    }];
    XCTAssertNotNil(e);
    XCTAssertEqualObjects(@"SIGABRT", e.name);
}

- (void)testCatchingSIGSEGV {
    NSException *e = [OCEException catching:^{
        volatile int *p = (volatile int *)0;
        *p = 1;
    }];
    XCTAssertNotNil(e);
    // x86_64 / arm64 simulators reliably deliver SIGSEGV for null deref.
    XCTAssertEqualObjects(@"SIGSEGV", e.name);
}

- (void)testCatchingSIGFPE {
    NSException *e = [OCEException catching:^{
        raise(SIGFPE);
    }];
    XCTAssertNotNil(e);
    XCTAssertEqualObjects(@"SIGFPE", e.name);
}

- (void)testCatchingSIGBUS {
    NSException *e = [OCEException catching:^{
        raise(SIGBUS);
    }];
    XCTAssertNotNil(e);
    XCTAssertEqualObjects(@"SIGBUS", e.name);
}

- (void)testCatchingSIGILL {
    NSException *e = [OCEException catching:^{
        raise(SIGILL);
    }];
    XCTAssertNotNil(e);
    XCTAssertEqualObjects(@"SIGILL", e.name);
}

- (void)testCallStackSymbolsPopulated {
    NSException *e = [OCEException catching:^{
        raise(SIGABRT);
    }];
    XCTAssertNotNil(e);
    NSArray<NSString *> *symbols = [e callStackSymbols];
    XCTAssertNotNil(symbols);
    XCTAssertGreaterThan(symbols.count, 0u);
}

#pragma mark - Tier 1: finally semantics

- (void)testFinallyRunsOnSuccess {
    __block BOOL ran = NO;
    NSException *e = [OCEException catching:^{
        // no-op
    } finally:^{
        ran = YES;
    }];
    XCTAssertNil(e);
    XCTAssertTrue(ran);
}

- (void)testFinallyRunsOnNSException {
    __block BOOL ran = NO;
    NSException *e = [OCEException catching:^{
        [NSException raise:@"X" format:@"y"];
    } finally:^{
        ran = YES;
    }];
    XCTAssertNotNil(e);
    XCTAssertTrue(ran);
}

- (void)testFinallyRunsOnSignal {
    // SIGSEGV via volatile null deref — synchronously delivered to the
    // faulting thread by the kernel. raise(SIGABRT) on iOS Simulator on
    // Apple Silicon goes through __kill(getpid()) and can be delivered to
    // a different thread depending on cumulative signal traffic.
    __block BOOL ran = NO;
    NSException *e = [OCEException catching:^{
        volatile int *p = (volatile int *)0;
        *p = 1;
    } finally:^{
        ran = YES;
    }];
    XCTAssertNotNil(e);
    XCTAssertTrue(ran);
}

#pragma mark - Tier 1: nesting

- (void)testNestedCatching_innerHandlesSignal {
    // See testFinallyRunsOnSignal for why this uses SIGSEGV not SIGABRT.
    __block BOOL outerBodyCompleted = NO;
    __block NSException *innerE = nil;
    NSException *outerE = [OCEException catching:^{
        innerE = [OCEException catching:^{
            volatile int *p = (volatile int *)0;
            *p = 1;
        }];
        outerBodyCompleted = YES;
    }];
    XCTAssertNotNil(innerE);
    XCTAssertEqualObjects(@"SIGSEGV", innerE.name);
    XCTAssertNil(outerE);
    XCTAssertTrue(outerBodyCompleted);
}

- (void)testNestedCatching_outerHandlesNSException {
    NSException *outerE = [OCEException catching:^{
        NSException *innerE = [OCEException catching:^{
            // body runs cleanly, then we throw out of the inner catch frame
        }];
        XCTAssertNil(innerE);
        [NSException raise:@"OuterEx" format:@"a"];
    }];
    XCTAssertNotNil(outerE);
    XCTAssertEqualObjects(@"OuterEx", outerE.name);
}

#pragma mark - Cross-tier nesting

// Outer = oce_try_catch (cpp_throw), inner = OCEException.catching (longjmp_).
// Inner consumes the signal via siglongjmp; outer's catch must NOT fire.
- (void)testCrossTier_cppOuter_longjmpInner_signalCaughtByInner {
    __block NSException *innerE = nil;
    __block NSException *outerE = nil;
    __block BOOL outerBodyCompleted = NO;
    oce_try_catch(^{
        innerE = [OCEException catching:^{
            volatile int *p = (volatile int *)0;
            *p = 1;
        }];
        outerBodyCompleted = YES;
    }, ^(NSException *e) {
        outerE = e;
    });
    XCTAssertNotNil(innerE);
    XCTAssertEqualObjects(@"SIGSEGV", innerE.name);
    XCTAssertNil(outerE);
    XCTAssertTrue(outerBodyCompleted);
}

// Outer = oce_try_catch (cpp_throw), inner = OCEException.catching (longjmp_).
// Inner runs clean; outer raises an NSException afterwards — outer's @catch
// should fire, proving the cpp_throw frame is still on top after inner pops.
- (void)testCrossTier_cppOuter_longjmpInner_outerRaisesAfter {
    __block NSException *outerE = nil;
    oce_try_catch(^{
        NSException *innerE = [OCEException catching:^{
            // clean
        }];
        XCTAssertNil(innerE);
        [NSException raise:@"FromOuterTier" format:@"x"];
    }, ^(NSException *e) {
        outerE = e;
    });
    XCTAssertNotNil(outerE);
    XCTAssertEqualObjects(@"FromOuterTier", outerE.name);
}

// Outer = OCEException.catching (longjmp_), inner = oce_try_catch (cpp_throw).
// Inner catches the signal via objc_exception_throw + C++ unwinder; outer's
// catching should return nil because no exception escapes inner.
//
// Uses pthread_kill(SIGABRT) rather than volatile null deref because the
// cpp_throw tier needs the unwinder to resume from a clean PC (return from
// the kill syscall), not the middle of an instruction fault. raise(SIGABRT)
// would also yield a clean PC, but on iOS Simulator on Apple Silicon it goes
// through __kill(getpid()) and the kernel can deliver to a thread with no
// active catch frame depending on cumulative signal traffic earlier in the
// test run; pthread_kill is per-thread by definition.
- (void)testCrossTier_longjmpOuter_cppInner_signalCaughtByInner {
    // Defensive unblock: on iOS Simulator on Apple Silicon, prior tests in
    // the suite that called raise(SIGABRT) leave the test thread's mask
    // with SIGABRT blocked, even after the matching handler has finished.
    // The likely cause is that raise(SIGABRT) is implemented as
    // __kill(getpid(), SIGABRT) and the kernel's per-thread "currently
    // delivering" state is sticky on threads that didn't actually run the
    // handler. siglongjmp / explicit sigprocmask in the handler can only
    // fix the thread that ran it. Every test that pthread_kill's a signal
    // it expects the library to catch must unblock it explicitly first.
    sigset_t unblock_set;
    sigemptyset(&unblock_set);
    sigaddset(&unblock_set, SIGABRT);
    pthread_sigmask(SIG_UNBLOCK, &unblock_set, NULL);

    __block NSException *innerE = nil;
    __block BOOL outerBodyCompleted = NO;
    NSException *outerE = [OCEException catching:^{
        oce_try_catch(^{
            pthread_kill(pthread_self(), SIGABRT);
        }, ^(NSException *e) {
            innerE = e;
        });
        outerBodyCompleted = YES;
    }];
    XCTAssertNotNil(innerE);
    XCTAssertEqualObjects(@"SIGABRT", innerE.name);
    XCTAssertNil(outerE);
    XCTAssertTrue(outerBodyCompleted);
}

// Cross-tier C++ destructor semantics: an RAII object declared in the OUTER
// cpp_throw scope (around an inner longjmp_ frame) still gets destructed
// when the outer scope exits normally — siglongjmp's lack of unwind in the
// inner frame doesn't affect the outer scope's automatic storage.
- (void)testCrossTier_cppOuter_longjmpInner_outerScopeDestructorRuns {
    std::atomic<int> dtorCount{0};
    std::atomic<int> *dtorCountPtr = &dtorCount;
    __block NSException *innerE = nil;

    oce_try_catch(^{
        DestructorProbe outerProbe(dtorCountPtr);
        innerE = [OCEException catching:^{
            volatile int *p = (volatile int *)0;
            *p = 1;
        }];
        // outerProbe destructs at scope exit, regardless of inner's signal path
    }, ^(NSException *e) {
        // not expected to fire
        XCTFail(@"outer catch should not run");
    });

    XCTAssertNotNil(innerE);
    XCTAssertEqualObjects(@"SIGSEGV", innerE.name);
    XCTAssertEqual(1, dtorCount.load(std::memory_order_relaxed));
}

#pragma mark - Tier 1: handler callback

- (void)testCaughtExceptionHandlerInvokedOnce {
    __block int callbackCount = 0;
    __block NSString *seenName = nil;
    [OCEException setCaughtExceptionHandler:^(NSException *e) {
        callbackCount++;
        seenName = e.name;
    }];

    NSException *e = [OCEException catching:^{
        raise(SIGABRT);
    }];

    XCTAssertNotNil(e);
    XCTAssertEqual(1, callbackCount);
    XCTAssertEqualObjects(@"SIGABRT", seenName);
}

- (void)testCaughtExceptionHandlerNotInvokedForNSException {
    // The handler is documented as pre-delivery for caught SIGNAL exceptions.
    // NSException re-throws are not pre-routed through the handler.
    __block int callbackCount = 0;
    [OCEException setCaughtExceptionHandler:^(NSException *e) {
        callbackCount++;
    }];

    NSException *e = [OCEException catching:^{
        [NSException raise:@"Boom" format:@"x"];
    }];

    XCTAssertNotNil(e);
    XCTAssertEqual(0, callbackCount);
}

#pragma mark - Tier 1: idempotent enable / disable

- (void)testEnableIsIdempotent {
    XCTAssertEqual(0, [OCEException enable]);
    XCTAssertEqual(0, [OCEException enable]);
}

#pragma mark - Tier 1: concurrency

- (void)testConcurrentCatchingFromManyThreads {
    // Use a synchronous fault (volatile null deref → SIGSEGV) instead of
    // raise(SIGABRT). On Darwin, raise(SIGABRT) goes through kill(getpid())
    // path in some configurations (observed on iOS Simulator on Apple
    // Silicon), and the kernel can deliver SIGABRT to *any* thread that
    // doesn't have it masked — including threads with no active catch
    // frame. SIGSEGV from a faulting load is synchronous and guaranteed
    // per-thread, which is what we actually want to test.
    const int N = 8;
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();
    std::atomic<int> caught{0};
    std::atomic<int> *caughtPtr = &caught;

    for (int i = 0; i < N; i++) {
        dispatch_group_async(group, q, ^{
            NSException *e = [OCEException catching:^{
                volatile int *p = (volatile int *)0;
                *p = 1;
            }];
            if (e && [e.name isEqualToString:@"SIGSEGV"]) {
                caughtPtr->fetch_add(1, std::memory_order_relaxed);
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    XCTAssertEqual(N, caught.load(std::memory_order_relaxed));
}

- (void)testConcurrentCatchingNSExceptionFromManyThreads {
    // Pure user-space exception path — exercises thread-local catch_frame
    // stack without involving signal delivery.
    const int N = 16;
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();
    std::atomic<int> caught{0};
    std::atomic<int> *caughtPtr = &caught;

    for (int i = 0; i < N; i++) {
        dispatch_group_async(group, q, ^{
            NSException *e = [OCEException catching:^{
                [NSException raise:@"ConcEx" format:@"i=%d", i];
            }];
            if (e && [e.name isEqualToString:@"ConcEx"]) {
                caughtPtr->fetch_add(1, std::memory_order_relaxed);
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    XCTAssertEqual(N, caught.load(std::memory_order_relaxed));
}

#pragma mark - Tier 2: C API — ObjC/C++ only

- (void)testCAPI_oce_try_catch_NSException {
    __block NSException *captured = nil;
    oce_try_catch(^{
        [NSException raise:@"CAPI" format:@"hi"];
    }, ^(NSException *e) {
        captured = e;
    });
    XCTAssertNotNil(captured);
    XCTAssertEqualObjects(@"CAPI", captured.name);
}

- (void)testCAPI_oce_try_catch_signal {
    __block NSException *captured = nil;
    oce_try_catch(^{
        raise(SIGABRT);
    }, ^(NSException *e) {
        captured = e;
    });
    XCTAssertNotNil(captured);
    XCTAssertEqualObjects(@"SIGABRT", captured.name);
}

- (void)testCAPI_finally_success {
    __block int finallyCount = 0;
    oce_try_catch_finally(^{
        // success
    }, nil, ^{
        finallyCount++;
    });
    XCTAssertEqual(1, finallyCount);
}

- (void)testCAPI_finally_NSException {
    __block int finallyCount = 0;
    __block NSException *captured = nil;
    oce_try_catch_finally(^{
        [NSException raise:@"X" format:@"y"];
    }, ^(NSException *e) {
        captured = e;
    }, ^{
        finallyCount++;
    });
    XCTAssertNotNil(captured);
    XCTAssertEqual(1, finallyCount);
}

- (void)testCAPI_finally_signal {
    __block int finallyCount = 0;
    __block NSException *captured = nil;
    oce_try_catch_finally(^{
        raise(SIGABRT);
    }, ^(NSException *e) {
        captured = e;
    }, ^{
        finallyCount++;
    });
    XCTAssertNotNil(captured);
    XCTAssertEqual(1, finallyCount);
}

- (void)testCAPI_cppDestructorRunsOnSignalUnwind {
    std::atomic<int> dtorCount{0};
    std::atomic<int> *dtorCountPtr = &dtorCount;
    __block NSException *captured = nil;

    oce_try_catch(^{
        DestructorProbe probe(dtorCountPtr);
        raise(SIGABRT);
    }, ^(NSException *e) {
        captured = e;
    });

    XCTAssertNotNil(captured);
    XCTAssertEqual(1, dtorCount.load(std::memory_order_relaxed));
}

- (void)testCAPI_cppDestructorRunsOnNSExceptionUnwind {
    std::atomic<int> dtorCount{0};
    std::atomic<int> *dtorCountPtr = &dtorCount;
    __block NSException *captured = nil;

    oce_try_catch(^{
        DestructorProbe probe(dtorCountPtr);
        [NSException raise:@"BoomCpp" format:@"z"];
    }, ^(NSException *e) {
        captured = e;
    });

    XCTAssertNotNil(captured);
    XCTAssertEqual(1, dtorCount.load(std::memory_order_relaxed));
}

@end
