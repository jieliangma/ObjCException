Pod::Spec.new do |s|
  s.name             = 'ObjCException'
  s.version          = '0.2.0'
  s.summary          = 'Catchable POSIX-signal exceptions for iOS — Swift, ObjC, and ObjC++.'
  s.description      = <<-DESC
ObjCException turns fatal POSIX signals (SIGSEGV, SIGABRT, SIGBUS, SIGFPE,
SIGILL, SIGTRAP) into catchable NSExceptions inside user-marked guard blocks.
Useful for guarding code paths that can crash but shouldn't take the process
down — plugin sandboxes, scripted hot-paths, recoverable parsers.

Two-tier API:
  - `OCEException.catching(_:)` — siglongjmp-based; safe across Swift / ObjC
    / C++ frames; does not run C++ destructors or @finally on the signal-
    catch path.
  - `oce_try_catch_finally()` C function — `objc_exception_throw`-based;
    preserves C++ destructors and @finally; ObjC / ObjC++ callers only.
                       DESC

  s.homepage         = 'https://github.com/jieliangma/ObjCException'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'JieLiang Ma' => 'majieliang@didiglobal.com' }
  s.source           = { :git => 'https://github.com/jieliangma/ObjCException.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.source_files = 'ObjCException/Classes/**/*.{h,hpp,m,mm}'
  s.public_header_files = 'ObjCException/Classes/ObjCException.h'
end
