//
//  OCECViewController.h
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, OCCrashType) {
    OCCrashTypeOC,
    OCCrashTypeSwift2OC,
    OCCrashTypeOC2Swift2OC,
};

NS_ASSUME_NONNULL_BEGIN

@interface OCECViewController : UIViewController

- (instancetype)initWithCrashType:(OCCrashType)crashType;

@end

NS_ASSUME_NONNULL_END
