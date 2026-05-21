//
//  ObjCException.mm
//  ObjCException
//
//  Created by JieLiang Ma on 2023/7/26.
//

#import "ObjCException.h"

#import <objc/objc-exception.h>

#include <atomic>
#include <errno.h>
#include <execinfo.h>
#include <mutex>
#include <setjmp.h>
#include <signal.h>

namespace {

constexpr int kMonitoredSignals[] = {
    SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP,
};
constexpr size_t kNumMonitoredSignals =
    sizeof(kMonitoredSignals) / sizeof(kMonitoredSignals[0]);
constexpr int kMaxBacktraceFrames = 128;

// Signal handler picks an action based on the top of this stack.
//   cpp_throw: synthesize an NSException and `objc_exception_throw` —
//              gives ObjC/C++ callers proper unwinding (destructors,
//              @finally) but cannot reliably traverse Swift frames on
//              ARM64 device builds.
//   longjmp_:  call `siglongjmp` — async-signal-safe, language-agnostic,
//              but skips C++ destructors / @finally.
enum class catch_mode : int {
    cpp_throw = 0,
    longjmp_  = 1,
};

struct catch_frame {
    catch_frame *prev;
    catch_mode   mode;
    int          signo;     // captured by the signal handler before longjmp
    sigjmp_buf   jmp_buf;   // valid only when mode == longjmp_
};

// Per-thread top of the catch_frame stack. Reading a thread_local pointer
// is async-signal-safe (no implicit malloc once the slot is initialized,
// and the slot is initialized eagerly the first time a frame is pushed).
thread_local catch_frame *g_top = nullptr;

// Saved previous sigactions. `g_active[i]` becomes true only after
// `g_previous_actions[i]` is fully populated, so the signal handler can
// read either field with acquire semantics and no lock.
struct sigaction g_previous_actions[kNumMonitoredSignals];
std::atomic_bool g_active[kNumMonitoredSignals];

// Atomically-swappable +1-retained ObjC block pointer. Stored as `void *`
// because std::atomic does not accept ObjC types directly.
std::atomic<void *> g_exception_handler{nullptr};

std::atomic_bool g_enabled{false};

// Serializes enable/disable iteration against itself. Cannot be acquired
// from the signal handler — handler reads only atomics.
std::mutex g_install_mutex;

int find_signal_index(int signo) noexcept {
    for (size_t i = 0; i < kNumMonitoredSignals; ++i) {
        if (kMonitoredSignals[i] == signo) return static_cast<int>(i);
    }
    return -1;
}

void invoke_caught_handler(NSException *exception) {
    void *raw = g_exception_handler.load(std::memory_order_acquire);
    if (raw == nullptr) return;
    oce_caught_exception_handler handler =
        (__bridge oce_caught_exception_handler)raw;
    handler(exception);
}

}  // namespace

#pragma mark - SignalException

@interface OCESignalException : NSException
- (instancetype)initWithSignal:(int)signal;
@end

@implementation OCESignalException {
    void *_frames[kMaxBacktraceFrames];
    int _frameCount;
    NSArray<NSString *> *_cachedSymbols;
}

- (instancetype)initWithSignal:(int)signal {
    NSExceptionName name;
    switch (signal) {
        case SIGABRT: name = @"SIGABRT"; break;
        case SIGBUS:  name = @"SIGBUS";  break;
        case SIGFPE:  name = @"SIGFPE";  break;
        case SIGILL:  name = @"SIGILL";  break;
        case SIGSEGV: name = @"SIGSEGV"; break;
        case SIGTRAP: name = @"SIGTRAP"; break;
        default:      name = [@(signal) stringValue]; break;
    }
    self = [super initWithName:name
                        reason:@"Exception raised by signal handler."
                      userInfo:nil];
    if (self) {
        // backtrace() is async-signal-safe on Darwin; backtrace_symbols()
        // is not, so symbolication is deferred to -callStackSymbols.
        _frameCount = backtrace(_frames, kMaxBacktraceFrames);
    }
    return self;
}

- (NSArray<NSString *> *)callStackSymbols {
    if (_cachedSymbols) return _cachedSymbols;
    if (_frameCount <= 0) {
        _cachedSymbols = @[];
        return _cachedSymbols;
    }
    char **strs = backtrace_symbols(_frames, _frameCount);
    if (!strs) {
        _cachedSymbols = @[];
        return _cachedSymbols;
    }
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:_frameCount];
    for (int i = 0; i < _frameCount; ++i) {
        const char *s = strs[i] ? strs[i] : "";
        [out addObject:[NSString stringWithUTF8String:s]];
    }
    free(strs);
    _cachedSymbols = [out copy];
    return _cachedSymbols;
}

@end

#pragma mark - Signal handler

namespace {

void forward_to_previous(int signo, siginfo_t *info, void *uap) {
    int idx = find_signal_index(signo);
    if (idx < 0 || !g_active[idx].load(std::memory_order_acquire)) {
        // Inconsistent state (signal we don't track, or we've been
        // disabled mid-flight). Fall back to OS default — terminate.
        signal(signo, SIG_DFL);
        raise(signo);
        return;
    }
    const struct sigaction &prev = g_previous_actions[idx];
    if (prev.sa_flags & SA_SIGINFO) {
        if (prev.sa_sigaction) {
            prev.sa_sigaction(signo, info, uap);
            return;
        }
    } else if (prev.sa_handler == SIG_IGN) {
        return;
    } else if (prev.sa_handler && prev.sa_handler != SIG_DFL) {
        prev.sa_handler(signo);
        return;
    }
    signal(signo, SIG_DFL);
    raise(signo);
}

void exception_crash_signal_handler(int signo, siginfo_t *info, void *uap) {
    catch_frame *top = g_top;
    if (top != nullptr) {
        if (top->mode == catch_mode::longjmp_) {
            // Pure async-safe path: stash the signal and unwind via
            // siglongjmp. NSException synthesis happens in the catch
            // site, after the handler has returned.
            top->signo = signo;
            siglongjmp(top->jmp_buf, 1);
            __builtin_unreachable();
        }

        // cpp_throw mode: synthesize NSException and throw. Allocating
        // an ObjC object here is technically not async-signal-safe — it
        // only works because Darwin's class allocator does not commonly
        // hold a lock the signal interrupted. Document, don't fix.
        sigset_t set;
        sigemptyset(&set);
        sigprocmask(SIG_SETMASK, &set, nullptr);

        OCESignalException *exception =
            [[OCESignalException alloc] initWithSignal:signo];
        invoke_caught_handler(exception);
        objc_exception_throw(exception);
        __builtin_unreachable();
    }

    forward_to_previous(signo, info, uap);
}

int register_signal(size_t idx) {
    int signo = kMonitoredSignals[idx];
    struct sigaction sa{};
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sa.sa_sigaction = &exception_crash_signal_handler;

    struct sigaction prev{};
    if (sigaction(signo, &sa, &prev) != 0) {
        return errno;
    }
    g_previous_actions[idx] = prev;
    g_active[idx].store(true, std::memory_order_release);
    return 0;
}

int unregister_signal(size_t idx) {
    if (!g_active[idx].load(std::memory_order_acquire)) return 0;
    int signo = kMonitoredSignals[idx];
    // Restore OS-level handler first; once that returns, no new signals
    // will be delivered to our handler. Then flip the flag so any handler
    // already in flight on another thread sees the inactive state and
    // falls into the forward-default path.
    if (sigaction(signo, &g_previous_actions[idx], nullptr) != 0) {
        return errno;
    }
    g_active[idx].store(false, std::memory_order_release);
    return 0;
}

int install_all_signals() {
    for (size_t i = 0; i < kNumMonitoredSignals; ++i) {
        int err = register_signal(i);
        if (err != 0) {
            for (size_t j = 0; j < i; ++j) unregister_signal(j);
            return err;
        }
    }
    return 0;
}

void uninstall_all_signals() {
    for (size_t i = 0; i < kNumMonitoredSignals; ++i) unregister_signal(i);
}

}  // namespace

#pragma mark - C API (cpp_throw mode — ObjC / ObjC++ only)

namespace {

// RAII guard for cpp_throw frames. Pushes/pops in c-tor/d-tor so the
// thread-local stack stays balanced under any unwind path.
struct cpp_throw_guard {
    catch_frame frame{};
    cpp_throw_guard() noexcept {
        frame.prev = g_top;
        frame.mode = catch_mode::cpp_throw;
        g_top = &frame;
    }
    ~cpp_throw_guard() noexcept { g_top = frame.prev; }
    cpp_throw_guard(const cpp_throw_guard &) = delete;
    cpp_throw_guard &operator=(const cpp_throw_guard &) = delete;
};

// RAII finally runner. Swallows any secondary exception thrown by the
// finally block to keep the destructor noexcept (otherwise an exception
// during stack unwinding would call std::terminate).
struct finally_runner {
    oce_block_t block;
    explicit finally_runner(oce_block_t b) noexcept : block(b) {}
    ~finally_runner() noexcept {
        if (!block) return;
        @try { block(); } @catch (...) {}
    }
    finally_runner(const finally_runner &) = delete;
    finally_runner &operator=(const finally_runner &) = delete;
};

}  // namespace

void oce_try_catch_impl(oce_block_t try_block, oce_catch_block_t catch_block) {
    cpp_throw_guard _g;
    @try {
        try_block();
    } @catch (NSException *exception) {
        catch_block(exception);
    }
}

void oce_try_catch_finally_impl(oce_block_t try_block,
                                oce_catch_block_t _Nullable catch_block,
                                oce_block_t _Nullable finally_block) {
    cpp_throw_guard _g;
    finally_runner _f(finally_block);
    @try {
        try_block();
    } @catch (NSException *exception) {
        if (catch_block) {
            catch_block(exception);
        } else {
            @throw;
        }
    }
}

#pragma mark - OCEException class (longjmp mode — Swift-safe)

@implementation OCEException

+ (int)enable {
    std::lock_guard<std::mutex> lock(g_install_mutex);
    if (g_enabled.load(std::memory_order_acquire)) return 0;

    int err = install_all_signals();
    if (err != 0) return err;

    g_enabled.store(true, std::memory_order_release);
    return 0;
}

+ (void)disable {
    std::lock_guard<std::mutex> lock(g_install_mutex);
    if (!g_enabled.load(std::memory_order_acquire)) return;

    uninstall_all_signals();
    g_enabled.store(false, std::memory_order_release);

    // Release the user-installed handler block, if any. Setting to nullptr
    // before the ARC-bridged release narrows but does not eliminate the
    // window during which a concurrent signal-catch on another thread
    // could be invoking the block — see header note about calling
    // setCaughtExceptionHandler at startup only.
    void *prior = g_exception_handler.exchange(nullptr,
                                               std::memory_order_acq_rel);
    if (prior) {
        oce_caught_exception_handler released =
            (__bridge_transfer oce_caught_exception_handler)prior;
        (void)released;
    }
}

+ (void)setCaughtExceptionHandler:(oce_caught_exception_handler)handler {
    void *new_raw = nullptr;
    if (handler) {
        // [handler copy] moves a stack block to the heap; __bridge_retained
        // hands ARC's +1 retain over to the raw pointer for atomic storage.
        oce_caught_exception_handler copied = [handler copy];
        new_raw = (__bridge_retained void *)copied;
    }
    void *old_raw = g_exception_handler.exchange(new_raw,
                                                 std::memory_order_acq_rel);
    if (old_raw) {
        oce_caught_exception_handler released =
            (__bridge_transfer oce_caught_exception_handler)old_raw;
        (void)released;
    }
}

+ (NSException *)catching:(NS_NOESCAPE oce_block_t)block {
    return [self catching:block finally:nil];
}

+ (NSException *)catching:(NS_NOESCAPE oce_block_t)block
                  finally:(nullable NS_NOESCAPE oce_block_t)finallyBlock {
    catch_frame frame{};
    frame.prev = g_top;
    frame.mode = catch_mode::longjmp_;
    frame.signo = 0;

    NSException *captured = nil;

    if (sigsetjmp(frame.jmp_buf, 1) == 0) {
        g_top = &frame;
        @try {
            block();
        } @catch (NSException *e) {
            captured = e;
        }
        g_top = frame.prev;
    } else {
        // siglongjmp escape from the signal handler. The frame still
        // points at us; pop it before doing anything that could re-enter.
        g_top = frame.prev;
        captured = [[OCESignalException alloc] initWithSignal:frame.signo];
        invoke_caught_handler(captured);
    }

    if (finallyBlock) {
        @try { finallyBlock(); } @catch (...) {}
    }

    return captured;
}

@end
