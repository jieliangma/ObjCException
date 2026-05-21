//
//  ObjCException.h
//  ObjCException
//
//  Created by JieLiang Ma on 2023/7/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^oce_block_t)(void);
typedef void (^oce_catch_block_t)(NSException *exception);
typedef void (^oce_caught_exception_handler)(NSException *exception);

/// Public façade. The ObjC class form is the only one Swift can use safely;
/// the C functions below preserve C++ destructor / @finally unwinding for
/// Objective-C(++) callers but are not callable from Swift on ARM64 device
/// builds.
NS_SWIFT_NAME(OCEException)
@interface OCEException : NSObject

/// Install signal handlers for SIGABRT/SIGBUS/SIGFPE/SIGILL/SIGSEGV/SIGTRAP.
/// Idempotent. Returns 0 on success, or the first errno reported by
/// sigaction() — any handlers installed earlier in the call are rolled back
/// before returning.
+ (int)enable __attribute__((warn_unused_result));

/// Restore previously-saved handlers and clear the global pre-throw callback.
/// Idempotent.
+ (void)disable;

/// Optional pre-delivery callback. Invoked once per caught signal exception
/// before the catch block / return value runs — useful for crash logging.
/// Pass nil to clear.
///
/// Thread-safety: safe to call from any thread, but calling concurrently
/// with a signal-catch may race; set this once at startup.
+ (void)setCaughtExceptionHandler:(nullable oce_caught_exception_handler)handler;

/// Run `block`. If a monitored POSIX signal fires inside, or `block` raises
/// an NSException, returns the exception; otherwise returns nil.
///
/// Cross-language safe: the signal escape uses `siglongjmp(2)` (POSIX
/// async-signal-safe), so it works regardless of whether the call chain
/// crosses Swift / ObjC / C / C++ frames. Trade-off: on the signal-catch
/// path, C++ destructors and Swift `defer` blocks within `block` do NOT
/// run — stack-allocated cleanup is skipped. ObjC ARC `__strong` locals
/// in `block` are also leaked on the signal path.
///
/// For Objective-C / Objective-C++ callers that need C++ destructor /
/// @finally semantics, use `oce_try_catch_finally()` below instead. That
/// path uses real exception unwinding but is not Swift-safe.
+ (nullable NSException *)catching:(NS_NOESCAPE oce_block_t)block
    NS_SWIFT_NAME(catching(_:));

/// As above; `finallyBlock` runs on every exit path (success, NSException
/// catch, signal escape).
+ (nullable NSException *)catching:(NS_NOESCAPE oce_block_t)block
                          finally:(nullable NS_NOESCAPE oce_block_t)finallyBlock
    NS_SWIFT_NAME(catching(_:finally:));

@end

#ifdef __cplusplus
extern "C" {
#endif

// MARK: C API — Objective-C / Objective-C++ only
//
// These wrappers use `objc_exception_throw` and the Itanium-ABI exception
// unwinder, so C++ destructors and @finally blocks run on the unwind path.
// They are NOT safe to call from Swift on ARM64 device builds: the unwinder
// cannot reliably propagate through Swift frames there.

// `OCE_FORCE_UNWIND_TABLES` is load-bearing for code generation. It forces
// clang to emit Itanium-ABI unwind tables for the surrounding function;
// without it, dead-code elimination strips the personality routine and
// `objc_exception_throw` cannot find a landing pad.
//   - DEBUG:   `@autoreleasepool {}` is enough.
//   - RELEASE: an empty `@try {} @catch (...) {}` is required after DCE.
#if !defined(OCE_FORCE_UNWIND_TABLES)
#   if DEBUG
#       define OCE_FORCE_UNWIND_TABLES @autoreleasepool {}
#   else
#       define OCE_FORCE_UNWIND_TABLES @try {} @catch (...) {}
#   endif
#endif

FOUNDATION_EXPORT
void oce_try_catch(oce_block_t try_block,
                   oce_catch_block_t catch_block);

FOUNDATION_EXPORT
void oce_try_catch_finally(oce_block_t try_block,
                           oce_catch_block_t _Nullable catch_block,
                           oce_block_t _Nullable finally_block);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
