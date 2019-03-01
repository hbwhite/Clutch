//
//  AppDelegate.m
//  ClutchAgent
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2019 Harrison White. All rights reserved.
//
//  See LICENSE for licensing information
//

#import "AppDelegate.h"
#import "Clutch.h"

#define POLL_INTERVAL   10

@interface AppDelegate () <NSMenuDelegate>

@property (nonatomic, strong) IBOutlet NSMenu* barMenu;
@property (nonatomic, strong) IBOutlet NSMenuItem* statusItem;
@property (nonatomic, strong) IBOutlet NSMenuItem* bindAddressItem;
@property (nonatomic, strong) IBOutlet NSMenuItem* interfaceStatusItem;
@property (nonatomic, strong) NSStatusItem* barItem;
@property (nonatomic, strong) NSTimer* pollTimer;

@end

@implementation AppDelegate

- (IBAction)checkForUpdates:(id)sender {
    [self launchClutch:YES];
}

- (IBAction)openTransmission:(id)sender {
    [[NSWorkspace sharedWorkspace]launchApplication:@"Transmission"];
}

- (IBAction)openClutch:(id)sender {
    [self launchClutch:NO];
}

- (IBAction)quitClutchAgent:(id)sender {
    [NSApp terminate:nil];
}

- (void)launchClutch:(BOOL)checkForUpdates {
    // NSArray *pathComponents = [[[NSBundle mainBundle]bundlePath]pathComponents];
    // NSString *path = [NSString pathWithComponents:[pathComponents subarrayWithRange:NSMakeRange(0, pathComponents.count - 4)]];
    // [[NSWorkspace sharedWorkspace]launchApplication:path];
    
    // using a custom URL scheme so we can tell Clutch to check for updates even if it is already running
    // (a custom launch argument would only work if Clutch wasn't already running)
    if (checkForUpdates) {
        [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-transmission:checkForUpdates"]];
    } else {
        [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-transmission:"]];
    }
}

- (void)menuWillOpen:(NSMenu *)menu {
    // update menu without waiting for the timer to fire next
    [self.pollTimer fire];
}

- (void)setupBarMenu {
    // Icon by Eleonor Wang from www.flaticon.com, licensed under CC-3.0-BY
    
    NSStatusItem* barItem = [[NSStatusBar systemStatusBar]statusItemWithLength:NSSquareStatusItemLength];
    barItem.button.image = [NSImage imageNamed:@"menu-icon"];
    barItem.highlightMode = YES;
    barItem.menu = self.barMenu;
    self.barItem = barItem;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    NSLog(@"ClutchAgent init");
    
    Clutch* clutch = [[Clutch alloc]init];
    
    [self setupBarMenu];
    
    // initially set interfacePreviouslyUp to YES
    // so Clutch doesn't automatically restart Transmission
    // when it first launches, thinking the interface
    // was previously down and just went up with the same IP
    // (see comment below for why Clutch restarts Transmission
    // in this situation)
    __block BOOL interfacePreviouslyUp = YES;
    
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:POLL_INTERVAL repeats:YES block:^(NSTimer * _Nonnull timer) {
        ClutchInterface* bindInterface = [clutch getBindInterface];
        
        if (bindInterface) {
            BOOL interfaceUp = NO;
            BOOL didRebind = NO;
            
            NSArray* interfaces = [clutch getInterfaces];
            for (ClutchInterface* interface in interfaces) {
                // if the name and ipv4 status match, treat as identical
                // (don't treat interfaces with the same name but different ipv4/ipv6 statuses as identical,
                // as some VPNs or networks may not support IPv6 and could send this traffic in the clear instead
                // if an IPv6 interface is used instead of its IPv4 counterpart)
                
                if ([interface.name isEqualToString:bindInterface.name] && interface.ipv4 == bindInterface.ipv4) {
                    interfaceUp = YES;
                    
                    if (![interface.address isEqualToString:bindInterface.address]) {
                        didRebind = YES;
                        
                        NSLog(@"interface address changed, binding to new IP...\n");
                        [clutch bindToInterface:interface];
                        bindInterface = interface; // used below to update status
                    }
                    break;
                }
            }
            if (interfaceUp && !interfacePreviouslyUp && !didRebind) {
                // interface was down and just came back up, and the binding IP was the same,
                // so we didn't re-bind and Transmission wasn't restarted.
                // restart Transmission to avoid the situation below:
                
                // (if Transmission was previously bound to the interface's IP and it started before the
                // interface was up, binding to that IP would have failed, causing Transmission to not send
                // any traffic until it was restarted; Clutch restarts Transmission when it binds to a new IP
                // (hence the !didRebind check above), but if the binding IP is the same, Clutch won't
                // re-bind and restart Transmission, causing it to get stuck in the situation described above;
                // this restart fixes that situation)
                
                [clutch restartTransmission];
            }
            interfacePreviouslyUp = interfaceUp;
            
            [self.statusItem setTitle:[NSString stringWithFormat:@"Binding to %@", bindInterface.name]];
            [self.interfaceStatusItem setTitle:[NSString stringWithFormat:@"Interface Status: %@", interfaceUp ? @"Up" : @"Down"]];
        }
        else {
            self.statusItem.title = @"Not Binding";
        }
        
        [self.bindAddressItem setTitle:[NSString stringWithFormat:@"Bind Address: %@", bindInterface ? bindInterface.address : @"None"]];
    }];
    
    // if NSTimer is not added to the main run loop, it will not fire while the menu is open!
    [[NSRunLoop mainRunLoop]addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    
    // run timer action immediately on startup
    [self.pollTimer fire];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    NSLog(@"invalidating timer");
    [self.pollTimer invalidate];
}

@end
