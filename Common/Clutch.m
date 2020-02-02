//
//  Clutch.m
//  Clutch
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2020 Harrison White. All rights reserved.
//
//  See LICENSE for licensing information
//

#import "Clutch.h"
#import "Reaper.h"
#import "Constants.h"
#import <SystemConfiguration/SystemConfiguration.h>

#define _GNU_SOURCE /* To get defns of NI_MAXSERV and NI_MAXHOST */
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netdb.h>
#include <ifaddrs.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

static Clutch *sharedInstance   = nil;

// You need to DISABLE the App Sandbox in "capabilities" in the Xcode project before things
// like editing other apps' preferences, killing other processes, etc. will function properly

// Also, apparently you must disable the sandbox in order to prompt the user for Accessibility permissions
// (necessary for gracefully quitting Transmission via AppleScript)
// https://forums.developer.apple.com/thread/24288

static NSString* kGroupPreferencesID        = @"8TSRGQJRTM.group.com.rcx.clutch";

static NSString* kBindInterfaceKey          = @"BindInterface";
static NSString* kGracefullyRestartKey      = @"Gracefully Restart";

static NSString* kBindAddressIPv4Key        = @"BindAddressIPv4";
static NSString* kBindAddressIPv6Key        = @"BindAddressIPv6";

@implementation ClutchInterface

// make serializable for storing in NSUserDefaults
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.address forKey:@"address"];
    [coder encodeBool:self.ipv4 forKey:@"ipv4"];
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.name       = [coder decodeObjectForKey:@"name"];
        self.address    = [coder decodeObjectForKey:@"address"];
        self.ipv4       = [coder decodeBoolForKey:@"ipv4"];
    }
    return self;
}

@end

@interface Clutch ()

@property (nonatomic, strong) NSUserDefaults* transmissionDefaults;

// this must be retained here so we can observe when it is terminated
// otherwise, ARC will release it while a key-value observer is registered and crash the app
@property (nonatomic, strong) NSMutableArray<NSRunningApplication *>* transmissionInstances;

@end

@implementation Clutch

+ (instancetype)sharedInstance {
    @synchronized (self) {
        if (!sharedInstance) {
            sharedInstance = [[Clutch alloc]init];
        }
        return sharedInstance;
    }
}

- (id)init {
    self = [super init];
    if (self) {
        self.clutchGroupDefaults = [[NSUserDefaults alloc]initWithSuiteName:kGroupPreferencesID];
        self.transmissionDefaults = [[NSUserDefaults alloc]initWithSuiteName:kTransmissionBundleID];
        
        self.transmissionInstances = [[NSMutableArray alloc]init];
    }
    return self;
}

- (ClutchInterface *)getBindInterface {
    NSData *data = [self.clutchGroupDefaults objectForKey:kBindInterfaceKey];
    return data ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
}

- (void)unbindFromInterface {
    NSUserDefaults* transmissionDefaults = [self transmissionDefaults];
    [transmissionDefaults removeObjectForKey:kBindAddressIPv4Key];
    [transmissionDefaults removeObjectForKey:kBindAddressIPv6Key];
    [transmissionDefaults synchronize];
    
    [self.clutchGroupDefaults removeObjectForKey:kBindInterfaceKey];
    [self.clutchGroupDefaults synchronize];
}

- (void)bindToInterface:(ClutchInterface *)interface {
    NSUserDefaults* transmissionDefaults = [self transmissionDefaults];
    if (interface.ipv4) {
        [transmissionDefaults removeObjectForKey:kBindAddressIPv6Key];
        [transmissionDefaults setObject:interface.address forKey:kBindAddressIPv4Key];
    }
    else {
        [transmissionDefaults removeObjectForKey:kBindAddressIPv4Key];
        [transmissionDefaults setObject:interface.address forKey:kBindAddressIPv6Key];
    }
    [transmissionDefaults synchronize];
    
    [self.clutchGroupDefaults setObject:[NSKeyedArchiver archivedDataWithRootObject:interface] forKey:kBindInterfaceKey];
    [self.clutchGroupDefaults synchronize];
}

- (void)bindToInterfaceWithName:(NSString *)name {
    // update bind address
    
    // Apple docs say specifying another app's identifier will return its preferences (assuming there is NO sandbox in place)
    // https://developer.apple.com/documentation/foundation/nsuserdefaults/1409957-initwithsuitename
    
    // Alternative solution
    /*
    NSString *writeCmd = [@"/usr/bin/defaults write org.m0k.transmission BindAddressIPv4 " stringByAppendingString:interface.address];
    NSLog(@"writeCmd %@", writeCmd);
    if (system([writeCmd cStringUsingEncoding:NSASCIIStringEncoding]) != 0) {
        return NO;
    }
    */
    
    // bind to the first interface with the given name
    
    ClutchInterface* bindInterface = nil;
    
    NSLog(@"clutch core bindToInterfaceWithName \"%@\"", name);
    
    for (ClutchInterface* interface in [self getInterfaces]) {
        // NSLog(@"checking interface %@ %@ %@", interface.name, interface.address, interface.ipv4 ? @"ipv4" : @"ipv6");
        
        NSRange regexMatchRange = [interface.name rangeOfString:name options:NSRegularExpressionSearch];
        // NSLog(@"comparing range %@ to %@", NSStringFromRange(regexMatchRange), NSStringFromRange(NSMakeRange(0, interface.name.length)));
        if (regexMatchRange.location == 0 && regexMatchRange.length == interface.name.length) {
            NSLog(@"matched; binding");
            
            // regex matched whole interface name; use this interface
            bindInterface = [[ClutchInterface alloc]init];
            
            // set bind interface name to provided regex
            bindInterface.name = name;
            
            // copy other values from matching ClutchInterface object
            bindInterface.address = interface.address;
            bindInterface.ipv4 = interface.ipv4;
            break;
        }
    }
    
    if (!bindInterface) {
        // important!
        // if an interface with the given name does NOT exist, bind to localhost to block traffic until it comes back up
        
        // create localhost placeholder interface
        bindInterface = [[ClutchInterface alloc]init];
        bindInterface.name = name;
        bindInterface.address = @"127.0.0.1";
        bindInterface.ipv4 = YES;
    }
    
    [self bindToInterface:bindInterface];
}

// I was looking for a way to get a callback when a utun interface changed.
// I looked here but didn't find anything that worked for this purpose:
// https://developer.apple.com/library/content/technotes/tn1145/_index.html
// So I'm using a polling timer instead

// getifaddrs code from:
// http://man7.org/linux/man-pages/man3/getifaddrs.3.html

- (NSArray *)getInterfaces {
    // SCNetworkInterfaceCopyAll doesn't list utun interfaces!
    /*
    NSArray *ifs = (__bridge NSArray *)SCNetworkInterfaceCopyAll();
    
    for (int i = 0; i < [ifs count]; i++) {
        SCNetworkInterfaceRef interface = (__bridge SCNetworkInterfaceRef)[ifs objectAtIndex:i];
        NSString *name = (__bridge NSString *)SCNetworkInterfaceGetBSDName(interface);
        NSLog(@"got name %@", name);
    }
    */
    
    NSMutableArray* interfaces = [[NSMutableArray alloc]init];
    
    struct ifaddrs *ifaddr, *ifa;
    int family, s, n;
    char host[NI_MAXHOST];
    
    if (getifaddrs(&ifaddr) == -1) {
        fprintf(stderr, "getifaddrs");
        
        // error getting interfaces; return empty array
        return interfaces;
    }
    
    /* Walk through linked list, maintaining head pointer so we
     can free list later */
    
    for (ifa = ifaddr, n = 0; ifa != NULL; ifa = ifa->ifa_next, n++) {
        if (ifa->ifa_addr == NULL)
            continue;
        
        family = ifa->ifa_addr->sa_family;
        
        /* For an AF_INET* interface address, display the address */
        
        if (family == AF_INET || family == AF_INET6) {
            s = getnameinfo(ifa->ifa_addr,
                            (family == AF_INET) ? sizeof(struct sockaddr_in) :
                            sizeof(struct sockaddr_in6),
                            host, NI_MAXHOST,
                            NULL, 0, NI_NUMERICHOST);
            if (s != 0) {
                printf("getnameinfo() failed: %s\n", gai_strerror(s));
                continue;
            }
            
            /* Display interface name and family (including symbolic
             form of the latter for the common families) */
            
            // printf("%-8s %s (%d)\n", ifa->ifa_name, (family == AF_INET) ? "AF_INET" : "AF_INET6", family);
            // printf("\t\taddress: <%s>\n", host);
            
            /* create new Clutch interface object */
            
            ClutchInterface* interface = [[ClutchInterface alloc]init];
            interface.name      = [NSString stringWithCString:ifa->ifa_name encoding:NSASCIIStringEncoding];
            interface.address   = [NSString stringWithCString:host encoding:NSASCIIStringEncoding];
            interface.ipv4      = (family == AF_INET);
            
            [interfaces addObject:interface];
        }
    }
    
    freeifaddrs(ifaddr);
    
    return interfaces;
}

- (BOOL)shouldRestartGracefully {
    return [self.clutchGroupDefaults boolForKey:kGracefullyRestartKey];
}

- (void)setShouldRestartGracefully:(BOOL)restartGracefully {
    [self.clutchGroupDefaults setBool:restartGracefully forKey:kGracefullyRestartKey];
    [self.clutchGroupDefaults synchronize];
}

@end
