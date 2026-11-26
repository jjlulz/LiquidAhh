// Glass-styled switch. The stock UISwitch stays as the (hidden) model so PSSwitchTableCell's
// own code still reads and saves the value; the glass control only mirrors and forwards taps.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "LGKBridge.h"

@class PSSpecifier;
@interface PSTableCell : UITableViewCell
@end
@interface PSControlTableCell : PSTableCell
@property (nonatomic, retain) UIControl *control;
@end
@interface PSSwitchTableCell : PSControlTableCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuse specifier:(PSSpecifier *)specifier;
@end

#pragma mark - control

@interface LGGlassToggle : UIControl
@property (nonatomic, readonly, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

@implementation LGGlassToggle {
    UIView *_track;
    CAGradientLayer *_gloss;
    UIView *_thumb;
    BOOL _on;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, 51, 31)];
    if (!self) return nil;

    _track = [[UIView alloc] initWithFrame:self.bounds];
    _track.userInteractionEnabled = NO;
    _track.layer.cornerRadius = 15.5;
    _track.layer.borderWidth = 1.0;
    _track.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
    _track.clipsToBounds = YES;
    [self addSubview:_track];

    _gloss = [CAGradientLayer layer];
    _gloss.frame = CGRectMake(0, 0, 51, 16);
    _gloss.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.45].CGColor,
                      (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor];
    [_track.layer addSublayer:_gloss];

    _thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 27, 27)];
    _thumb.userInteractionEnabled = NO;
    _thumb.layer.cornerRadius = 13.5;
    _thumb.layer.shadowColor = UIColor.blackColor.CGColor;
    _thumb.layer.shadowOpacity = 0.28;
    _thumb.layer.shadowRadius = 3.0;
    _thumb.layer.shadowOffset = CGSizeMake(0, 2);

    UIVisualEffectView *frost = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight]];
    frost.frame = _thumb.bounds;
    frost.layer.cornerRadius = 13.5;
    frost.clipsToBounds = YES;
    frost.layer.borderWidth = 1.0;
    frost.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    frost.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    [_thumb addSubview:frost];
    [self addSubview:_thumb];

    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [self applyOn:NO];
    return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(51, 31); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(51, 31); }
- (BOOL)isOn { return _on; }

- (void)applyOn:(BOOL)on {
    _track.backgroundColor = on ? [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:0.88]
                                : [UIColor colorWithWhite:0.72 alpha:0.50];
    _thumb.frame = CGRectMake(on ? 22 : 2, 2, 27, 27);
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (on == _on) return;
    _on = on;
    if (!animated) { [self applyOn:on]; return; }
    [UIView animateWithDuration:0.28 delay:0
         usingSpringWithDamping:0.8 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ [self applyOn:on]; } completion:nil];
}

- (void)tapped {
    [self setOn:!_on animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

#pragma mark - cell

@interface LGGlassSwitchCell : PSSwitchTableCell
@end

@implementation LGGlassSwitchCell {
    UIControl<LGKSwitchLike> *_glass;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuse specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuse specifier:specifier];
    if (!self) return nil;

    // LiquidGlassKit's glass switch when it loads, otherwise the Objective-C glass toggle
    _glass = LGKMakeSwitch() ?: (UIControl<LGKSwitchLike> *)[[LGGlassToggle alloc] initWithFrame:CGRectZero];
    [_glass addTarget:self action:@selector(glassChanged:) forControlEvents:UIControlEventValueChanged];

    UISwitch *model = (UISwitch *)self.control;
    if ([model isKindOfClass:UISwitch.class]) {
        model.hidden = YES;                 // stays alive as the data model
        [_glass setOn:model.isOn animated:NO];
    }
    self.accessoryView = _glass;
    return self;
}

- (void)glassChanged:(UIControl<LGKSwitchLike> *)glass {
    UISwitch *model = (UISwitch *)self.control;
    if (![model isKindOfClass:UISwitch.class]) return;
    [model setOn:[glass isOn] animated:NO];
    [model sendActionsForControlEvents:UIControlEventValueChanged];   // PSSwitchTableCell saves it
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UISwitch *model = (UISwitch *)self.control;
    if ([model isKindOfClass:UISwitch.class] && model.isOn != [_glass isOn])
        [_glass setOn:model.isOn animated:NO];   // value loaded / reloaded by the stock cell
}

@end
