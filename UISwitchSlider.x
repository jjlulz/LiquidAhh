// System-wide LiquidGlassKit switches and sliders for iOS 12 (apps + Settings, not SpringBoard).
//
// Every UISwitch / UISlider keeps working as the real control (target-actions, values, accessibility,
// app logic). A LiquidGlassKit LGKSwitch / LGKSlider is laid on top of it, the stock visuals are
// hidden, and the glass control forwards user input to the stock one.
//
// LGKCore.dylib lives in the settings bundle (LiquidAss12Prefs.bundle/LGK). If it is missing or Metal
// is unavailable in a process, that process keeps the stock controls.
// Kill switches: /var/mobile/liquidass12.disabled (everything), /var/mobile/liquidass12-nolgk (glass controls only).

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "LGSupport.h"

@protocol LGKSwitchLike <NSObject>
- (BOOL)isOn;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

@protocol LGKSliderLike <NSObject>
- (float)value;
- (void)setValue:(float)value;
- (float)minimumValue;
- (void)setMinimumValue:(float)value;
- (float)maximumValue;
- (void)setMaximumValue:(float)value;
@end

static NSString *const kLGKDir = @"/Library/PreferenceBundles/LiquidAss12Prefs.bundle/LGK";
static NSString *const kNoLGK  = @"/var/mobile/liquidass12-nolgk";
static const NSUInteger kMaxOverlays = 30;   // each one owns a (paused) Metal view

static BOOL sTried, sReady, sBusy;
static NSHashTable<UIView *> *sOverlays;
static void *kGlassKey  = &kGlassKey;
static void *kHiddenKey = &kHiddenKey;

#pragma mark - LGKCore loader (once per process, main thread)

static BOOL UILGKReady(void) {
    if (sTried) return sReady;
    sTried = YES;
    @try {
        if ([NSFileManager.defaultManager fileExistsAtPath:kNoLGK]) return NO;
        NSString *dylib = [kLGKDir stringByAppendingPathComponent:@"LGKCore.dylib"];
        if (![NSFileManager.defaultManager fileExistsAtPath:dylib]) return NO;
        if (!dlopen(dylib.fileSystemRepresentation, RTLD_NOW)) { LGLog(@"ui: dlopen failed: %s", dlerror()); return NO; }
        Class core = NSClassFromString(@"LGKCore");
        if (!core || !NSClassFromString(@"LGKSwitch") || !NSClassFromString(@"LGKSlider")) return NO;
        ((void (*)(Class, SEL, NSString *))objc_msgSend)(core, NSSelectorFromString(@"configureWithResourceDirectory:"), kLGKDir);
        sReady = ((BOOL (*)(Class, SEL))objc_msgSend)(core, NSSelectorFromString(@"isAvailable"));
        LGLog(@"ui: LGK ready=%d in %@", sReady, NSBundle.mainBundle.bundleIdentifier);
    } @catch (NSException *exception) {
        LGLog(@"ui: loader exception %@ %@", exception.name, exception.reason);
        sReady = NO;
    }
    return sReady;
}

static NSUInteger UIOverlayCount(void) {
    NSUInteger count = 0;
    for (UIView *view in sOverlays.allObjects) if (view.superview) count++;
    return count;
}

#pragma mark - glass -> stock forwarding

@interface LGUITarget : NSObject
+ (instancetype)shared;
- (void)switchChanged:(UIControl *)glass;
- (void)sliderChanged:(UIControl *)glass;
@end

@implementation LGUITarget
+ (instancetype)shared {
    static LGUITarget *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LGUITarget new]; });
    return shared;
}

- (void)switchChanged:(UIControl<LGKSwitchLike> *)glass {
    UISwitch *stock = (UISwitch *)glass.superview;
    if (sBusy || ![stock isKindOfClass:UISwitch.class]) return;
    sBusy = YES;
    @try {
        [stock setOn:[glass isOn] animated:NO];
        [stock sendActionsForControlEvents:UIControlEventValueChanged];
    } @finally { sBusy = NO; }
}

- (void)sliderChanged:(UIControl<LGKSliderLike> *)glass {
    UISlider *stock = (UISlider *)glass.superview;
    if (sBusy || ![stock isKindOfClass:UISlider.class]) return;
    sBusy = YES;
    @try {
        [stock setValue:[glass value] animated:NO];
        [stock sendActionsForControlEvents:UIControlEventValueChanged];
    } @finally { sBusy = NO; }
}
@end

#pragma mark - overlay management

static void UIRemoveOverlay(UIView *stock) {
    UIView *glass = objc_getAssociatedObject(stock, kGlassKey);
    NSHashTable<UIView *> *hidden = objc_getAssociatedObject(stock, kHiddenKey);
    for (UIView *view in hidden.allObjects) view.hidden = NO;
    objc_setAssociatedObject(stock, kHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stock, kGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [glass removeFromSuperview];
}

// returns the glass control for `stock`, creating it if needed; hides every other subview of the stock control
static UIControl *UIOverlayFor(UIView *stock, UIControl *(^make)(void)) {
    UIControl *glass = objc_getAssociatedObject(stock, kGlassKey);
    if (!glass) {
        if (UIOverlayCount() >= kMaxOverlays || !UILGKReady()) return nil;
        glass = make();
        if (!glass) return nil;
        objc_setAssociatedObject(stock, kGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!sOverlays) sOverlays = [NSHashTable weakObjectsHashTable];
        [sOverlays addObject:glass];
    }
    if (glass.superview != stock) [stock addSubview:glass];

    NSHashTable<UIView *> *hidden = objc_getAssociatedObject(stock, kHiddenKey);
    if (!hidden) {
        hidden = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(stock, kHiddenKey, hidden, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *sub in stock.subviews) {
        if (sub == glass || sub.hidden) continue;
        sub.hidden = YES;
        [hidden addObject:sub];
    }
    if (stock.subviews.lastObject != glass) [stock bringSubviewToFront:glass];
    return glass;
}

static BOOL UIEligible(UIView *view) {
    return view.window != nil && !view.hidden && CGRectGetWidth(view.bounds) >= 20.0 && CGRectGetHeight(view.bounds) >= 10.0;
}

#pragma mark - switch

static void UISyncSwitch(UISwitch *stock) {
    if (sBusy) return;
    if (!UIEligible(stock)) { if (objc_getAssociatedObject(stock, kGlassKey)) UIRemoveOverlay(stock); return; }
    @try {
        UIControl<LGKSwitchLike> *glass = (UIControl<LGKSwitchLike> *)UIOverlayFor(stock, ^UIControl *{
            Class cls = NSClassFromString(@"LGKSwitch");
            UIControl *control = [[cls alloc] initWithFrame:CGRectZero];
            [control addTarget:LGUITarget.shared action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            return control;
        });
        if (!glass) return;
        glass.center = CGPointMake(CGRectGetMidX(stock.bounds), CGRectGetMidY(stock.bounds));
        glass.alpha = stock.isEnabled ? 1.0 : 0.5;
        glass.userInteractionEnabled = stock.isEnabled;
        if ([glass isOn] != stock.isOn) {
            sBusy = YES;
            [glass setOn:stock.isOn animated:NO];
            sBusy = NO;
        }
    } @catch (NSException *exception) {
        sBusy = NO;
        LGLog(@"ui: switch exception %@ %@", exception.name, exception.reason);
    }
}

static void UIMirrorSwitch(UISwitch *stock, BOOL animated) {
    UIControl<LGKSwitchLike> *glass = objc_getAssociatedObject(stock, kGlassKey);
    if (!glass || sBusy || [glass isOn] == stock.isOn) return;
    @try {
        sBusy = YES;
        [glass setOn:stock.isOn animated:animated];
    } @catch (NSException *exception) {
        LGLog(@"ui: switch mirror exception %@", exception.reason);
    } @finally { sBusy = NO; }
}

#pragma mark - slider

static void UISyncSlider(UISlider *stock) {
    if (sBusy) return;
    if (!UIEligible(stock)) { if (objc_getAssociatedObject(stock, kGlassKey)) UIRemoveOverlay(stock); return; }
    @try {
        UIControl<LGKSliderLike> *glass = (UIControl<LGKSliderLike> *)UIOverlayFor(stock, ^UIControl *{
            Class cls = NSClassFromString(@"LGKSlider");
            UIControl *control = [[cls alloc] initWithFrame:CGRectZero];
            [control addTarget:LGUITarget.shared action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            return control;
        });
        if (!glass) return;
        CGFloat height = 28.0;   // LiquidGlassSlider's own height
        glass.frame = CGRectMake(0, CGRectGetMidY(stock.bounds) - height / 2.0, CGRectGetWidth(stock.bounds), height);
        glass.alpha = stock.isEnabled ? 1.0 : 0.5;
        glass.userInteractionEnabled = stock.isEnabled;
        if (!glass.isTracking) {
            sBusy = YES;
            [glass setMinimumValue:stock.minimumValue];   // range first so the value is not clamped wrongly
            [glass setMaximumValue:stock.maximumValue];
            if (fabsf([glass value] - stock.value) > 0.0001f) [glass setValue:stock.value];
            sBusy = NO;
        }
    } @catch (NSException *exception) {
        sBusy = NO;
        LGLog(@"ui: slider exception %@ %@", exception.name, exception.reason);
    }
}

#pragma mark - hooks

%group LGUI
%hook UISwitch
- (void)didMoveToWindow { %orig; UISyncSwitch((UISwitch *)self); }
- (void)layoutSubviews  { %orig; UISyncSwitch((UISwitch *)self); }
- (void)setOn:(BOOL)on animated:(BOOL)animated { %orig; UIMirrorSwitch((UISwitch *)self, animated); }
- (void)setOn:(BOOL)on { %orig; UIMirrorSwitch((UISwitch *)self, NO); }
%end

%hook UISlider
- (void)didMoveToWindow { %orig; UISyncSlider((UISlider *)self); }
- (void)layoutSubviews  { %orig; UISyncSlider((UISlider *)self); }
- (void)setValue:(float)value animated:(BOOL)animated { %orig; UISyncSlider((UISlider *)self); }
- (void)setValue:(float)value { %orig; UISyncSlider((UISlider *)self); }
%end
%end

%ctor {
    @autoreleasepool {
        NSBundle *main = NSBundle.mainBundle;
        NSString *bundleID = main.bundleIdentifier;
        if (!bundleID || [bundleID isEqualToString:@"com.apple.springboard"]) return;
        if (![main.bundlePath hasSuffix:@".app"]) return;                 // apps only, no daemons/extensions
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 12) return;
        if (LGKillSwitchPresent()) return;
        if (!LGPrefBool(@"Global.Enabled", YES) || !LGPrefBool(@"UI.Enabled", YES)) return;
        %init(LGUI);
    }
}
