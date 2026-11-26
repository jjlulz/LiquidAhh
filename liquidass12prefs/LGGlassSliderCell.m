// Glass-styled slider: restyles the stock UISlider (frosted thumb, tinted track) so value
// handling and saving stay in PSSliderTableCell.
#import <UIKit/UIKit.h>
#import "LGKBridge.h"

@class PSSpecifier;
@interface PSTableCell : UITableViewCell
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier;
@end
@interface PSControlTableCell : PSTableCell
@property (nonatomic, retain) UIControl *control;
@end
@interface PSSliderTableCell : PSControlTableCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuse specifier:(PSSpecifier *)specifier;
@end

static UIImage *LGGlassThumb(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat d = 30.0, pad = 6.0;
        CGSize size = CGSizeMake(d + pad * 2, d + pad * 2);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGRect rect = CGRectMake(pad, pad - 1.0, d, d);
            CGContextRef c = ctx.CGContext;
            CGContextSaveGState(c);
            CGContextSetShadowWithColor(c, CGSizeMake(0, 2), 4.0, [UIColor colorWithWhite:0 alpha:0.30].CGColor);
            [[UIColor colorWithWhite:1.0 alpha:0.92] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:rect] fill];
            CGContextRestoreGState(c);

            // soft frosted highlight on the upper half
            CGContextSaveGState(c);
            [[UIBezierPath bezierPathWithOvalInRect:rect] addClip];
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGGradientRef gradient = CGGradientCreateWithColors(space,
                (__bridge CFArrayRef)@[(__bridge id)[UIColor colorWithRed:1 green:1 blue:1 alpha:0.95].CGColor,
                                       (__bridge id)[UIColor colorWithRed:0.86 green:0.90 blue:0.96 alpha:0.55].CGColor], NULL);
            CGContextDrawLinearGradient(c, gradient, CGPointMake(0, CGRectGetMinY(rect)),
                                        CGPointMake(0, CGRectGetMaxY(rect)), 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(space);
            CGContextRestoreGState(c);

            [[UIColor colorWithWhite:1.0 alpha:1.0] setStroke];
            UIBezierPath *rim = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(rect, 0.5, 0.5)];
            rim.lineWidth = 1.0;
            [rim stroke];
        }];
    });
    return image;
}

@interface LGGlassSliderCell : PSSliderTableCell
@end

@implementation LGGlassSliderCell {
    UIControl<LGKSliderLike> *_glass;   // LiquidGlassKit slider, nil if it is unavailable
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuse specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuse specifier:specifier];
    if (!self) return nil;

    _glass = LGKMakeSlider();
    UISlider *model = (UISlider *)self.control;
    if (_glass && [model isKindOfClass:UISlider.class]) {
        model.hidden = YES;   // stays alive as the data model (value label, saving)
        [_glass addTarget:self action:@selector(glassChanged:) forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:_glass];
        [self lgSyncFromModel];
    } else {
        _glass = nil;
        [self lgStyle];       // fallback: restyle the stock slider
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    if (_glass) [self lgSyncFromModel]; else [self lgStyle];
}

- (void)glassChanged:(UIControl<LGKSliderLike> *)glass {
    UISlider *model = (UISlider *)self.control;
    if (![model isKindOfClass:UISlider.class]) return;
    [model setValue:[glass value] animated:NO];
    [model sendActionsForControlEvents:UIControlEventValueChanged];   // PSSliderTableCell saves it
}

- (void)lgSyncFromModel {
    UISlider *model = (UISlider *)self.control;
    if (!_glass || ![model isKindOfClass:UISlider.class] || _glass.isTracking) return;
    [_glass setMinimumValue:model.minimumValue];   // range first so the value is not clamped wrongly
    [_glass setMaximumValue:model.maximumValue];
    if (fabsf([_glass value] - model.value) > 0.0001f) [_glass setValue:model.value];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_glass) return;
    UISlider *model = (UISlider *)self.control;
    if (![model isKindOfClass:UISlider.class]) return;
    [self lgSyncFromModel];
    CGRect frame = model.superview ? [model.superview convertRect:model.frame toView:self.contentView] : model.frame;
    if (CGRectIsEmpty(frame)) frame = CGRectInset(self.contentView.bounds, 16, 0);
    CGFloat height = 28.0;   // LiquidGlassSlider's own height
    _glass.frame = CGRectMake(CGRectGetMinX(frame), CGRectGetMidY(frame) - height / 2.0,
                              CGRectGetWidth(frame), height);
    [self.contentView bringSubviewToFront:_glass];
}

- (void)lgStyle {
    UISlider *slider = (UISlider *)self.control;
    if (![slider isKindOfClass:UISlider.class]) return;
    UIImage *thumb = LGGlassThumb();
    [slider setThumbImage:thumb forState:UIControlStateNormal];
    [slider setThumbImage:thumb forState:UIControlStateHighlighted];
    slider.minimumTrackTintColor = [UIColor colorWithRed:0.36 green:0.62 blue:1.0 alpha:0.95];
    slider.maximumTrackTintColor = [UIColor colorWithWhite:0.80 alpha:0.70];
}

@end
