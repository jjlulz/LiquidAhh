#pragma once
#import <UIKit/UIKit.h>

// Shape of the Swift LGKSwitch / LGKSlider classes (LiquidGlassKit, ported to iOS 12).
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

// YES only if LGKCore.dylib loaded, Metal works and the shaders compile.
BOOL LGKAvailable(void);

// nil when LiquidGlassKit is unavailable (callers fall back to the Objective-C glass controls).
UIControl<LGKSwitchLike> *LGKMakeSwitch(void);
UIControl<LGKSliderLike> *LGKMakeSlider(void);
