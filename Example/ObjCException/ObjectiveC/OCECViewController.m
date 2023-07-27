//
//  OCECViewController.m
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

#import "OCECViewController.h"
#import "ObjCException_Example-Swift.h"

@import ObjCException;

@interface OCECViewController ()
@property (nonatomic, assign) OCCrashType crashType;
@end

@implementation OCECViewController

- (instancetype)initWithCrashType:(OCCrashType)crashType {
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.crashType = crashType;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Objective-C crash";
    self.view.backgroundColor = UIColor.whiteColor;
    
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(100, 200, 100, 50)];
    [button setTitle:@"Crash" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [button setTitleColor:UIColor.grayColor forState:UIControlStateHighlighted];
    [self.view addSubview:button];
    [button addTarget:self action:@selector(buttonAction) forControlEvents:UIControlEventTouchUpInside];
}

- (void)buttonAction {
    switch (self.crashType) {
        case OCCrashTypeOC:
            [self OCCrash];
            break;
        case OCCrashTypeSwift2OC:
            [self Swift2OCCrash];
            break;
        case OCCrashTypeOC2Swift2OC:
            [self OC2Swift2OCCrash];
            break;
    }
    
}

- (void)OCCrash {
    oce_try_catch(^{
        ((char *)0)[0] = 0;
    }, ^(NSException *exception) {
        NSLog(@"saved my life. (%@)", exception.name);
    });
}

- (void)Swift2OCCrash {
    [OCECSwiftCrash crashWithImmediately:NO];
}

- (void)OC2Swift2OCCrash {
    [OCECSwiftCrash crashWithImmediately:YES];
}

@end
