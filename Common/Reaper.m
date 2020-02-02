//
//  Reaper.m
//  Clutch
//
//  Created by Harrison White on 2/28/19.
//  Copyright © 2020 Harrison White. All rights reserved.
//  
//  See LICENSE for licensing information
//

#import "Reaper.h"

// kqueue event
#import <sys/event.h>

static Reaper *sharedInstance   = nil;

NSString* kTerminationCallbackKey   = @"terminaionCallback";

static void *kAppTerminatedContext  = &kAppTerminatedContext;

@interface AppInstance : NSObject

@property (nonatomic, strong) NSRunningApplication* app;
@property (nonatomic, strong) void (^terminationCallback)(BOOL);

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
        
        NSLog(@"adding workspace observer");
        // observing the NSRunningApplication "isTerminated" key path
        // and subscribing to the NSWorkspaceDidTerminateApplicationNotification
        // DO NOT WORK when you quit Transmission via AppleScript, as it appears to be an external action.
        // To observe this, you need to dig deeper:
        // https://stackoverflow.com/questions/4128002/nsrunningapplication-terminated-not-observable
        // https://developer.apple.com/library/archive/technotes/tn2050/_index.html#//apple_ref/doc/uid/DTS10003081-CH1-SECTION8
        //
        // "Both NSWorkspace and Carbon events only work within a single GUI login context. If you're writing a program that does not run within a GUI login context (a daemon perhaps), or you need to monitor a process in a different context from the one in which you're running, you will need to consider alternatives.
        // One such alternative is the kqueue NOTE_EXIT event. You can use this to detect when a process quits, regardless of what context it's running in. Unlike NSWorkspace and Carbon events, you must specify exactly which process to monitor; there is no way to be notified when any process terminates."
        //
    }
    return self;
}

- (void)monitorPID:(pid_t)gTargetPID
{
    int                     kq;
    struct kevent           changes;
    CFFileDescriptorContext context = { 0, (__bridge void *)(self), NULL, NULL, NULL };
    CFFileDescriptorRef     noteExitKQueueRef;
    CFRunLoopSourceRef      rls;

    // Create the kqueue and set it up to watch for SIGCHLD. Use the
    // new-in-10.5 EV_RECEIPT flag to ensure that we get what we expect.

    kq = kqueue();

    EV_SET(&changes, gTargetPID, EVFILT_PROC, EV_ADD | EV_RECEIPT, NOTE_EXIT, 0, NULL);
    (void) kevent(kq, &changes, 1, &changes, 1, NULL);

    // Wrap the kqueue in a CFFileDescriptor (new in Mac OS X 10.5!). Then
    // create a run-loop source from the CFFileDescriptor and add that to the
    // runloop.

    noteExitKQueueRef = CFFileDescriptorCreate(NULL, kq, true, NoteExitKQueueCallback, &context);
    rls = CFFileDescriptorCreateRunLoopSource(NULL, noteExitKQueueRef, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRelease(rls);

    CFFileDescriptorEnableCallBacks(noteExitKQueueRef, kCFFileDescriptorReadCallBack);

    // Execution continues in NoteExitKQueueCallback, below.
}

static void NoteExitKQueueCallback(
    CFFileDescriptorRef f,
    CFOptionFlags       callBackTypes,
    void *              info
)
{
    struct kevent   event;

    (void) kevent( CFFileDescriptorGetNativeDescriptor(f), NULL, 0, &event, 1, NULL);

    NSLog(@"terminated %d", (int) (pid_t) event.ident);

    // You've been notified!
    
    [[Reaper sharedInstance]notifyPidTerminated:(pid_t)event.ident];
}

- (void)notifyPidTerminated:(pid_t)gTargetPID {
    NSLog(@"reaper notifyPidTerminated");
    NSNumber* lookupKey = [NSNumber numberWithInt:gTargetPID];
    AppInstance* instance = [self.appInstances objectForKey:lookupKey];
    if (instance) {
        NSLog(@"found instance, calling termination callback");
        instance.terminationCallback(YES); // YES = app asked to terminate was running
        
        // we no longer need to retain this NSRunningApplication instance
        // it is contained within the AppInstance object we're removing here
        [self.appInstances removeObjectForKey:lookupKey];
    } else {
        NSLog(@"no instance found, ignoring");
    }
}



- (BOOL)killAppWithBundleID:(NSString *)bundleID terminationBlock:(void (^)(NSRunningApplication *))terminationBlock callback:(void (^)(BOOL))callback {
    // close the app with this bundle ID if it's running
    
    // retain these NSRunningApplication instances
    // otherwise they will be released by ARC while we're still observing them to see when they terminate and crash the app
    
    BOOL wasRunning = NO;
    
    for (NSRunningApplication* app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        wasRunning = YES;
        
        // only monitor the instance if a callback was provided
        if (callback) {
            AppInstance* instance = [[AppInstance alloc]init];
            instance.app = app;
            instance.terminationCallback = callback;
            [self.appInstances setObject:instance forKey:[NSNumber numberWithInt:app.processIdentifier]];
            
            NSLog(@"monitoring pid %d", app.processIdentifier);
            [self monitorPID:app.processIdentifier];
        }
        
        // if plain -terminate was used, Transmission would present an "are you sure" dialog that would prevent the app from quitting
        if (terminationBlock) {
            terminationBlock(app);
        } else {
            [app forceTerminate];
        }
    }
    
    // App wasn't running, so fire callback immediately
    if (!wasRunning) {
        callback(NO); // NO = app asked to terminate was not running
    }
    
    return wasRunning;
}

@end
