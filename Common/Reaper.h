//
//  Reaper.h
//  Clutch
//
//  Created by Harrison White on 2/28/19.
//  Copyright © 2020 Harrison White. All rights reserved.
//  
//  See LICENSE for licensing information
//
//
//                 ...                            
//                ;::::;                           
//              ;::::; :;                          
//            ;:::::'   :;                         
//           ;:::::;     ;.                        
//          ,:::::'       ;           OOO\         
//          ::::::;       ;          OOOOO\        
//          ;:::::;       ;         OOOOOOOO       
//         ,;::::::;     ;'         / OOOOOOO      
//       ;:::::::::`. ,,,;.        /  / DOOOOOO    
//     .';:::::::::::::::::;,     /  /     DOOOO   
//    ,::::::;::::::;;;;::::;,   /  /        DOOO  
//   ;`::::::`'::::::;;;::::: ,#/  /          DOOO 
//   :`:::::::`;::::::;;::: ;::#  /            DOOO
//   ::`:::::::`;:::::::: ;::::# /              DOO
//   `:`:::::::`;:::::: ;::::::#/               DOO
//    :::`:::::::`;; ;:::::::::##                OO
//    ::::`:::::::`;::::::::;:::#                OO
//    `:::::`::::::::::::;'`:;::#                O 
//     `:::::`::::::::;' /  / `:#                  
//      ::::::`:::::;'  /  /   `#
//
//

#import <Cocoa/Cocoa.h>

@interface Reaper : NSObject

/*
 * Returns the Reaper singleton
 */
+ (instancetype)sharedInstance;

/*
 * Returns whether the app was previously running
 *
 * terminationBlock allows you to pass a custom function to terminate the app (e.g. for gracefully quitting);
 * if it is not provided, the reaper will use -forceTerminate
 *
 * callback will fire only after the app has been terminated;
 * this is the key feature of the reaper; it will notify you when the app has been terminated;
 * it also mentions whether the app was running in the first place in case you wish to restart it
 */
- (BOOL)killAppWithBundleID:(NSString *)bundleID
           terminationBlock:(void (^)(NSRunningApplication *))terminationBlock
                   callback:(void (^)(BOOL wasRunning))callback;

@end
