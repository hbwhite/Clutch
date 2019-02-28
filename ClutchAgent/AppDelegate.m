//
//  AppDelegate.m
//  ClutchAgent
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2018 Harrison White. All rights reserved.
//

/*
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "AppDelegate.h"
#import "Clutch.h"

#define POLL_INTERVAL   10

@interface AppDelegate () <NSMenuDelegate>

@property (nonatomic, strong) IBOutlet NSMenu* barMenu;
@property (nonatomic, strong) IBOutlet NSMenuItem* statusItem;
@property (nonatomic, strong) IBOutlet NSMenuItem* bindAddressItem;
@property (nonatomic, strong) NSStatusItem* barItem;
@property (nonatomic, strong) NSTimer* pollTimer;

@end

@implementation AppDelegate

- (IBAction)openTransmission:(id)sender {
    [[NSWorkspace sharedWorkspace]launchApplication:@"Transmission"];
}

- (IBAction)openClutch:(id)sender {
    NSArray *pathComponents = [[[NSBundle mainBundle]bundlePath]pathComponents];
    NSString *path = [NSString pathWithComponents:[pathComponents subarrayWithRange:NSMakeRange(0, pathComponents.count - 4)]];
    [[NSWorkspace sharedWorkspace]launchApplication:path];
}

- (IBAction)quitClutchAgent:(id)sender {
    [NSApp terminate:nil];
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
    
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:POLL_INTERVAL repeats:YES block:^(NSTimer * _Nonnull timer) {
        ClutchInterface* bindInterface = [clutch getBindInterface];
        
        if (bindInterface) {
            NSArray* interfaces = [clutch getInterfaces];
            for (ClutchInterface* interface in interfaces) {
                // if the name and ipv4 status match, treat as identical
                // (don't treat interfaces with the same name but different ipv4/ipv6 statuses as identical,
                // as some VPNs or networks may not support IPv6 and could send this traffic in the clear instead
                // if an IPv6 interface is used instead of its IPv4 counterpart)
                
                if ([interface.name isEqualToString:bindInterface.name] && interface.ipv4 == bindInterface.ipv4) {
                    if (![interface.address isEqualToString:bindInterface.address]) {
                        NSLog(@"interface address changed, binding to new IP...\n");
                        [clutch bindToInterface:interface];
                        bindInterface = interface; // used below to update status
                    }
                    break;
                }
            }
            
            [self.statusItem setTitle:[NSString stringWithFormat:@"Binding to %@", bindInterface.name]];
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
