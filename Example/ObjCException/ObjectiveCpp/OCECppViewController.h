//
//  OCECppViewController.h
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, CPPCrashType) {
    CPPCrashTypeCPP,
    CPPCrashTypeSwift2CPP,
};

NS_ASSUME_NONNULL_BEGIN

@interface OCECppViewController : UIViewController
- (instancetype)initWithCrashType:(CPPCrashType)crashType;
@end

NS_ASSUME_NONNULL_END
