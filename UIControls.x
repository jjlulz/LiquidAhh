#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "liquidass12prefs/LGKBridge.h"

static void *kLGKControlKey = &kLGKControlKey;
static void *kLGKTargetKey  = &kLGKTargetKey;

@interface LGKGlobalTarget : NSObject
@property (nonatomic, weak) UIControl *hostControl;
@end

@implementation LGKGlobalTarget
- (void)switchChanged:(UIControl<LGKSwitchLike> *)glassSwitch {
    UISwitch *sw = (UISwitch *)self.hostControl;
    if (!sw) return;
    [sw setOn:[glassSwitch isOn] animated:NO];
    [sw sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)sliderChanged:(UIControl<LGKSliderLike> *)glassSlider {
    UISlider *sl = (UISlider *)self.hostControl;
    if (!sl) return;
    [sl setValue:[glassSlider value] animated:NO];
    [sl sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

#pragma mark - Global UISwitch

%hook UISwitch

- (void)didMoveToWindow {
    %orig;
    if (!self.window || objc_getAssociatedObject(self, kLGKControlKey)) return;
    if (self.hidden) return;

    UIControl<LGKSwitchLike> *glass = LGKMakeSwitch();
    if (!glass) return;

    for (UIView *sub in self.subviews) {
        sub.hidden = YES;
    }

    LGKGlobalTarget *target = [LGKGlobalTarget new];
    target.hostControl = self;
    objc_setAssociatedObject(self, kLGKTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    glass.frame = self.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [glass setOn:self.isOn animated:NO];
    [glass addTarget:target action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];

    [self addSubview:glass];
    objc_setAssociatedObject(self, kLGKControlKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)layoutSubviews {
    %orig;
    UIControl<LGKSwitchLike> *glass = objc_getAssociatedObject(self, kLGKControlKey);
    if (!glass) return;
    for (UIView *sub in self.subviews) {
        if (sub != glass) sub.hidden = YES;
    }
    glass.frame = self.bounds;
    [self bringSubviewToFront:glass];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    %orig;
    UIControl<LGKSwitchLike> *glass = objc_getAssociatedObject(self, kLGKControlKey);
    if (glass && !glass.isTracking && [glass isOn] != on) {
        [glass setOn:on animated:animated];
    }
}

%end

#pragma mark - Global UISlider

%hook UISlider

- (void)didMoveToWindow {
    %orig;
    if (!self.window || objc_getAssociatedObject(self, kLGKControlKey)) return;
    if (self.hidden) return;

    UIControl<LGKSliderLike> *glass = LGKMakeSlider();
    if (!glass) return;

    for (UIView *sub in self.subviews) {
        sub.hidden = YES;
    }

    LGKGlobalTarget *target = [LGKGlobalTarget new];
    target.hostControl = self;
    objc_setAssociatedObject(self, kLGKTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGFloat height = 28.0;
    glass.frame = CGRectMake(0, (CGRectGetHeight(self.bounds) - height) / 2.0, CGRectGetWidth(self.bounds), height);
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [glass setMinimumValue:self.minimumValue];
    [glass setMaximumValue:self.maximumValue];
    [glass setValue:self.value];
    [glass addTarget:target action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];

    [self addSubview:glass];
    objc_setAssociatedObject(self, kLGKControlKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)layoutSubviews {
    %orig;
    UIControl<LGKSliderLike> *glass = objc_getAssociatedObject(self, kLGKControlKey);
    if (!glass) return;
    for (UIView *sub in self.subviews) {
        if (sub != glass) sub.hidden = YES;
    }
    CGFloat height = 28.0;
    glass.frame = CGRectMake(0, (CGRectGetHeight(self.bounds) - height) / 2.0, CGRectGetWidth(self.bounds), height);
    [self bringSubviewToFront:glass];
}

- (void)setValue:(float)value animated:(BOOL)animated {
    %orig;
    UIControl<LGKSliderLike> *glass = objc_getAssociatedObject(self, kLGKControlKey);
    if (glass && !glass.isTracking) {
        [glass setMinimumValue:self.minimumValue];
        [glass setMaximumValue:self.maximumValue];
        if (fabsf([glass value] - value) > 0.0001f) {
            [glass setValue:value];
        }
    }
}

%end

%ctor {
    if (access("/var/mobile/liquidass12.disabled", F_OK) == 0) return;
    if (access("/var/mobile/liquidass12-nolgk", F_OK) == 0) return;

    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID || [bundleID hasPrefix:@"com.apple.WebKit"] || [bundleID isEqualToString:@"com.apple.backboardd"]) {
        return;
    }
    %init;
}
