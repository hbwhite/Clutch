//
//  ViewController.m
//  Clutch
//
//  Created by Harrison White on 2/25/18.
//  Copyright © 2019 Harrison White. All rights reserved.
//
//  See LICENSE for licensing information
//

#import "ViewController.h"
#import "Clutch.h"
#import <ServiceManagement/ServiceManagement.h>

static NSString* kSavedTextKey        = @"Saved Text";
static NSString* kHelpShownKey        = @"Help Shown3";

@interface ViewController () <NSControlTextEditingDelegate>

@property (nonatomic, strong) IBOutlet NSComboBox* interfaceDropdown;
@property (nonatomic, strong) IBOutlet NSButton* bindButton;
@property (nonatomic, strong) IBOutlet NSTextField* statusLabel;
@property (nonatomic, strong) IBOutlet NSButton* openClutchAgentAtLoginButton;
@property (nonatomic, strong) NSMutableArray* interfaces;
@property (nonatomic, strong) Clutch* clutch;

@end

@implementation ViewController

- (IBAction)bindToInterfaceClicked:(id)sender {
    if ([self.clutch getBindInterface]) {
        NSLog(@"unbinding");
        [self.clutch unbindFromInterface];
    }
    else {
        NSLog(@"binding");
        [self.clutch bindToInterfaceWithName:self.interfaceDropdown.stringValue];
    }
    
    [self saveText];
    [self updateInterfaceDropdown];
}

- (IBAction)helpItemClicked:(id)sender {
    [self showHelp];
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
    NSString *path = [NSString pathWithComponents:[pathComponents arrayByAddingObjectsFromArray:@[ @"Contents", @"Library", @"LoginItems", @"ClutchAgent.app" ]]];
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
    
    self.interfaces = [[NSMutableArray alloc]init];
    self.clutch = [[Clutch alloc]init];
    
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

- (void)viewDidAppear {
    // show help if this is the first launch
    // this is done in -viewDidAppear because the window needs to exist first
    
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

@end
