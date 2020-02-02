//
//  ViewController.m
//  Clutch
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2020 Harrison White. All rights reserved.
//
//  See LICENSE for licensing information
//

#import "ViewController.h"
#import "Clutch.h"
#import "Reaper.h"
#import "Constants.h"
#import <ServiceManagement/ServiceManagement.h>
#import "PermissionsViewController.h"

static NSString* kSavedTextKey        = @"Saved Text";
static NSString* kHelpShownKey        = @"Help Shown3";

@interface ViewController () <NSControlTextEditingDelegate, NSComboBoxDelegate>

@property (nonatomic, strong) IBOutlet NSComboBox* interfaceDropdown;
@property (nonatomic, strong) IBOutlet NSButton* bindButton;
@property (nonatomic, strong) IBOutlet NSTextField* statusLabel;
@property (nonatomic, strong) IBOutlet NSButton* gracefullyRestartTransmissionButton;
@property (nonatomic, strong) IBOutlet NSButton* openClutchAgentAtLoginButton;
@property (nonatomic, strong) IBOutlet NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) NSMutableArray* interfaces;
@property (nonatomic) BOOL hasPermissions;
@property (nonatomic) BOOL justCheckedGracefulBox;
@property (nonatomic) BOOL justFinishedPermissionsVC;

@end

@implementation ViewController

// custom getter so self.clutch automatically calls [Clutch sharedInstance]
// (self.clutch is less cumbersome to write)
- (Clutch *)clutch {
    return [Clutch sharedInstance];
}

- (IBAction)gracefullyRestartHelpButtonClicked:(id)sender {
    // the prompt is the only way to add Clutch Agent to the Automation permissions list;
    //
    // if this is the user's first time seeing the permissions VC (because they clicked
    // the help button instead of clicking the "restart gracefully" checkbox),
    // and if they decide to follow the instructions, Clutch Agent would be
    // missing from the Automation permissions list if we only called
    // -showPermissionsViewController without -checkPermissionsWithPrompt:YES
    [self checkPermissionsWithPrompt:YES];
    
    // the permissions VC won't automatically show when we get a permissions callback
    // because we didn't set justCheckedGracefulBox=YES; manually show it immediately here
    [self showPermissionsViewController];
}

- (IBAction)gracefullyRestartTransmissionToggle:(id)sender {
    if (self.gracefullyRestartTransmissionButton.state == NSControlStateValueOn) {
        // if it turns out that we don't have permissions after the callback
        // from [self checkPermissions], immediately show the PermissionsViewController
        self.justCheckedGracefulBox = YES;
        [self checkPermissionsWithPrompt:YES];
    } else {
        [self.clutch setShouldRestartGracefully:NO];
    }
}

- (void)comboBoxWillPopUp:(NSNotification *)notification {
    NSLog(@"combo box will pop up; updating interface dropdown");
    
    // refresh the interface names when the user opens the dropdown
    // (self.interfaceDropdown.delegate = self is set in the storyboard)
    [self updateInterfaceDropdown];
}

- (IBAction)bindToInterfaceClicked:(id)sender {
    
    // hide the buttons until Clutch Agent notifies us that Transmission has been quit (if it isn't running, this notification will happen immediately)
    // this is to prevent the user from clicking the button many times in succession, which could cause a crash
    
    [self.progressIndicator startAnimation:nil];
    self.bindButton.enabled = NO;
    self.statusLabel.hidden = YES;
    
    if ([self.clutch getBindInterface]) {
        NSLog(@"unbinding");
        [self.clutch unbindFromInterface];
    }
    else {
        NSLog(@"binding");
        [self.clutch bindToInterfaceWithName:self.interfaceDropdown.stringValue];
    }
    
    // tell Clutch Agent to restart Transmission gracefully
    [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-agent-transmission:restartTransmission"]];
    
    [self saveText];
}

- (void)showHelp {
    [self performSegueWithIdentifier:@"showHelp" sender:nil];
}

- (void)saveText {
    // self.interfaceDropdown.currentEditor.selectedRange = NSMakeRange(0, self.interfaceDropdown.stringValue.length);
    
    // save the text
    NSUserDefaults* defaults = [self.clutch clutchGroupDefaults];
    [defaults setObject:self.interfaceDropdown.stringValue forKey:kSavedTextKey];
    [defaults synchronize];
}

- (void)mouseDown:(NSEvent *)theEvent {
    // deselect the text field
    [self.view.window makeFirstResponder:nil];
    
    [self saveText];
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor {
    [self saveText];
    return YES;
}

- (IBAction)interfaceSelected:(NSComboBox *)sender {
    // in the list, the ip address and other info is shown
    // however, once the item is selected, only enter the name in the box
    
    // this shows the user that, for a manual entry, they only need to enter the name of the interface
    
    NSInteger index = self.interfaceDropdown.indexOfSelectedItem;
    if (index >= 0 && index < self.interfaces.count) {
        ClutchInterface* selectedInterface = [self.interfaces objectAtIndex:self.interfaceDropdown.indexOfSelectedItem];
        self.interfaceDropdown.stringValue = selectedInterface.name;
    }
}

- (IBAction)openAtLoginCheckboxChanged:(NSButton *)sender {
    // Ignore deprecated warnings
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    LSSharedFileListItemRef clutchAgentLoginItem = nil;
    LSSharedFileListRef loginItemsList = nil;
    [self getClutchAgentLoginItem:&clutchAgentLoginItem loginItemsList:&loginItemsList];
    
    if (sender.state == NSOnState && !clutchAgentLoginItem && loginItemsList) {
        // login item does not exist; add
        
        NSURL* clutchAgentURL = [NSURL fileURLWithPath:[self clutchAgentPath]];
        clutchAgentLoginItem = LSSharedFileListInsertItemURL(loginItemsList, kLSSharedFileListItemBeforeFirst, NULL, NULL, (__bridge CFURLRef)clutchAgentURL, NULL, NULL);
        if (!clutchAgentLoginItem) {
            NSLog(@"error adding login item!");
        }
    }
    else if (sender.state == NSOffState && clutchAgentLoginItem && loginItemsList) {
        // login item exists; remove
        LSSharedFileListItemRemove(loginItemsList, clutchAgentLoginItem);
    }
    
    CFRelease(loginItemsList); // don't forget to release memory
#pragma GCC diagnostic pop
}

- (void)getClutchAgentLoginItem:(LSSharedFileListItemRef *)clutchAgentLoginItem loginItemsList:(LSSharedFileListRef *)loginItemsList {
    // This didn't seem to work when I tried it. Perhaps it only works with sandboxed apps.
    // SMLoginItemSetEnabled((__bridge CFStringRef)@"com.rcx.clutchagent", sender.state == NSOnState);
    
    // Arq has this functionality so I opened it in ida64, and it uses the LSSharedFileList APIs instead.
    // These have been deprecated, but since the latest version of Arq still uses them, perhaps they haven't found
    // a solution to this problem either. In any case, I know that LSSharedFileList still works for now.
    
    // I have included a "Copy Files" build phase that will copy a release build of ClutchAgent.app
    // into the Contents/Library/LoginItems dir of the build automatically.
    // Otherwise, this function WILL NOT WORK until ClutchAgent.app is placed in Contents/Library/LoginItems in the app bundle
    
    // The following was straight reverse-engineered from Arq in ida64
    
    // Ignore deprecated warnings
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    LSSharedFileListRef loginItemsListRef = LSSharedFileListCreate(CFAllocatorGetDefault(), kLSSharedFileListSessionLoginItems, nil);
    
    if (loginItemsListRef) {
        // output login items so other methods can add/remove items
        if (loginItemsList != nil) {
            *loginItemsList = loginItemsListRef;
        }
        
        UInt32 loginItemsSnapshotSeed;
        NSArray* loginItems = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItemsListRef, &loginItemsSnapshotSeed);
        
        NSURL* clutchAgentURL = [NSURL fileURLWithPath:[self clutchAgentPath]];
        
        for (int i = 0; i < loginItems.count; i++) {
            LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItems objectAtIndex:i];
            CFURLRef itemURL;
            FSRef itemFSRef;
            OSStatus status = LSSharedFileListItemResolve(itemRef, kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes, &itemURL, &itemFSRef);
            if (status == 0) {
                // resolved item
                NSURL* itemNSURL = (__bridge NSURL *)itemURL;
                if ([itemNSURL.absoluteString isEqualToString:clutchAgentURL.absoluteString]) {
                    // matched; output clutch agent login item
                    *clutchAgentLoginItem = itemRef;
                    break;
                }
            }
        }
    }
#pragma GCC diagnostic pop
}

- (NSString *)clutchAgentPath {
    NSArray *pathComponents = [[[NSBundle mainBundle]bundlePath]pathComponents];
    NSString *path = [NSString pathWithComponents:[pathComponents arrayByAddingObjectsFromArray:@[ @"Contents", @"Library", @"LoginItems", @"Clutch Agent.app" ]]];
    return path;
}

- (void)launchClutchAgent {
    // This causes the main window to be unable to get focus if called from -viewDidLoad
    
    // only launch Clutch Agent if it isn't already running
    // otherwise, the main window will lose focus, and sometimes it cannot be
    // re-selected without restarting the app! (possible macOS bug?)
    if ([[NSRunningApplication runningApplicationsWithBundleIdentifier:kClutchAgentBundleID]count] == 0) {
        [[NSWorkspace sharedWorkspace]launchApplication:[self clutchAgentPath]];
    }
}

- (NSString *)humanReadableNameFromInterface:(ClutchInterface *)interface {
    return [NSString stringWithFormat:@"%@ - %@", interface.name, interface.address];
}

- (void)updateInterfaceDropdown {
    // select bound interface
    ClutchInterface* bindInterface = [self.clutch getBindInterface];
    
    if (bindInterface) {
        // update ui
        self.interfaceDropdown.stringValue = bindInterface.name;
        self.interfaceDropdown.enabled = NO;
        self.bindButton.title = @"Unbind Transmission from Interface";
        
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Binding to %@", self.interfaceDropdown.stringValue];
        
        // different shade of green for Dark Mode (looks better)
        // self.statusLabel.textColor = [NSColor colorWithRed:0 green:0.4 blue:0 alpha:1];
        self.statusLabel.textColor = [NSColor colorNamed:@"greenColor"];
    }
    else {
        // update interfaces
        [self.interfaces setArray:[self.clutch getInterfaces]];
        
        // populate list of interface names with info
        NSMutableArray* interfaceNames = [[NSMutableArray alloc]init];
        for (ClutchInterface* interface in self.interfaces) {
            NSString* name = [self humanReadableNameFromInterface:interface];
            NSLog(@"adding %@...", name);
            [interfaceNames addObject:name];
        }
        
        // refresh interface dropdown
        [self.interfaceDropdown removeAllItems];
        [self.interfaceDropdown addItemsWithObjectValues:interfaceNames];
        
        // load the last text that was in the text field
        NSString* savedText = [[self.clutch clutchGroupDefaults]objectForKey:kSavedTextKey];
        if (savedText) {
            self.interfaceDropdown.stringValue = savedText;
        }
        
        // update ui
        self.interfaceDropdown.enabled = YES;
        self.bindButton.title = @"Bind Transmission to Interface";
        
        self.statusLabel.stringValue = @"Not Binding";
        
        // using [NSColor labelColor] will automatically set the default text color for light/dark mode
        // (black for light mode, white for dark mode)
        self.statusLabel.textColor = [NSColor labelColor];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    
    // AutoLayout debug visualizer
//    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
//    [defaults setBool:YES forKey:@"NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints"];
//    [defaults synchronize];
    
    // initialize to NO
    self.hasPermissions = NO;
    self.justCheckedGracefulBox = NO;
    self.justFinishedPermissionsVC = NO;
    
    [[NSNotificationCenter defaultCenter]addObserverForName:kTransmissionQuitNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"got transmission-quit callback; stopping loading animation");
        
        // transmission quit; if progress indicator is showing and button is hiding, invert both of those states
        [self.progressIndicator stopAnimation:nil];
        self.bindButton.enabled = YES;
        self.statusLabel.hidden = NO;
        
        // update bind button text and currently-bound interface info
        [self updateInterfaceDropdown];
    }];
    
    self.interfaces = [[NSMutableArray alloc]init];
    
    // depends on self.clutch, so declare after self.clutch
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:kClutchAgentPermissionsTrueNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        self.hasPermissions = YES;
        self.gracefullyRestartTransmissionButton.enabled = YES;
        
        if (self.justCheckedGracefulBox) {
            self.justCheckedGracefulBox = NO;
            
            // the user wants to enable "graceful restart" and we have permissions;
            // enable and save the user's settings
            [self.clutch setShouldRestartGracefully:YES];
        } else if (self.justFinishedPermissionsVC) {
            self.justFinishedPermissionsVC = NO;
            
            // because the permissions VC was just dismissed, this notification means that we didn't have permissions before,
            // that the user intended to enable "graceful restart" (by checking the box that showed the permissions VC),
            // and that we now have permissions; because of this, enable "graceful restart" and save the user's settings
            [self.clutch setShouldRestartGracefully:YES];
            self.gracefullyRestartTransmissionButton.state = NSControlStateValueOn;
        } else {
            // initial permissions check when Clutch launches
            // or re-check of permissions if the user has "graceful restart" enabled
            //
            // at this point, we know we have permissions, but only show the box as checked if "restart gracefully"
            // is actually enabled by the user
            self.gracefullyRestartTransmissionButton.state = [self.clutch shouldRestartGracefully] ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }];
    [center addObserverForName:kClutchAgentPermissionsFalseNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        self.hasPermissions = NO;
        self.gracefullyRestartTransmissionButton.enabled = YES;
        self.gracefullyRestartTransmissionButton.state = NSControlStateValueOff;
        
        if (self.justCheckedGracefulBox) {
            // in this case, don't set self.justCheckedGracefulBox to NO until
            // we get the kUserFinishedPermissionsVCNotificationName;
            // that way, we will know whether the permissions VC was dismissed
            // after the user clicked the help button, or whether it was dismissed
            // after the user tried to check the "graceful restart" box;
            // only in the latter case should Clutch enable "graceful restart",
            // because in the former case the user isn't signaling his or her intention
            // to actually enable "graceful restart"; they just clicked the help button
            
            // the user wants to enable "graceful restart" and we do NOT have permissions;
            // show the permissions view controller, and if we have permissions when the user dismisses it,
            // enable and save the user's settings (see "permissions true" notification above)

            // disable the checkbox until we re-check the permissions after the
            // PermissionsViewController is dismissed
            self.gracefullyRestartTransmissionButton.enabled = NO;
            
            [self showPermissionsViewController];
        } else if (self.justFinishedPermissionsVC) {
            self.justFinishedPermissionsVC = NO;
            
            // because the permissions VC was just dismissed, this notification means that we didn't have permissions before,
            // that the user intended to enable "graceful restart" (by checking the box that showed the permissions VC),
            // and that we still do NOT have permissions; do nothing in this case
            
        } else {
            // initial permissions check when Clutch launches
            // or re-check of permissions if the user has "graceful restart" enabled
            //
            // since we don't have permissions, set "should restart gracefully" to NO in case it was previously set to YES.
            // it can be re-enabled by:
            //
            // (a) if the user enables permissions manually and then checks the box, Clutch
            // will recognize the permissions and let them check the box.
            //
            // (b) if the user checks the box without permissions enabled, the PermissionsViewController
            // will be shown, and if the app has permissions when the user clicks "OK" to dismiss it,
            // the box will be checked and "should restart gracefully" will be set to YES.
            [self.clutch setShouldRestartGracefully:NO];
        }
    }];
    [center addObserverForName:kUserFinishedPermissionsVCNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        
        // if the user just clicked the help button and then dismissed the permissions VC,
        // check to make sure they didn't DISABLE permissions if the box was enabled before,
        // but don't automatically check the box if it was disabled before
        
        // check permissions if:
        // (a) the user tried to check the box and just closed the permissions VC
        // (b) the user already had permissions enabled, clicked the help button, and
        //     just closed the permissions VC (just in case they DISABLED permissions)
        
        if (self.justCheckedGracefulBox) {
            self.justCheckedGracefulBox = NO;
            
            // this notification is sent by PermissionsViewController when the user dismisses it;
            // it is to re-check the permissions, as the user may have granted them now,
            // and if they did, enable "graceful restart," since by checking the box the user
            // intended to enable it (see kClutchAgentPermissionsTrueNotificationName above)
            self.justFinishedPermissionsVC = YES;
            [self checkPermissionsWithPrompt:NO];
        } else if ([self.clutch shouldRestartGracefully]) {
            [self checkPermissionsWithPrompt:NO];
        }
    }];
    
    // Checking the permissions calls a test AppleScript that selects the Clutch window,
    // causing a brief graphical glitch. Since this is unnecessary if the user doesn't have the
    // "reset gracefully" option enabled, only check permissions (thereby temporarily disabling
    // the checkbox here) if they have that option enabled
    if ([self.clutch shouldRestartGracefully]) {
        // this checkbox will be re-enabled after Clutch determines whether it has permissions
        self.gracefullyRestartTransmissionButton.state = NSControlStateValueOn;
        self.gracefullyRestartTransmissionButton.enabled = NO;
    } else {
        self.gracefullyRestartTransmissionButton.state = NSControlStateValueOff;
        self.gracefullyRestartTransmissionButton.enabled = YES;
    }
    
    [self updateInterfaceDropdown];
    
    // update "open clutch agent at login" checkbox
    LSSharedFileListItemRef clutchAgentLoginItem = nil;
    LSSharedFileListRef loginItemsList = nil;
    [self getClutchAgentLoginItem:&clutchAgentLoginItem loginItemsList:&loginItemsList];
    self.openClutchAgentAtLoginButton.state = (clutchAgentLoginItem ? NSOnState : NSOffState);
    CFRelease(loginItemsList); // don't forget to release memory
    
    // launch agent if it isn't running
    [self launchClutchAgent];
}

- (void)showPermissionsViewController {
    // the "hasPermissions" variable will be updated after the permissions view controller is dismissed,
    // on -viewDidAppear
    PermissionsViewController* pvc = [self.storyboard instantiateControllerWithIdentifier:@"permissionsViewController"];
    [self presentViewControllerAsSheet:pvc];
}

// function for -performSelector:withObject:afterDelay: which can't pass a
// primitive boolean value as an object argument
- (void)checkPermissionsWithNoPrompt {
    [self checkPermissionsWithPrompt:NO];
}

- (void)checkPermissionsWithPrompt:(BOOL)prompt {
    NSLog(@"checking permissions; prompt: %@", prompt ? @"YES" : @"NO");
    
    // the prompt is necessary to add Clutch Agent to the Automation permissions list;
    // so pass prompt=YES when the user can reasonably expect it
    // in our case, this is when the user checks the "restart gracefully" checkbox,
    // which is perfect because they will HAVE to check that checkbox before they
    // can enable the "restart gracefully" feature, and then they will be instructed to
    // check the box, which they will then look for even if they previously checked
    // and didn't see before
    
    if (prompt) {
        [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-agent-transmission:testAppleScriptWithPrompt"]];
    } else {
        [[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"clutch-agent-transmission:testAppleScript"]];
    }
}

- (void)viewDidAppear {
    [super viewDidAppear];
    
    // show help if this is the first launch
    // this is done in -viewDidAppear because the window needs to exist first
    
    // Check whether Clutch Agent has the required permissions to restart Transmission gracefully
    // The test script uses the Clutch window so we need to add a delay to make sure the window is available
    
    // Checking the permissions calls a test AppleScript that selects the Clutch window,
    // causing a brief graphical glitch. Since this is unnecessary if the user doesn't have the
    // "reset gracefully" option enabled, only check permissions if they have that option enabled
    if ([self.clutch shouldRestartGracefully]) {
        [self performSelector:@selector(checkPermissionsWithNoPrompt) withObject:nil afterDelay:1];
    }
    
    NSUserDefaults* defaults = [self.clutch clutchGroupDefaults];
    if (![defaults boolForKey:kHelpShownKey]) {
        [self showHelp];
        
        [defaults setBool:YES forKey:kHelpShownKey];
        [defaults synchronize];
    }
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (void)dealloc {
    // remove self as an observer for transmission-quit notifications
    // and permissions notifications
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}

@end
