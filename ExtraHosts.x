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

#pragma mark - 1. Control Center (MTMaterialView inside CCUIControlCenterWindow)

static void LGSyncControlCenterMaterial(UIView *mat) {
    if (!mat.window) { LGRemoveGlass(mat); return; }
    if (![NSStringFromClass(mat.window.class) containsString:@"ControlCenter"]) return;
    // Skip the fullscreen background blur (width >= 300) and tiny sliders
    CGFloat w = CGRectGetWidth(mat.bounds);
    CGFloat h = CGRectGetHeight(mat.bounds);
    if (w < 30.0 || h < 30.0 || w >= 300.0) return;

    CGFloat r = mat.layer.cornerRadius > 0.5 ? mat.layer.cornerRadius : ((MAX(w, h) <= MIN(w, h) * 1.25) ? MIN(w, h) * 0.5 : 19.0);
    LGInstallGlass(mat, @"ControlCenter", r);
}

%group ControlCenter
%hook MTMaterialView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncControlCenterMaterial); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncControlCenterMaterial); }
%end
%end

#pragma mark - 2. Volume HUD (_UIBackdropView inside SBVolumeHUDView)

static void LGSyncVolumeHUD(UIView *host) {
    UIView *backdrop = nil;
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_UIBackdropView"]) {
            backdrop = sub;
            break;
        }
    }
    if (!host.window) { LGRemoveGlass(backdrop); return; }
    if (!backdrop || CGRectIsEmpty(backdrop.bounds)) return;
    CGFloat r = host.layer.cornerRadius > 0.5 ? host.layer.cornerRadius : 18.0;
    backdrop.layer.cornerRadius = r;
    backdrop.layer.masksToBounds = YES;
    LGInstallGlass(backdrop, @"VolumeHUD", r);
}

%group VolumeHUD
%hook SBVolumeHUDView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncVolumeHUD); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncVolumeHUD); }
%end
%end

#pragma mark - 3. Passcode Keypad (Exact 75x75 Circle UIView inside SBPasscodeNumberPadButton)

static UIView *LGFindPasscodeCircle(UIView *button) {
    for (UIView *sub in button.subviews) {
        if ([sub isMemberOfClass:UIView.class]) {
            CGFloat w = CGRectGetWidth(sub.bounds);
            CGFloat h = CGRectGetHeight(sub.bounds);
            if (w >= 50.0 && fabs(w - h) < 2.0) {
                return sub;
            }
        }
    }
    return nil;
}

static void LGSyncPasscodeButton(UIView *button) {
    UIView *circle = LGFindPasscodeCircle(button);
    if (!button.window) { LGRemoveGlass(circle); return; }
    if (!circle) return;
    circle.alpha = 1.0; // stock alpha is 0.15; bring to 1.0 so Metal glass is visible
    CGFloat r = MIN(CGRectGetWidth(circle.bounds), CGRectGetHeight(circle.bounds)) * 0.5;
    circle.layer.cornerRadius = r;
    circle.layer.masksToBounds = YES;
    LGInstallGlass(circle, @"Passcode", r);
}

%group Passcode
%hook SBPasscodeNumberPadButton
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

%group Alerts
%hook UIAlertController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!LGActive() || self.preferredStyle != UIAlertControllerStyleAlert) return;
    @try {
        UIView *backdrop = LGFindAlertBackdrop(self.view);
        if (backdrop) {
            backdrop.layer.cornerRadius = 18.0;
            backdrop.layer.masksToBounds = YES;
            LGInstallGlass(backdrop, @"Alerts", 18.0);
        }
    } @catch (NSException *e) {}
}
%end
%end

#pragma mark - 5. Keyboard Backdrop (UIKBBackdropView)

static void LGSyncKeyboardBackdrop(UIView *host) {
    if (!host.window) { LGRemoveGlass(host); return; }
    if (![NSStringFromClass(host.window.class) containsString:@"Keyboard"]) return;
    if (CGRectGetHeight(host.bounds) < 60.0) return;
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
        if (!LGGuardShouldLoad()) return;
        if (!LGPrefBool(@"Global.Enabled", YES)) return;
        if (!LGGlassSupported()) return;

        if (NSClassFromString(@"MTMaterialView"))            { %init(ControlCenter); }
        if (NSClassFromString(@"SBVolumeHUDView"))           { %init(VolumeHUD); }
        if (NSClassFromString(@"SBPasscodeNumberPadButton")) { %init(Passcode); }
        if (NSClassFromString(@"UIAlertController"))         { %init(Alerts); }
        if (NSClassFromString(@"UIKBBackdropView"))          { %init(Keyboard); }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            for (UIView *host in sExtraHosts.allObjects)
                if (host.window) [host setNeedsLayout];
        });
    }
}

