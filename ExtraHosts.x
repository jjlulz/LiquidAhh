#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import "LGSupport.h"
#import "LGGlass.h"

static NSHashTable<UIView *> *sExtraHosts;
static BOOL sExtraBusy;

static void LGExtraRun(UIView *host, void (*work)(UIView *)) {
    if (!host || sExtraBusy) return;
    if (!sExtraHosts) sExtraHosts = [NSHashTable weakObjectsHashTable];
    [sExtraHosts addObject:host];
    if (!LGActive()) return;
    sExtraBusy = YES;
    @try {
        work(host);
    } @catch (NSException *exception) {
        LGLog(@"ExtraHosts exception in %@: %@ %@", NSStringFromClass(host.class), exception.name, exception.reason);
    } @finally {
        sExtraBusy = NO;
    }
}

static CGFloat LGExtraRadius(UIView *view, CGFloat fallback) {
    CGFloat radius = view.layer.cornerRadius;
    return radius > 0.5 ? radius : fallback;
}

#pragma mark - 1. Control Center (Modules & Sliders)

static void LGSyncControlCenterModule(UIView *host) {
    UIView *background = LGFindView(host, @[@"backgroundView", @"materialView", @"contentContainerView"]);
    if (!background) {
        for (UIView *sub in host.subviews) {
            if ([NSStringFromClass(sub.class) containsString:@"Material"] ||
                [NSStringFromClass(sub.class) containsString:@"Background"]) {
                background = sub;
                break;
            }
        }
    }
    if (!host.window) { LGRemoveGlass(background); return; }
    LGDumpOnce(host, @"CCUIContentModuleContainerView");
    if (!background) return;

    CGFloat w = CGRectGetWidth(background.bounds);
    CGFloat h = CGRectGetHeight(background.bounds);
    if (w < 20.0 || h < 20.0) return;

    // Pill radius for 1x1 toggles or sliders, continuous rounded rect for larger modules
    CGFloat fallbackRadius = (MAX(w, h) <= MIN(w, h) * 1.25) ? (MIN(w, h) * 0.5) : 19.0;
    LGInstallGlass(background, @"ControlCenter", LGExtraRadius(background, fallbackRadius));
}

%group ControlCenter
%hook CCUIContentModuleContainerView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncControlCenterModule); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncControlCenterModule); }
%end
%end

#pragma mark - 2. Volume HUD (iOS 12 Centered HUD)

static void LGSyncVolumeHUD(UIView *host) {
    UIView *background = LGFindView(host, @[@"backdropView", @"backgroundView", @"materialView"]);
    if (!background) {
        for (UIView *sub in host.subviews) {
            if ([sub isKindOfClass:UIVisualEffectView.class] ||
                [NSStringFromClass(sub.class) containsString:@"Backdrop"] ||
                [NSStringFromClass(sub.class) containsString:@"Material"]) {
                background = sub;
                break;
            }
        }
    }
    if (!host.window) { LGRemoveGlass(background ?: host); return; }
    LGDumpOnce(host, @"SBVolumeHUDView");
    UIView *target = background ?: host;
    LGInstallGlass(target, @"VolumeHUD", LGExtraRadius(target, 20.0));
}

%group VolumeHUD
%hook SBVolumeHUDView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncVolumeHUD); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncVolumeHUD); }
%end
%end

#pragma mark - 3. Passcode Keypad (iOS 12 TPNumberPadButton)

static void LGSyncPasscodeButton(UIView *host) {
    // TPNumberPadButton on iOS 12 uses _revealingRingView or a circular subview
    UIView *ring = LGFindView(host, @[@"revealingRingView", @"circleView", @"backgroundView"]);
    if (!ring) {
        for (UIView *sub in host.subviews) {
            CGFloat w = CGRectGetWidth(sub.bounds);
            CGFloat h = CGRectGetHeight(sub.bounds);
            if (w >= 40.0 && fabs(w - h) < 2.0) {
                ring = sub;
                break;
            }
        }
    }
    if (!host.window) { LGRemoveGlass(ring); return; }
    LGDumpOnce(host, @"TPNumberPadButton");
    if (!ring) return;

    CGFloat r = MIN(CGRectGetWidth(ring.bounds), CGRectGetHeight(ring.bounds)) * 0.5;
    ring.layer.cornerRadius = r;
    ring.layer.masksToBounds = YES;
    LGInstallGlass(ring, @"Passcode", r);
}

%group Passcode
%hook TPNumberPadButton
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncPasscodeButton); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncPasscodeButton); }
%end
%end

#pragma mark - 4. Alerts (SpringBoard UIAlertController)

static UIView *LGFindAlertBackdrop(UIView *root) {
    for (UIView *sub in root.subviews) {
        NSString *cls = NSStringFromClass(sub.class);
        if ([cls containsString:@"Backdrop"] || [cls containsString:@"VisualEffect"] ||
            [cls hasPrefix:@"_UIAlertControllerPhoneTVMacView"]) {
            if (CGRectGetWidth(sub.bounds) > 100.0 && CGRectGetHeight(sub.bounds) > 50.0) {
                return sub;
            }
        }
        UIView *found = LGFindAlertBackdrop(sub);
        if (found) return found;
    }
    return nil;
}

static void LGSyncAlertView(UIView *host) {
    UIView *backdrop = LGFindAlertBackdrop(host);
    if (!host.window) { LGRemoveGlass(backdrop); return; }
    LGDumpOnce(host, @"_UIAlertControllerView");
    if (!backdrop) return;
    backdrop.layer.cornerRadius = 16.0;
    backdrop.layer.masksToBounds = YES;
    LGInstallGlass(backdrop, @"Alerts", 16.0);
}

%group Alerts
%hook _UIAlertControllerView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncAlertView); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncAlertView); }
%end
%end

#pragma mark - 5. Keyboard Backdrop (UIKBBackdropView in SpringBoard)

static void LGSyncKeyboardBackdrop(UIView *host) {
    if (!host.window) { LGRemoveGlass(host); return; }
    // Only apply to remote/system keyboard windows
    if (![NSStringFromClass(host.window.class) containsString:@"Keyboard"]) return;
    LGDumpOnce(host, @"UIKBBackdropView");
    LGInstallGlass(host, @"Keyboard", 0.0);
}

%group Keyboard
%hook UIKBBackdropView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncKeyboardBackdrop); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncKeyboardBackdrop); }
%end
%end

#pragma mark - Init

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 12) return;
        if (!LGPrefBool(@"Global.Enabled", YES)) return;

        if (NSClassFromString(@"CCUIContentModuleContainerView")) { %init(ControlCenter); }
        if (NSClassFromString(@"SBVolumeHUDView"))                { %init(VolumeHUD); }
        if (NSClassFromString(@"TPNumberPadButton"))              { %init(Passcode); }
        if (NSClassFromString(@"_UIAlertControllerView"))         { %init(Alerts); }
        if (NSClassFromString(@"UIKBBackdropView"))               { %init(Keyboard); }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            for (UIView *host in sExtraHosts.allObjects)
                if (host.window) [host setNeedsLayout];
        });
    }
}
