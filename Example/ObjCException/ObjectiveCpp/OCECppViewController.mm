//
//  OCECppViewController.m
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

#import "OCECppViewController.h"
#import <ObjCException/ObjCException.h>
#import "OCECppCrash.h"
#import "ObjCException_Example-Swift.h"

@interface OCECppViewController ()
@property (nonatomic, assign) CPPCrashType crashType;
@end

@implementation OCECppViewController

- (instancetype)initWithCrashType:(CPPCrashType)crashType {
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.crashType = crashType;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Objective-Cpp crash";
    self.view.backgroundColor = UIColor.whiteColor;

    UIButton *buttonOne = [[UIButton alloc] initWithFrame:CGRectMake(100, 200, 100, 50)];
    [buttonOne setTitle:@"Crash One" forState:UIControlStateNormal];
    [buttonOne setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [buttonOne setTitleColor:UIColor.grayColor forState:UIControlStateHighlighted];
    [self.view addSubview:buttonOne];
    [buttonOne addTarget:self action:@selector(buttonOneAction) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *buttonTwo = [[UIButton alloc] initWithFrame:CGRectMake(100, 300, 100, 50)];
    [buttonTwo setTitle:@"Crash Two" forState:UIControlStateNormal];
    [buttonTwo setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [buttonTwo setTitleColor:UIColor.grayColor forState:UIControlStateHighlighted];
    [self.view addSubview:buttonTwo];
    [buttonTwo addTarget:self action:@selector(buttonTwoAction) forControlEvents:UIControlEventTouchUpInside];
}

- (void)buttonOneAction {
    switch (self.crashType) {
        case CPPCrashTypeCPP:
            cpp_crash();
            break;
        case CPPCrashTypeSwift2CPP:
            [OCECppSwiftCrash crash];
            break;
    }
}

- (void)buttonTwoAction {
    switch (self.crashType) {
        case CPPCrashTypeCPP:
            cpp_crash_deeper();
            break;
        case CPPCrashTypeSwift2CPP:
            [OCECppSwiftCrash crashDeeper];
            break;
    }
}

@end
