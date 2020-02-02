//
//  GracefulQuit.m
//  Clutch Agent
//
//  Created by Harrison White on 2/1/20.
//  Copyright © 2020 Harrison White. All rights reserved.
//  
//  See LICENSE for licensing information
//

#import "GracefulQuit.h"
#import "Reaper.h"
#import "Constants.h"

@implementation GracefulQuit

// TO RESET AUTOMATION PERMISSIONS:
// tccutil reset AppleEvents; tccutil reset SystemPolicyAllFiles

// Note:
//

// this prompts the user for accessibility permissions,
// but it's no better than the way I'm doing it now;
// also, I can't find a way to prompt for Automation permissions,
// so it's simpler to use the PermissionsViewController the way I'm doing it now

// to check Accessibility permissions without prompt:
// AXIsProcessTrusted()
    
// NSDictionary *options = @{(__bridge id) kAXTrustedCheckOptionPrompt : @YES};
// BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef) options);
// if (accessibilityEnabled) {
//     NSLog(@"accessibility enabled");
// } else {
//     NSLog(@"accessibility disabled");
// }

+ (BOOL)hasPermissions {
    NSError* srcLoadError = nil;
    NSString* appleScriptSrc = [[NSString alloc]initWithContentsOfFile:[[NSBundle mainBundle]pathForResource:@"test-applescript" ofType:@"txt"] encoding:NSUTF8StringEncoding error:&srcLoadError];

    NSLog(@"loaded applescript src %@, error %@", appleScriptSrc, srcLoadError);

    NSAppleScript* script = [[NSAppleScript alloc]initWithSource:appleScriptSrc];
    
    NSDictionary<NSString *, id> *scriptError = nil;
    [script executeAndReturnError:&scriptError];
    if (scriptError) {
        // user probably denied access to either (a) Apple Events, or (b) Accessibility
        // (a) "Not authorized to send Apple events to System Events." -- Error "-1743"
        // (b) "Clutch is not allowed assistive access." -- Error "-25211"
        // Error "-1728" = script failed
        NSLog(@"applescript execute got error %@", scriptError);
        NSLog(@"error num %@", scriptError[NSAppleScriptErrorNumber]);
        
    } else {
        NSLog(@"success!");
        return YES;
    }
    
    return NO;
}

+ (void)restartTransmissionGracefully:(BOOL)gracefully withCallback:(nullable void (^)(void))callback {
    
    [[Reaper sharedInstance]killAppWithBundleID:kTransmissionBundleID terminationBlock:^(NSRunningApplication *app) {
        if (gracefully) {
            // quit Transmission gracefully
            [app terminate];
            
            NSLog(@"got bundle path %@", [[NSBundle mainBundle]bundlePath]);
            
            NSError* srcLoadError = nil;
            NSString* appleScriptSrc = [[NSString alloc]initWithContentsOfFile:[[NSBundle mainBundle]pathForResource:@"quit-transmission-applescript" ofType:@"txt"] encoding:NSUTF8StringEncoding error:&srcLoadError];
            
            NSLog(@"loaded applescript src %@, error %@", appleScriptSrc, srcLoadError);
            
            NSAppleScript* script = [[NSAppleScript alloc]initWithSource:appleScriptSrc];
            
            NSDictionary<NSString *, id> *scriptError = nil;
            [script executeAndReturnError:&scriptError];
            if (scriptError) {
                // user probably denied access to either (a) Apple Events, or (b) Accessibility
                // (a) "Not authorized to send Apple events to System Events." -- Error "-1743"
                // (b) "Clutch is not allowed assistive access." -- Error "-25211"
                // Error "-1728" = script failed
                NSLog(@"applescript execute got error %@", scriptError);
                NSLog(@"error num %@", scriptError[NSAppleScriptErrorNumber]);
                
                // if there was an error, force terminate
                // quitting gracefully didn't work; force quit
                NSLog(@"script got error, force terminate");
                
                // we don't need a callback here because the callback below (from the original call to the reaper)
                // will fire when Transmission quits
                [app forceTerminate];
                
            } else {
                NSLog(@"success!");
            }
        } else {
            // force-quit Transmission
            [app forceTerminate];
        }
        
    } callback:^(BOOL wasRunning) {
        if (wasRunning) {
            [[NSWorkspace sharedWorkspace]launchApplication:@"Transmission"];
        }
        if (callback) {
            callback();
        }
    }];
}

@end
