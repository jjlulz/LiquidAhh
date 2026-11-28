// Liquid (Gl)ass 12 - iOS 12 port of dylv's Liquid (Gl)ass (CC BY-NC 4.0).
// SpringBoard only. Hosts: dock, folder icons, open folder, banners (+ optional notification platters).
//
// Safety rules for this file:
//  * nothing is touched for the first few seconds after SpringBoard starts
//  * every hook only runs its work inside @try/@catch and never re-enters itself
//  * hooks are only installed for classes that really exist on this iOS version
//  * stock views are only hidden (never removed) and are restored when the host leaves the screen
//  * crash-loop guard + /var/mobile/liquidass12.disabled kill switch (see LGSupport.m)

#import <UIKit/UIKit.h>
#import <math.h>
#import "LGSupport.h"
#import "LGGlass.h"

void LGInitHosts12(void);       // Hosts12.x
void LGHosts12Activate(void);

static NSHashTable<UIView *> *sHosts;
static BOOL sBusy;

static void LGRun(UIView *host, void (*work)(UIView *)) {
    if (!host || sBusy) return;
    if (!sHosts) sHosts = [NSHashTable weakObjectsHashTable];
    [sHosts addObject:host];
    if (!LGActive()) return;
    sBusy = YES;
    @try {
        work(host);
    } @catch (NSException *exception) {
        LGLog(@"exception in %@: %@ %@", NSStringFromClass(host.class), exception.name, exception.reason);
    } @finally {
        sBusy = NO;
    }
}

static CGFloat LGRadius(UIView *view, CGFloat fallback) {
    CGFloat radius = view.layer.cornerRadius;
    return radius > 0.5 ? radius : fallback;
}

#pragma mark - dock

static void LGSyncDock(UIView *host) {
    UIView *background = LGFindView(host, @[@"backgroundView", @"backgroundBlurView"]);
    if (!host.window) { LGRemoveGlass(background); return; }
    LGDumpOnce(host, @"SBDockView");
    if (!background) { LGLog(@"dock: no background view found"); return; }
    LGInstallGlass(background, @"Dock", LGRadius(background, 0.0));
}

%group Dock
%hook SBDockView
- (void)didMoveToWindow { %orig; LGRun((UIView *)self, LGSyncDock); }
- (void)layoutSubviews  { %orig; LGRun((UIView *)self, LGSyncDock); }
%end
%end

#pragma mark - folder icon (home screen)

static void LGSyncFolderIcon(UIView *host) {
    UIView *background = LGFindView(host, @[@"backgroundView"]);
    if (!host.window) { LGRemoveGlass(background); return; }
    LGDumpOnce(host, @"SBFolderIconImageView");
    if (!background) { LGLog(@"folder icon: no background view found"); return; }
    CGFloat side = MIN(CGRectGetWidth(background.bounds), CGRectGetHeight(background.bounds));
    LGInstallGlass(background, @"FolderIcon", LGRadius(background, side * 0.2237));
}

%group FolderIcon
%hook SBFolderIconImageView
- (void)didMoveToWindow { %orig; LGRun((UIView *)self, LGSyncFolderIcon); }
- (void)layoutSubviews  { %orig; LGRun((UIView *)self, LGSyncFolderIcon); }
%end
%end

#pragma mark - open folder

static void LGSyncOpenFolder(UIView *host) {
    UIView *stock = LGFindView(host, @[@"blurView", @"backgroundView"]) ?: host;
    if (!host.window) { LGRemoveGlass(stock); return; }
    LGDumpOnce(host, @"SBFolderBackgroundView");
    LGInstallGlass(stock, @"OpenFolder", LGRadius(stock, LGRadius(host, 0.0)));
}

%group OpenFolder
%hook SBFolderBackgroundView
- (void)didMoveToWindow { %orig; LGRun((UIView *)self, LGSyncOpenFolder); }
- (void)layoutSubviews  { %orig; LGRun((UIView *)self, LGSyncOpenFolder); }
%end
%end

#pragma mark - banners / notification platters

static BOOL LGIsBanner(UIView *view) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
        if ([NSStringFromClass(ancestor.class) rangeOfString:@"Banner"].location != NSNotFound) return YES;
    return [NSStringFromClass(view.window.class) rangeOfString:@"Banner"].location != NSNotFound;
}

static void LGSyncPlatter(UIView *host) {
    UIView *background = LGFindView(host, @[@"backgroundMaterialView", @"backgroundView", @"materialView"]);
    if (!host.window) { LGRemoveGlass(background); return; }
    BOOL banner = LGIsBanner(host);
    LGDumpOnce(host, banner ? @"PLPlatterView(banner)" : @"PLPlatterView(list)");
    if (!background) { LGLog(@"platter: no background view found"); return; }
    LGInstallGlass(background, banner ? @"Banner" : @"Notification",
                   LGRadius(background, LGRadius(host, 13.0)));
}

%group Platter
%hook PLPlatterView
- (void)didMoveToWindow { %orig; LGRun((UIView *)self, LGSyncPlatter); }
- (void)layoutSubviews  { %orig; LGRun((UIView *)self, LGSyncPlatter); }
%end
%end

#pragma mark - init

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 12) {
            LGLog(@"not iOS 12; not loading");
            return;
        }
        if (!LGGuardShouldLoad()) return;
        LGGuardCheckMetalMarker();
        if (!LGPrefBool(@"Global.Enabled", YES)) return;
        if (!LGGlassSupported()) return;

        if (NSClassFromString(@"SBDockView"))             { %init(Dock); }
        if (NSClassFromString(@"SBFolderIconImageView"))  { %init(FolderIcon); }
        if (NSClassFromString(@"SBFolderBackgroundView")) { %init(OpenFolder); }
        if (NSClassFromString(@"PLPlatterView"))          { %init(Platter); }
        LGInitHosts12();   // control center, passcode keypad, volume HUD
        LGLog(@"loaded on iOS %@; waiting to activate",
              NSProcessInfo.processInfo.operatingSystemVersionString);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            LGMetalPrepare();   // loads LiquidGlassKit; falls back to the blur renderer if anything is off
            LGSetActive(YES);
            LGLog(@"active");
            for (UIView *host in sHosts.allObjects)
                if (host.window) [host setNeedsLayout];   // re-enter the hooks, which now do real work
            LGHosts12Activate();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ LGMetalMarkerClear(); });   // Metal survived its first seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ LGGuardMarkStable(); });
    }
}
