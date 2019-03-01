//
//  Reaper.h
//  Clutch
//
//  Created by Harrison White on 2/28/19.
//  Copyright © 2019 Harrison White. All rights reserved.
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
 */
- (BOOL)killAppWithBundleID:(NSString *)bundleID callback:(void (^)(void))callback;

@end
