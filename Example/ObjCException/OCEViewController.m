//
//  OCEViewController.m
//  ObjCException
//
//  Created by JieLiang Ma on 07/25/2023.
//  Copyright (c) 2023 JieLiang Ma. All rights reserved.
//

#import "OCEViewController.h"
#import "OCECViewController.h"
#import "OCECppViewController.h"
#import "ObjCException_Example-Swift.h"

@interface OCEViewController () <UITableViewDataSource, UITableViewDelegate>

@end

@implementation OCEViewController

- (void)viewDidLoad {
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.frame];
    tableView.allowsMultipleSelection = NO;
    tableView.tableFooterView = [UIView alloc];
    tableView.dataSource = self;
    tableView.delegate = self;
    [self.view addSubview:tableView];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return 3;
        case 1:
            return 2;
        default:
            return 4;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return @"Objective-C crash";
        case 1:
            return @"Objective-Cpp crash";
        default:
            return @"Swift crash";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] init];
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Objective-C";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Swift -> Objective-C";
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Objective-C -> Swift -> Objective-C";
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Objective-Cpp";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Swift -> Objective-Cpp";
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Swift";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Objective-C -> Swift";
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Objective-Cpp -> Swift";
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Swift-> Objective-C -> Swift";
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UIViewController *viewController;
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            // Objective-C
            viewController = [[OCECViewController alloc] initWithCrashType:OCCrashTypeOC];
        } else if (indexPath.row == 1) {
            // Swift -> Objective-C
            viewController = [[OCECViewController alloc] initWithCrashType:OCCrashTypeSwift2OC];
        } else {
            // Objective-C -> Swift -> Objective-C
            viewController = [[OCECViewController alloc] initWithCrashType:OCCrashTypeOC2Swift2OC];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            // Objective-Cpp
            viewController = [[OCECppViewController alloc] initWithCrashType:CPPCrashTypeCPP];
        } else {
            // Swift -> Objective-Cpp
            viewController = [[OCECppViewController alloc] initWithCrashType:CPPCrashTypeSwift2CPP];
        }
    } else {
        if (indexPath.row == 0) {
            // Swift
            viewController = [[SwiftCrashViewController alloc] initWithCrashType:SwiftCrashTypeSwift];
        } else if (indexPath.row == 1) {
            // Objective-C -> Swift
            viewController = [[SwiftCrashViewController alloc] initWithCrashType:SwiftCrashTypeOc2Swift];
        } else if (indexPath.row == 2) {
            // Objective-Cpp -> Swift
            viewController = [[SwiftCrashViewController alloc] initWithCrashType:SwiftCrashTypeCpp2Swift];
        } else if (indexPath.row == 3) {
            // Swift-> Objective-C -> Swift
            viewController = [[SwiftCrashViewController alloc] initWithCrashType:SwiftCrashTypeSwift2OC2Swift];
        }
    }
    
    [self.navigationController pushViewController:viewController animated:YES];
}

@end
