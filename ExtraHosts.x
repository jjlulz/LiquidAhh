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

#pragma mark - 1. Control Center Modules

static void LGSyncControlCenterModule(UIView *host) {
    UIView *background = LGFindView(host, @[@"backgroundView", @"materialView"]);
    if (!host.window) { LGRemoveGlass(background); return; }
    if (!background) return;

    CGFloat w = CGRectGetWidth(background.bounds);
    CGFloat h = CGRectGetHeight(background.bounds);
    if (w < 36.0 || h < 36.0) return;

    CGFloat fallbackRadius = (MAX(w, h) <= MIN(w, h) * 1.25) ? (MIN(w, h) * 0.5) : 19.0;
    LGInstallGlass(background, @"ControlCenter", LGExtraRadius(background, fallbackRadius));
}

%group ControlCenter
%hook CCUIContentModuleContainerView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncControlCenterModule); }
%end
%end

#pragma mark - 2. Volume HUD (iOS 12 Centered HUD)

static void LGSyncVolumeHUD(UIView *host) {
    UIView *background = LGFindView(host, @[@"backdropView", @"backgroundView"]);
    if (!host.window) { LGRemoveGlass(background); return; }
    if (!background) return;
    LGInstallGlass(background, @"VolumeHUD", LGExtraRadius(background, 20.0));
}

%group VolumeHUD
%hook SBVolumeHUDView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncVolumeHUD); }
%end
%end

#pragma mark - 3. Passcode Keypad (Safe Chill Tint, No Subview Injection Crash)

static void LGSyncPasscodeKeypad(UIView *host) {
    if (!LGHostEnabled(@"Passcode")) return;
    if (!host.window) return;
    // Safely style the keypad buttons' existing background alpha/border without inserting views into TPRevealingRingView
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"NumberPadButton"]) {
            sub.layer.cornerRadius = MIN(CGRectGetWidth(sub.bounds), CGRectGetHeight(sub.bounds)) * 0.5;
            sub.layer.borderWidth = 0.75;
            sub.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
            sub.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        }
    }
}

%group Passcode
%hook TPNumberPad
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncPasscodeKeypad); }
%end
%end

#pragma mark - 4. Alerts (Safe viewDidAppear Hook)

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

#pragma mark - 5. Keyboard Backdrop (One-Shot on Window Attach)

static void LGSyncKeyboardBackdrop(UIView *host) {
    if (!host.window) { LGRemoveGlass(host); return; }
    if (![NSStringFromClass(host.window.class) containsString:@"Keyboard"]) return;
    if (CGRectGetHeight(host.bounds) < 60.0) return;
    LGInstallGlass(host, @"Keyboard", 0.0);
}

%group Keyboard
%hook UIKBBackdropView
- (void)didMoveToWindow { %orig; LGExtraRun((UIView *)self, LGSyncKeyboardBackdrop); }
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
        if (NSClassFromString(@"TPNumberPad"))                    { %init(Passcode); }
        if (NSClassFromString(@"UIAlertController"))              { %init(Alerts); }
        if (NSClassFromString(@"UIKBBackdropView"))               { %init(Keyboard); }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            for (UIView *host in sExtraHosts.allObjects)
                if (host.window) [host setNeedsLayout];
        });
    }
}

