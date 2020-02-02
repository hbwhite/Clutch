//
//  AppDelegate.m
//  Clutch
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2020 Harrison White. All rights reserved.
//
//  See LICENSE for licensing information
//

#import "AppDelegate.h"
#import "Clutch.h"
#import "Reaper.h"
#import "Constants.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    [[SUUpdater sharedUpdater]setDelegate:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL* url in urls) {
        if ([[url scheme]isEqualToString:@"clutch-transmission"]) {
            NSLog(@"clutch got url call");
            
            // check if the user opened Clutch via the "Check for Updates..."
            // menu item in Clutch Agent
            
            // using a custom URL scheme for this so it will work whether or
            // not the Clutch app was already running
            
            // I used this odd url scheme name in case the user has another app named
            // "clutch" installed that needs the plain "clutch" url scheme
            
            NSString* resource = [url resourceSpecifier];
            if ([resource isEqualToString:kCheckForUpdatesArg]) {
                [[SUUpdater sharedUpdater]checkForUpdates:self];
            } else if ([resource isEqualToString:@"quitCallback"]) {
                NSLog(@"clutch got transmission quit callback, posting notification");
                // Clutch Agent is done quitting Transmission gracefully
                [[NSNotificationCenter defaultCenter]postNotificationName:kTransmissionQuitNotificationName object:nil];
            } else if ([resource isEqualToString:@"hasPermissionsTrue"]) {
                NSLog(@"clutch got has permissions TRUE");
                [[NSNotificationCenter defaultCenter]postNotificationName:kClutchAgentPermissionsTrueNotificationName object:nil];
            } else if ([resource isEqualToString:@"hasPermissionsFalse"]) {
                NSLog(@"clutch got has permissions FALSE");
                [[NSNotificationCenter defaultCenter]postNotificationName:kClutchAgentPermissionsFalseNotificationName object:nil];
            }
        }
    }
}

// quit Clutch when the user clicks the red x button in the corner
// so we don't have an unnecessary app running in the background
// (Clutch Agent is separate and will continue to run)
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return YES;
}

// Return YES to delay the relaunch until you do some processing.
// Invoke the provided NSInvocation to continue the relaunch.
- (BOOL)updater:(SUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)update
  untilInvoking:(NSInvocation *)invocation {
    
    // When Clutch is updated, Sparkle automatically relaunches it,
    // but the old version of Clutch Agent will still be running in the background.
    // Here, we force Clutch Agent to quit so the new version of Clutch Agent will start when
    // the Clutch app is restarted.
    
    [[Reaper sharedInstance]killAppWithBundleID:kClutchAgentBundleID terminationBlock:nil callback:^(BOOL wasRunning) {
        // killed Clutch Agent, now let Sparkle restart the Clutch app
        // which will launch the new version of Clutch Agent
        [invocation invoke];
    }];
    return YES;
}

@end
