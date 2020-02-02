//
//  PermissionsViewController.m
//  Clutch
//
//  Created by Harrison White on 2/1/20.
//  Copyright © 2020 Harrison White. All rights reserved.
//  
//  See LICENSE for licensing information
//

#import "PermissionsViewController.h"
#import "Constants.h"

@interface PermissionsViewController ()

@end

@implementation PermissionsViewController

- (IBAction)openAutomationSettings:(id)sender {
    [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"]];
}

- (IBAction)openAccessibilitySettings:(id)sender {
    [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (IBAction)dismiss:(id)sender {
    [[NSNotificationCenter defaultCenter]postNotificationName:kUserFinishedPermissionsVCNotificationName object:nil];
    [self dismissController:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

@end
