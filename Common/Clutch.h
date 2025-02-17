//
//  Clutch.h
//  Clutch
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2020 Harrison White. All rights reserved.
//
//  See LICENSE for licensing information
//

#import <Cocoa/Cocoa.h>

// static so when we import these in multiple places in the same project
// we won't get linker errors from duplicate symbols
// (multiple identical file-local vars)
static NSString* kCheckForUpdatesArg    = @"checkForUpdates";
static NSString* kClutchAgentBundleID   = @"com.rcx.clutchagent";

@interface ClutchInterface : NSObject

@property (nonatomic, strong) NSString* name;
@property (nonatomic, strong) NSString* address;
@property (readwrite) BOOL ipv4;

@end

@interface Clutch : NSObject

@property (nonatomic, strong) NSUserDefaults* clutchGroupDefaults;

/*
 * Returns the Clutch singleton
 */
+ (instancetype)sharedInstance;

- (ClutchInterface *)getBindInterface;
- (NSArray *)getInterfaces;
- (void)unbindFromInterface;
- (void)bindToInterface:(ClutchInterface *)interface;
- (void)bindToInterfaceWithName:(NSString *)name;
- (BOOL)shouldRestartGracefully;
- (void)setShouldRestartGracefully:(BOOL)restartGracefully;

@end
