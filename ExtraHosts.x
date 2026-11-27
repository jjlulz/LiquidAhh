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

#pragma mark - 1. Control Center (iOS 12 CCUIContentModuleContainerView)

static UIView *LGFindCCBackground(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    UIView *deepestContainer = nil;
    while (stack.count > 0) {
        UIView *cur = stack.firstObject;
        [stack removeObjectAtIndex:0];
        NSString *cls = NSStringFromClass(cur.class);
        if ([cls isEqualToString:@"_UIBackdropView"] || [cls isEqualToString:@"MTMaterialView"]) {
            return cur;
        }
        if (cur != root && CGRectGetWidth(cur.bounds) >= 50.0 && CGRectGetHeight(cur.bounds) >= 50.0) {
            deepestContainer = cur;
        }
        [stack addObjectsFromArray:cur.subviews];
    }
    return deepestContainer;
}

static void LGSyncControlCenterModule(UIView *host) {
    UIView *target = LGFindCCBackground(host);
    if (!host.window) { LGRemoveGlass(target); return; }
    if (!target) return;

    CGFloat w = CGRectGetWidth(target.bounds);
    CGFloat h = CGRectGetHeight(target.bounds);
    if (w < 40.0 || h < 40.0 || w >= 300.0) return;

    // 1x1 circular/pill tiles vs larger 2x1 / 2x2 rounded-rect modules
    CGFloat r = target.layer.cornerRadius > 0.5
        ? target.layer.cornerRadius
        : ((MAX(w, h) <= MIN(w, h) * 1.25) ? (MIN(w, h) * 0.5) : 19.0);

    target.layer.cornerRadius = r;
    target.layer.masksToBounds = YES;
    LGInstallGlass(target, @"ControlCenter", r);
}

%group ControlCenter
%hook CCUIContentModuleContainerView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncControlCenterModule); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncControlCenterModule); }
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

#pragma mark - 3. Passcode Keypad (Pure Liquid Glass)

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

    circle.backgroundColor = UIColor.clearColor;
    circle.alpha = 1.0;

    CGFloat r = MIN(CGRectGetWidth(circle.bounds), CGRectGetHeight(circle.bounds)) * 0.5;
    circle.layer.cornerRadius = r;
    circle.layer.masksToBounds = YES;
    LGInstallGlass(circle, @"Passcode", r);
}

%group Passcode
%hook SBPasscodeNumberPadButton
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncPasscodeButton); }
- (void)layoutSubviews  { %orig; LGExtraRun((UIView *)self, LGSyncPasscodeButton); }
- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    UIView *circle = LGFindPasscodeCircle((UIView *)self);
    if (circle && LGHostEnabled(@"Passcode")) {
        circle.backgroundColor = UIColor.clearColor;
        circle.alpha = 1.0;
    }
}
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

        if (NSClassFromString(@"CCUIContentModuleContainerView")) { %init(ControlCenter); }
        if (NSClassFromString(@"SBVolumeHUDView"))                { %init(VolumeHUD); }
        if (NSClassFromString(@"SBPasscodeNumberPadButton"))      { %init(Passcode); }
        if (NSClassFromString(@"UIAlertController"))              { %init(Alerts); }
        if (NSClassFromString(@"UIKBBackdropView"))               { %init(Keyboard); }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            for (UIView *host in sExtraHosts.allObjects)
                if (host.window) [host setNeedsLayout];
        });
    }
}
