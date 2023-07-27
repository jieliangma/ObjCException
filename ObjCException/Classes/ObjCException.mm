//
//  ObjCException.m
//  ObjCException
//
//  Created by JieLiang Ma on 2023/7/26.
//

#import "ObjCException.h"
#import "try_block_count.h"
#import "async_linked_list.hpp"

#import <objc/objc-exception.h>

using namespace cpp;

@implementation ObjCException

@end

struct plcrash_signal_handler_action {
    /** Signal type. */
    int signo;
    
    /** Signal handler action. */
    struct sigaction action;
};

static oce_caught_exception_handler global_exception_handler = NULL;
static async_list<plcrash_signal_handler_action> *previous_actions = NULL;
static os_unfair_lock global_lock = OS_UNFAIR_LOCK_INIT;


@interface SignalException : NSException
@property (nonatomic, strong) NSArray<NSString *> *stackSymbols;
- (instancetype)initWithSignal:(int)signal;
@end

oce_caught_exception_handler
oce_set_caught_exception_handler(oce_caught_exception_handler _Nullable handler) {
    oce_caught_exception_handler result;
    
    os_unfair_lock_lock(&global_lock); {
        result = global_exception_handler;
        global_exception_handler = handler;
    } os_unfair_lock_unlock(&global_lock);
    
    return result;
}

NS_INLINE
void invoke_try_block(oce_block_t try_block) {
    // 包裹一下 try_block, 避免 try_block 内的崩溃影响信号处理。
    void (^block_wrapper)(void) = ^{ try_block(); };
    block_wrapper();
}

void oce_try(oce_block_t try_block) {
    increase_try_block_count();
    try {
        invoke_try_block(try_block);
        decrease_try_block_count();
    } catch (id obj) {
        decrease_try_block_count();
        throw obj;
    }
}

void oce_try_catch(oce_block_t try_block,
                  oce_catch_block_t catch_block)
{
    try {
        increase_try_block_count();
        invoke_try_block(try_block);
        decrease_try_block_count();
    } catch (NSException *exception) {
        decrease_try_block_count();
        catch_block(exception);
    }
}

void oce_try_catch_finally(oce_block_t try_block,
                          oce_catch_block_t _Nullable catch_block,
                          oce_block_t _Nullable finally_block)
{
    @try {
        increase_try_block_count();
        invoke_try_block(try_block);
        decrease_try_block_count();
    } @catch (NSException *exception) {
        decrease_try_block_count();
        if (catch_block) {
            catch_block(exception);
        } else {
            @throw exception;
        }
    } @finally {
        if (finally_block) {
            finally_block();
        }
    }
}

void exception_crash_signal_handler(int signo, siginfo_t *info, void *uap) {
    int count;
    bool handled;
    sigset_t set, oset;
    
    count = get_try_block_count();
    
    if (count > 0) {
        SignalException *exception = [[SignalException alloc] initWithSignal:signo];
        
        exception.stackSymbols = [NSThread callStackSymbols];
        
        sigemptyset(&set);
        sigprocmask(SIG_SETMASK, &set, &oset);
        
        oce_caught_exception_handler caught_exception_handler;
        
        os_unfair_lock_lock(&global_lock); {
            caught_exception_handler = global_exception_handler;
        } os_unfair_lock_unlock(&global_lock);
        
        if (caught_exception_handler != NULL) {
            caught_exception_handler(exception);
        }
        
        objc_exception_throw(exception);
    }
    
    handled = false;
    
    previous_actions->set_reading(true); {
        /* Find the first matching handler */
        async_list<plcrash_signal_handler_action>::node *next = NULL;
        while ((next = previous_actions->next(next)) != NULL) {
            /* Skip non-matching entries */
            if (next->value().signo != signo)
                continue;
            
            /* Found a match */
            // TODO - Should we handle the other flags, eg, SA_RESETHAND, SA_ONSTACK? */
            if (next->value().action.sa_flags & SA_SIGINFO) {
                next->value().action.sa_sigaction(signo, info, uap);
                NSLog(@"%s:%d", __FUNCTION__, __LINE__);
                handled = true;
            } else {
                void (*next_handler)(int) = next->value().action.sa_handler;
                if (next_handler == SIG_IGN) {
                    /* Ignored */
                    NSLog(@"%s:%d", __FUNCTION__, __LINE__);
                    handled = true;
                } else if (next_handler == SIG_DFL) {
                    /* Default handler should be run, be we have no mechanism to pass through to
                     * the default handler; mark the signal as unhandled. */
                    handled = false;
                    NSLog(@"%s:%d signal(%d) match default handler", __FUNCTION__, __LINE__, signo);
                    signal(signo, SIG_DFL);
                } else {
                    /* Handler registered, execute it */
                    NSLog(@"%s:%d", __FUNCTION__, __LINE__);
                    next_handler(signo);
                    handled = true;
                }
            }
            
            /* Handler was found; iteration done */
            break;
        }
    } previous_actions->set_reading(false);
    
    if (!handled) {
        NSLog(@"%s:%d signal(%d) unhandled", __FUNCTION__, __LINE__, signo);
        raise(signo);
    }
}

static int register_signals(int signo) {
    struct sigaction sa;
    struct sigaction sa_prev;

    /* Configure action */
    memset(&sa, 0, sizeof(sa));
    sa.sa_flags = SA_SIGINFO|SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    sa.sa_sigaction = &exception_crash_signal_handler;

    /* Set new sigaction */
    if (sigaction(signo, &sa, &sa_prev) != 0) {
        return errno;
    }
    
    /* Save the previous action. Note that there's an inescapable race condition here, such that
     * we may not call the previous signal handler if signal occurs prior to our saving
     * the caller's handler.
     *
     * TODO - Investigate use of async-safe locking to avoid this condition. See also:
     * The PLCrashReporter class's enabling of Mach exceptions.
     */
    plcrash_signal_handler_action act = {
        .signo = signo,
        .action = sa_prev
    };
    previous_actions->nasync_append(act);
    return 0;
}

static int unregister_signals(int signo) {
    async_list<plcrash_signal_handler_action>::node *sig_node = NULL;
    
    previous_actions->set_reading(true); {
        /* Find the first matching handler */
        async_list<plcrash_signal_handler_action>::node *next = NULL;
        while ((next = previous_actions->next(next)) != NULL) {
            /* Skip non-matching entries */
            if (next->value().signo != signo)
                continue;
            
            sig_node = next;
            
            /* Handler was found; iteration done */
            break;
        }
    } previous_actions->set_reading(false);

    if (sig_node != NULL) {
        plcrash_signal_handler_action act = sig_node->value();
        
        if (sigaction(signo, &act.action, NULL) != 0) {
            return errno;
        }
        
        previous_actions->nasync_remove_node(sig_node);
    }
    
    return 0;
}

//__attribute__((constructor))
void oce_enable_objc_exception(void) {
    /**
     * hook signal() and sig_action()
     */
    int monitored_signals[] = {
        SIGABRT,
        SIGBUS,
        SIGFPE,
        SIGILL,
        SIGSEGV,
        SIGTRAP
    };
    int monitored_signals_count = (sizeof(monitored_signals) / sizeof(monitored_signals[0]));
    
    os_unfair_lock_lock(&global_lock); {
        if (previous_actions != NULL) {
            os_unfair_lock_unlock(&global_lock);
            return;
        }
        
        previous_actions = new async_list<plcrash_signal_handler_action>();
        
        if (previous_actions == NULL) {
            return;
        }
        
        for (int i = 0; i < monitored_signals_count; i++) {
            if (register_signals(monitored_signals[i]) != 0) {
                NSLog(@"error(%d):%s", monitored_signals[i], strerror(errno));
            }
        }
    } os_unfair_lock_unlock(&global_lock);
}

//__attribute__((destructor))
void oce_disable_objc_exception(void)
{
    /**
     * hook signal() and sig_action()
     */
    int monitored_signals[] = {
        SIGABRT,
        SIGBUS,
        SIGFPE,
        SIGILL,
        SIGSEGV,
        SIGTRAP
    };
    int monitored_signals_count = (sizeof(monitored_signals) / sizeof(monitored_signals[0]));
    
    os_unfair_lock_lock(&global_lock); {
        if (previous_actions == NULL) {
            os_unfair_lock_unlock(&global_lock);
            return;
        }
        
        for (int i = 0; i < monitored_signals_count; i++) {
            if (unregister_signals(monitored_signals[i]) != 0) {
                NSLog(@"error(%d):%s", monitored_signals[i], strerror(errno));
            }
        }
        
        delete previous_actions;
        previous_actions = NULL;
    } os_unfair_lock_unlock(&global_lock);
}

@implementation SignalException

- (instancetype)initWithSignal:(int)signal {
    NSExceptionName name;
    NSString *reason = @"Exception raised by signal handler.";
    
    switch (signal) {
        case SIGABRT: name = @"SIGABRT"; break;
        case SIGBUS: name = @"SIGBUS"; break;
        case SIGFPE: name = @"SIGFPE"; break;
        case SIGILL: name = @"SIGILL"; break;
        case SIGSEGV: name = @"SIGSEGV"; break;
        case SIGTRAP: name = @"SIGTRAP"; break;
        default: name = [@(signal) stringValue]; break;
    }
    return [super initWithName:name reason:reason userInfo:nil];
}

- (NSArray<NSString *> *)callStackSymbols {
    NSArray<NSString *> *stackSymbols = self.stackSymbols;
    
    return stackSymbols;
}

@end
