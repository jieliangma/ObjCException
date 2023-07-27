//
//  OCECppCallSwift.mm
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

#import "OCECppCallSwift.h"
#import <UIKit/UIKit.h>
#import "ObjCException_Example-Swift.h"

@implementation OCECppCallSwift

+ (void)crash {
    [OCESwiftCrash crash];
}

@end
