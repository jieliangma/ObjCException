//
//  ObjCException.h
//  ObjCException
//
//  Created by JieLiang Ma on 2023/7/26.
//

#import <Foundation/Foundation.h>

#if !defined(at_keyword)
#   if DEBUG
#       define at_keyword autoreleasepool {}
#   else
#       define at_keyword try {} @catch (...) {}
#   endif
#endif


#define ctry(...) at_keyword @try { oe_try(^__VA_ARGS__); }

NS_ASSUME_NONNULL_BEGIN

typedef void (^oce_caught_exception_handler)(NSException *exception);
typedef void (^oce_block_t)(void);
typedef void (^oce_catch_block_t)(NSException *exception);

@interface ObjCException : NSObject

@end

FOUNDATION_EXPORT oce_caught_exception_handler
oce_set_caught_exception_handler(oce_caught_exception_handler _Nullable handler);

FOUNDATION_EXPORT
void oce_enable_objc_exception(void);
FOUNDATION_EXPORT
void oce_disable_objc_exception(void);

FOUNDATION_EXPORT
void oce_try(oce_block_t try_block);
FOUNDATION_EXPORT
void oce_try_catch(oce_block_t try_block,
                   oce_catch_block_t catch_block);
FOUNDATION_EXPORT
void oce_try_catch_finally(oce_block_t try_block,
                           oce_catch_block_t _Nullable catch_block,
                           oce_block_t _Nullable finally_block);

NS_ASSUME_NONNULL_END
