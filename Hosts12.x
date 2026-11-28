// More hosts for the iOS 12 port: Control Center modules, lock screen keypad, volume HUD.
// (The original's iOS 14+ versions hook CAFilter/CALayer globally and rely on iOS 14+ classes;
// these are small, conservative replacements on the same safe glass layer.)
//
// Every class is looked up at runtime and only hooked if it exists on this iOS version.
// Where the iOS 12 view structure is not known, the first time a host is seen its view tree is
// written to /var/mobile/liquidass12-debug.txt so it can be retargeted.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "LGSupport.h"
#import "LGGlass.h"

static NSHashTable<UIView *> *sH12Hosts;
static BOOL sH12Busy;

static void H12Run(UIView *host, void (*work)(UIView *)) {
    if (!host || sH12Busy) return;
    if (!sH12Hosts) sH12Hosts = [NSHashTable weakObjectsHashTable];
    [sH12Hosts addObject:host];
    if (!LGActive()) return;
    sH12Busy = YES;
    @try {
        work(host);
    } @catch (NSException *exception) {
        LGLog(@"exception in %@: %@ %@", NSStringFromClass(host.class), exception.name, exception.reason);
    } @finally {
        sH12Busy = NO;
    }
}

static CGFloat H12Radius(UIView *view, CGFloat fallback) {
    CGFloat radius = view.layer.cornerRadius;
    return radius > 0.5 ? radius : fallback;
}

static BOOL H12HasAncestor(UIView *view, NSString *needle) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview)
        if ([NSStringFromClass(ancestor.class) rangeOfString:needle].location != NSNotFound) return YES;
    return NO;
}

#pragma mark - Control Center modules

static void H12SyncCCMaterial(UIView *material) {
    BOOL candidate = material.window != nil
        && [NSStringFromClass(material.class) isEqualToString:@"MTMaterialView"]
        && H12HasAncestor(material, @"CCUIContentModule")
        && !H12HasAncestor(material, @"Slider")          // keep slider fills intact
        && CGRectGetWidth(material.bounds) >= 40.0 && CGRectGetHeight(material.bounds) >= 40.0;
    if (!candidate) { LGRemoveGlass(material); return; }
    LGDumpOnce(material, @"CC module material");
    CGFloat side = MIN(CGRectGetWidth(material.bounds), CGRectGetHeight(material.bounds));
    LGInstallGlass(material, @"ControlCenter", H12Radius(material, H12Radius(material.superview, side * 0.22)));
}

%group H12CC
%hook MTMaterialView
- (void)didMoveToWindow { %orig; H12Run((UIView *)self, H12SyncCCMaterial); }
- (void)layoutSubviews  { %orig; H12Run((UIView *)self, H12SyncCCMaterial); }
%end
%end

#pragma mark - lock screen passcode keypad

static void *kH12PassBgKey   = &kH12PassBgKey;
static void *kH12PassTintKey = &kH12PassTintKey;

// the round fill view inside a keypad button (ivar names first, then a shape heuristic)
static UIView *H12PasscodeCircle(UIView *button) {
    UIView *named = LGFindView(button, @[@"circleView", @"backgroundView", @"fillView"]);
    if (named && CGRectGetWidth(named.bounds) >= 40.0) return named;
    UIView *best = nil;
    CGFloat bestScore = CGFLOAT_MAX;
    for (UIView *sub in button.subviews) {
        if (![NSStringFromClass(sub.class) isEqualToString:@"UIView"]) continue;
        CGFloat w = CGRectGetWidth(sub.bounds), h = CGRectGetHeight(sub.bounds);
        if (w < 40.0 || h < 40.0) continue;
        CGFloat score = fabs(w - h) + fabs(sub.layer.cornerRadius - MIN(w, h) * 0.5) + sub.subviews.count * 50.0;
        if (score < bestScore) { best = sub; bestScore = score; }
    }
    return best;
}

static void H12RestorePasscodeCircle(UIView *host) {
    id color = objc_getAssociatedObject(host, kH12PassBgKey);
    if (color) host.backgroundColor = (color == NSNull.null) ? nil : color;
    objc_setAssociatedObject(host, kH12PassBgKey, nil, OBJC_ASSOCIATION_ASSIGN);
    host.transform = CGAffineTransformIdentity;
}

static void H12SyncPasscodeButton(UIView *button) {
    UIView *host = H12PasscodeCircle(button);
    if (!host) {
        static BOOL logged;
        if (!logged && button.window) { logged = YES; LGDumpOnce(button, @"passcode button (no circle found)"); }
        return;
    }
    if (!button.window) { LGRemoveGlass(host); H12RestorePasscodeCircle(host); return; }
    LGDumpOnce(button, @"passcode button");

    if (!objc_getAssociatedObject(host, kH12PassBgKey))
        objc_setAssociatedObject(host, kH12PassBgKey, host.backgroundColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat radius = MIN(CGRectGetWidth(host.bounds), CGRectGetHeight(host.bounds)) * 0.5;
    host.backgroundColor = UIColor.clearColor;     // the stock fill would sit under the glass
    host.layer.cornerRadius = radius;

    UIView *glass = LGInstallGlass(host, @"Passcode", radius);
    if (!glass) { H12RestorePasscodeCircle(host); return; }

    // press tint lives inside the glass so the glass' "hide stock children" pass leaves it alone
    UIView *tint = objc_getAssociatedObject(host, kH12PassTintKey);
    if (!tint) {
        tint = [[UIView alloc] initWithFrame:glass.bounds];
        tint.userInteractionEnabled = NO;
        tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tint.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.12];
        objc_setAssociatedObject(host, kH12PassTintKey, tint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (tint.superview != glass) [glass addSubview:tint];
}

static void H12PasscodeHighlight(UIView *button, BOOL highlighted) {
    if (!LGActive()) return;
    @try {
        UIView *host = H12PasscodeCircle(button);
        UIView *tint = host ? objc_getAssociatedObject(host, kH12PassTintKey) : nil;
        if (!host || !tint) return;
        [UIView animateWithDuration:0.3 delay:0
             usingSpringWithDamping:0.65 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            host.transform = highlighted ? CGAffineTransformMakeScale(1.16, 1.16) : CGAffineTransformIdentity;
            tint.backgroundColor = highlighted ? [UIColor colorWithWhite:1.0 alpha:0.55]
                                               : [UIColor colorWithWhite:0.0 alpha:0.12];
        } completion:nil];
    } @catch (NSException *exception) {
        LGLog(@"passcode highlight exception: %@", exception.reason);
    }
}

%group H12PassSB
%hook SBPasscodeNumberPadButton
- (void)didMoveToWindow { %orig; H12Run((UIView *)self, H12SyncPasscodeButton); }
- (void)layoutSubviews  { %orig; H12Run((UIView *)self, H12SyncPasscodeButton); }
- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    H12Run((UIView *)self, H12SyncPasscodeButton);   // stock code may recolor the circle
    H12PasscodeHighlight((UIView *)self, highlighted);
}
%end
%end

%group H12PassTP
%hook TPNumberPadButton
- (void)didMoveToWindow { %orig; H12Run((UIView *)self, H12SyncPasscodeButton); }
- (void)layoutSubviews  { %orig; H12Run((UIView *)self, H12SyncPasscodeButton); }
- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    H12Run((UIView *)self, H12SyncPasscodeButton);
    H12PasscodeHighlight((UIView *)self, highlighted);
}
%end
%end

#pragma mark - volume HUD (iOS 12 style HUD, not the iOS 13+ side slider)

// the translucent blur inside the HUD: a known ivar name first, then any child that looks like a blur
static UIView *H12HUDBackground(UIView *host) {
    UIView *named = LGFindView(host, @[@"backgroundView", @"backdropView", @"blurView", @"materialView"]);
    if (named) return named;
    for (UIView *sub in host.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if ([name rangeOfString:@"Backdrop"].location != NSNotFound ||
            [name rangeOfString:@"Blur"].location != NSNotFound ||
            [name rangeOfString:@"Material"].location != NSNotFound ||
            [name rangeOfString:@"VisualEffect"].location != NSNotFound) return sub;
    }
    return nil;
}

static void H12SyncHUD(UIView *host) {
    UIView *background = H12HUDBackground(host);
    if (!host.window) { LGRemoveGlass(background); return; }
    LGDumpOnce(host, [@"HUD " stringByAppendingString:NSStringFromClass(host.class)]);
    if (!background) { LGLog(@"HUD %@: no background view found", NSStringFromClass(host.class)); return; }
    // legacy HUD is a ~155 pt rounded square: radius ~18 if the stock view does not say otherwise
    CGFloat side = MIN(CGRectGetWidth(background.bounds), CGRectGetHeight(background.bounds));
    CGFloat fallback = side > 100.0 ? 18.0 : side * 0.25;
    LGInstallGlass(background, @"VolumeHUD", H12Radius(background, H12Radius(host, fallback)));
}

%group H12HudA
%hook SBHUDView
- (void)didMoveToWindow { %orig; H12Run((UIView *)self, H12SyncHUD); }
- (void)layoutSubviews  { %orig; H12Run((UIView *)self, H12SyncHUD); }
%end
%end

%group H12HudB
%hook SBVolumeHUDView
- (void)didMoveToWindow { %orig; H12Run((UIView *)self, H12SyncHUD); }
- (void)layoutSubviews  { %orig; H12Run((UIView *)self, H12SyncHUD); }
%end
%end

#pragma mark - init / activation (called from Tweak.x)

void LGInitHosts12(void) {
    // Control Center: only worth hooking if its module classes exist here
    if (NSClassFromString(@"MTMaterialView") &&
        (NSClassFromString(@"CCUIContentModuleContainerView") || NSClassFromString(@"CCUIModularControlCenterOverlayViewController")))
        { %init(H12CC); }
    if (NSClassFromString(@"SBPasscodeNumberPadButton")) { %init(H12PassSB); }
    if (NSClassFromString(@"TPNumberPadButton"))         { %init(H12PassTP); }
    if (NSClassFromString(@"SBHUDView"))                 { %init(H12HudA); }
    if (NSClassFromString(@"SBVolumeHUDView"))           { %init(H12HudB); }
    LGLog(@"hosts12: cc=%d passSB=%d passTP=%d hudA=%d hudB=%d",
          NSClassFromString(@"CCUIContentModuleContainerView") != Nil,
          NSClassFromString(@"SBPasscodeNumberPadButton") != Nil,
          NSClassFromString(@"TPNumberPadButton") != Nil,
          NSClassFromString(@"SBHUDView") != Nil,
          NSClassFromString(@"SBVolumeHUDView") != Nil);
}

void LGHosts12Activate(void) {
    for (UIView *host in sH12Hosts.allObjects)
        if (host.window) [host setNeedsLayout];
}
