# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this library does

`ObjCException` turns fatal POSIX signals (SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGTRAP) into catchable `NSException`s scoped to user-marked guard blocks. iOS-only CocoaPod, deployment target 12.0. **Swift, Obj-C, and Obj-C++ callers are all supported** — see the two-tier API below.

## Build / run / lint

There is no test target yet. CI (`.github/workflows/ci.yml`) runs `pod lib lint` and an Example-app build on macos-14.

```bash
# From repo root
pod lib lint --allow-warnings

# From Example/
pod install                     # regenerates Example/ObjCException.xcworkspace and Pods/
open ObjCException.xcworkspace  # build & run the demo app from Xcode

# Headless build (matches CI)
xcodebuild build \
  -workspace ObjCException.xcworkspace \
  -scheme ObjCException-Example \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

The workspace and `Pods/` are git-ignored — always run `pod install` after a fresh clone.

## Architecture

Two source files in `ObjCException/Classes/`:

### `ObjCException.h` — public surface, two-tier

**Tier 1 — `OCEException` class (Swift-safe).**
- `+[OCEException catching:]` / `+[OCEException catching:finally:]` run a block and return any caught `NSException`. Implemented via `siglongjmp(2)`, which is async-signal-safe and does not depend on stack-frame unwind metadata. **Works regardless of whether the call chain crosses Swift / ObjC / ObjC++ frames.**
- Trade-off: on the signal-catch path, C++ destructors, `@finally`, ARC `__strong` locals, and Swift `defer` blocks inside the guarded block are skipped — `siglongjmp` restores SP/FP without running landing pads.
- `+[OCEException enable]` / `+[OCEException disable]` install/restore signal handlers; `+enable` returns `int` (0 = ok, otherwise errno from the first failed `sigaction`; partial installs are rolled back).
- `+[OCEException setCaughtExceptionHandler:]` registers a global pre-delivery callback (typical use: crash logging). Set this once at startup — concurrent updates race with in-flight signal-catches.

**Tier 2 — `oce_try_catch` / `oce_try_catch_finally` C functions (ObjC / ObjC++ only).**
- Use `objc_exception_throw` and the Itanium-ABI unwinder, so C++ destructors and `@finally` run on the unwind path.
- **Cannot be called from Swift on ARM64 device builds**: the unwinder does not propagate reliably through Swift frames there.
- `OCE_FORCE_UNWIND_TABLES` macro must wrap the surrounding function in DCE-affected release builds, so clang keeps the personality routine emitted (otherwise the unwinder has no landing pad). The macro looks like dead code; it isn't.

### `ObjCException.mm` — implementation

Three pieces:

1. **Per-thread `catch_frame` stack.** A `thread_local catch_frame *g_top` points at the innermost guard frame. Each frame carries a `catch_mode` (`cpp_throw` for the C functions, `longjmp_` for the OCEException class) and — for longjmp frames — a `sigjmp_buf`. Reading `g_top` from the signal handler is async-signal-safe (initialized lazily on first push, but only `oce_*` / `OCEException catching:` paths push, so the slot is touched before any signal can ever consult it on a given thread).
2. **Async-safe signal handler** (`exception_crash_signal_handler`). Reads the top frame, picks a path:
   - `longjmp_` → store `signo`, `siglongjmp` to the catch site. Pure async-safe; NSException synthesis is deferred to the catch site. **This is the path Swift callers exercise.**
   - `cpp_throw` → synthesize an `OCESignalException`, invoke the user-supplied caught-exception callback, `objc_exception_throw`. The allocation here is technically not async-signal-safe; it works in practice because Darwin's class allocator doesn't usually hold the lock the signal interrupted. Documented; not fixable while keeping ObjC throw semantics.
   - No active frame → forward to the previously-saved sigaction.
3. **`OCESignalException`** — private `NSException` subclass that snapshots raw frame addresses via `backtrace()` (async-safe) at construction time and lazily symbolicates via `backtrace_symbols()` only when `-callStackSymbols` is first read (so the expensive call happens after the throw, in user code).

Saved sigactions live in a fixed `struct sigaction g_previous_actions[6]` with a parallel `std::atomic_bool g_active[6]` — no async-allocating list machinery.

The user-supplied caught-exception callback is stored as `std::atomic<void *>` holding a `+1`-retained block; `__bridge_retained` / `__bridge_transfer` move ARC ownership across the atomic boundary.

`g_install_mutex` (a plain `std::mutex`) serializes `+enable` / `+disable` against itself — never acquired from the signal handler.

## File conventions

- Library implementation lives in `.mm` (Objective-C++). The atomic types and RAII guards require C++.
- The header guards C-function declarations with `extern "C"` so the symbols have C linkage and are callable from `.m` and `.mm` translation units alike.
- Only `ObjCException.h` is in `s.public_header_files`.
- The Example app demonstrates every crash provenance the author tested: pure ObjC, ObjC++, and Swift, with cross-language call chains. Each row in `OCEViewController.m`'s table view is a different combination — useful as manual test fixtures when modifying the signal handler.

## Don't

- Don't add `os_unfair_lock`, `NSLog`, `malloc`, or any other async-signal-unsafe call to `exception_crash_signal_handler` or anything it transitively calls before `siglongjmp` / `objc_exception_throw`. Reads must be atomic loads or `thread_local` plain memory access; everything else must be deferred (lazy symbolication, NSException synthesis after siglongjmp returns, etc.).
- Don't expose the C functions (`oce_try_catch*`) to Swift. They will compile, but on ARM64 device the unwinder cannot propagate through Swift frames and the catch silently fails. Swift callers must use `OCEException.catching(_:)`.
- Don't strip the `OCE_FORCE_UNWIND_TABLES` macro from any function calling `oce_try_catch*`. It looks like dead code; it isn't — see the comment in the header.
- Don't take `g_install_mutex` from the signal handler — it would deadlock if a signal arrives while another thread holds it.
