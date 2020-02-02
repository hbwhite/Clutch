//
//  GracefulQuit.h
//  Clutch Agent
//
//  Created by Harrison White on 2/1/20.
//  Copyright © 2020 Harrison White. All rights reserved.
//  
//  See LICENSE for licensing information
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GracefulQuit : NSObject

+ (BOOL)hasPermissions;

// "nullable" added to avoid error "Null passed to a callee that requires a non-null argument"
+ (void)restartTransmissionGracefully:(BOOL)gracefully withCallback:(nullable void (^)(void))callback;

@end

NS_ASSUME_NONNULL_END
