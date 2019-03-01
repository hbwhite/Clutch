//
//  Reaper.m
//  Clutch
//
//  Created by Harrison White on 2/28/19.
//  Copyright © 2019 Harrison White. All rights reserved.
//  
//  See LICENSE for licensing information
//

#import "Reaper.h"

static Reaper *sharedInstance   = nil;

// NSRunningApplication -isTerminated
NSString* kAppTerminatedKeyPath     = @"isTerminated";
NSString* kTerminationCallbackKey   = @"terminaionCallback";

static void *kAppTerminatedContext  = &kAppTerminatedContext;

@interface AppInstance : NSObject

@property (nonatomic, strong) NSRunningApplication* app;
@property (nonatomic, strong) void (^terminationCallback)(void);

@end
@implementation AppInstance
@end

@interface Reaper ()

// this must be retained here so we can observe when it is terminated
// otherwise, ARC will release it while a key-value observer is registered and crash the app
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, AppInstance *> *appInstances;

@end

@implementation Reaper

+ (instancetype)sharedInstance {
    @synchronized (self) {
        if (!sharedInstance) {
            sharedInstance = [[Reaper alloc]init];
        }
        return sharedInstance;
    }
}

- (id)init {
    self = [super init];
    if (self) {
        self.appInstances = [[NSMutableDictionary alloc]init];
    }
    return self;
}

- (BOOL)killAppWithBundleID:(NSString *)bundleID callback:(void (^)(void))callback {
    // close the app with this bundle ID if it's running
    
    // retain these NSRunningApplication instances
    // otherwise they will be released by ARC while we're still observing them to see when they terminate and crash the app
    
    BOOL wasRunning = NO;
    
    for (NSRunningApplication* app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        wasRunning = YES;
        
        AppInstance* instance = [[AppInstance alloc]init];
        instance.app = app;
        instance.terminationCallback = callback;
        [self.appInstances setObject:instance forKey:[NSNumber numberWithInt:app.processIdentifier]];
        
        [app addObserver:self forKeyPath:kAppTerminatedKeyPath options:NSKeyValueObservingOptionNew context:kAppTerminatedContext];
        
        // if plain -terminate was used, Transmission would present an "are you sure" dialog that would prevent the app from quitting
        [app forceTerminate];
    }
    
    return wasRunning;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    
    if (context == kAppTerminatedContext) {
        NSRunningApplication* app = (NSRunningApplication *)object;
        
        // we no longer need to observe the "isTerminated" property
        // must remove observers before releasing the object
        [app removeObserver:self forKeyPath:kAppTerminatedKeyPath context:kAppTerminatedContext];
        
        NSNumber* lookupKey = [NSNumber numberWithInt:app.processIdentifier];
        AppInstance* instance = [self.appInstances objectForKey:lookupKey];
        instance.terminationCallback();
        
        // we no longer need to retain this NSRunningApplication instance
        // it is contained within the AppInstance object we're removing here
        [self.appInstances removeObjectForKey:lookupKey];
        
    } else {
        // Any unrecognized context must belong to super
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

@end
