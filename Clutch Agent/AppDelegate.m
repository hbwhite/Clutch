//
//  AppDelegate.m
//  Clutch Agent
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2020 Harrison White. All rights reserved.
//
//  See LICENSE for licensing information
//

#import "AppDelegate.h"
#import "Clutch.h"
#import "GracefulQuit.h"

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

// custom getter so self.clutch automatically calls [Clutch sharedInstance]
// (self.clutch is less cumbersome to write)
- (Clutch *)clutch {
    return [Clutch sharedInstance];
}

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
    
    [self setupBarMenu];
    
    // initially set interfacePreviouslyUp to YES
    // so Clutch doesn't automatically restart Transmission
    // when it first launches, thinking the interface
    // was previously down and just went up with the same IP
    // (see comment below for why Clutch restarts Transmission
    // in this situation)
    __block BOOL interfacePreviouslyUp = YES;
    
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:POLL_INTERVAL repeats:YES block:^(NSTimer * _Nonnull timer) {
        
        ClutchInterface* bindInterface = [self.clutch getBindInterface];
        
        if (bindInterface) {
            BOOL interfaceUp = NO;
            BOOL didRebind = NO;
            
            NSArray* interfaces = [self.clutch getInterfaces];
            for (ClutchInterface* interface in interfaces) {
                // if the name and ipv4 status match, treat as identical
                // (don't treat interfaces with the same name but different ipv4/ipv6 statuses as identical,
                // as some VPNs or networks may not support IPv6 and could send this traffic in the clear instead
                // if an IPv6 interface is used instead of its IPv4 counterpart)
                
                NSRange regexMatchRange = [interface.name rangeOfString:bindInterface.name options:NSRegularExpressionSearch];
                // NSLog(@"clutch agent comparing range %@ to %@", NSStringFromRange(regexMatchRange), NSStringFromRange(NSMakeRange(0, interface.name.length)));
                if (regexMatchRange.location == 0 &&
                    regexMatchRange.length == interface.name.length &&
                    interface.ipv4 == bindInterface.ipv4) {
                    
                    interfaceUp = YES;
                    
                    if (![interface.address isEqualToString:bindInterface.address]) {
                        didRebind = YES;
                        
                        NSLog(@"interface address changed, binding to new IP...\n");
                        
                        // regex matched whole interface name; use this interface
                        ClutchInterface* bindInterfaceNew = [[ClutchInterface alloc]init];
                        
                        // set bind interface name to provided regex
                        bindInterfaceNew.name = bindInterface.name;
                        
                        // copy other values from matching ClutchInterface object
                        bindInterfaceNew.address = interface.address;
                        bindInterfaceNew.ipv4 = interface.ipv4;
                        
                        [self.clutch bindToInterface:bindInterfaceNew];
                        
                        // it seems apps can't be launched while the bar menu is open,
                        // so even though force-quit may work, the relaunch will not until the menu is closed;
                        // for this reason, close the menu in all cases here
                        
                        // dismisses the menu if it was open
                        [self.barItem.menu cancelTracking];
                        
                        // if the user hasn't set Clutch to restart Transmission gracefully, continue to use force-quit
                        // to keep Clutch's behavior consistent
                        [GracefulQuit restartTransmissionGracefully:[self.clutch shouldRestartGracefully] withCallback:nil];
                        
                        bindInterface = bindInterfaceNew; // used below to update status
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
                
                // if the user hasn't set Clutch to restart Transmission gracefully, continue to use force-quit
                // to keep Clutch's behavior consistent
                [GracefulQuit restartTransmissionGracefully:[self.clutch shouldRestartGracefully] withCallback:nil];
            }
            interfacePreviouslyUp = interfaceUp;
            
            [self.statusItem setTitle:[NSString stringWithFormat:@"Binding to %@", bindInterface.name]];
            [self.interfaceStatusItem setTitle:[NSString stringWithFormat:@"Interface Status: %@", interfaceUp ? @"Up" : @"Down"]];
        }
        else {
            self.statusItem.title = @"Not Binding";
            [self.interfaceStatusItem setTitle:@"Interface Status: n/a"];
        }
        
        [self.bindAddressItem setTitle:[NSString stringWithFormat:@"Bind Address: %@", bindInterface ? bindInterface.address : @"None"]];
    }];
    
    // if NSTimer is not added to the main run loop, it will not fire while the menu is open!
    [[NSRunLoop mainRunLoop]addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    
    // run timer action immediately on startup
    [self.pollTimer fire];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL* url in urls) {
        if ([[url scheme]isEqualToString:@"clutch-agent-transmission"]) {
            // the only time this happens is when Clutch is asking Clutch Agent to quit Transmission.
            // this is handled by Clutch Agent only because the user has to grant permissions
            // for Clutch Agent to be able to quit Transmission gracefully, and if both Clutch and
            // Clutch Agent quit Transmission on their own, the user would have to grant permissions
            // to two separate apps; this way, they only have to grant permissions to Clutch Agent.
            
            NSLog(@"inside clutch-agent-transmission: URL handler");
            
            NSString* resource = [url resourceSpecifier];
            if ([resource isEqualToString:@"restartTransmission"]) {
                NSLog(@"clutch agent asked to quit Transmission gracefully");
                
                NSLog(@"clutch agent checking self.clutch in url handler: %@", self.clutch);
                [GracefulQuit restartTransmissionGracefully:[self.clutch shouldRestartGracefully] withCallback:^{
                    // tell Clutch that Transmission has quit (if it was not running, this will fire immediately)
                    [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-transmission:quitCallback"]];
                }];
            } else if ([resource isEqualToString:@"testAppleScript"]) {
                [self testAppleScriptWithPrompt:NO];
            } else if ([resource isEqualToString:@"testAppleScriptWithPrompt"]) {
                [self testAppleScriptWithPrompt:YES];
            }
        }
    }
}

- (void)testAppleScriptWithPrompt:(BOOL)prompt {
    // only display the prompt when the user expects it
    // in our case, it's when they check the "restart gracefully" checkbox,
    // and Clutch will send a separate URL call to tell us to prompt the user
    // (the prompt here is NECESSARY to add Clutch Agent to the Accessibility permissions
    // section; merely checking AXIsProcessTrusted() will NOT add it to the list!)
    if (prompt) {
        
        // when Clutch Agent runs the test script to see if we have permissions,
        // the Automation permission option is automatically added to the list;
        // the Accessibility permission option is NOT added until you run this code
        // to prompt the user for permission
        // (and because Clutch Agent is the app that's actually performing the actions,
        // which it must be because it must do this in the background,
        // this must be called here inside of Clutch Agent)
        //
        // for some strange reason, because Clutch Agent.app is inside Clutch.app,
        // the Accessibility permissions section lists "Clutch.app" and checking its box works, but
        // the Automation permissions section only works when you call the below code from
        // Clutch Agent.app and check the box next to "Clutch Agent.app"
        // (calling it from Clutch.app and checking the box next to Clutch.app does NOT work!)
        NSDictionary *options = @{(__bridge id) kAXTrustedCheckOptionPrompt : @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef) options);
    }
    
    BOOL hasPermissions = [GracefulQuit hasPermissions];
    if (hasPermissions) {
        [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-transmission:hasPermissionsTrue"]];
    } else {
        [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-transmission:hasPermissionsFalse"]];
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    NSLog(@"invalidating timer");
    [self.pollTimer invalidate];
}

@end
