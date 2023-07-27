//
//  OCECCrash.m
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/11.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

#import "OCECCrash.h"

@import ObjCException;

@implementation OCECCrash

+ (void)crash {
    oce_try_catch(^{
        __builtin_trap();
    }, ^(NSException * _Nonnull exception) {
        NSLog(@"saved my life. (%@)", exception.name);
    });
}

@end
