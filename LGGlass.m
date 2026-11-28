// Renderer for the iOS 12 port.
// The original tweak registers custom refraction filters inside backboardd (iOS 14+ render
// server internals). None of that exists on iOS 12, so this uses only what iOS 12 already
// ships: CABackdropLayer + CAFilter gaussianBlur/colorSaturate, a tint, and a specular rim.
// It never touches backboardd.

#import "LGGlass.h"
#import "LGSupport.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>

typedef struct {
    const char *prefix;
    CGFloat blur;        // gaussian radius
    CGFloat saturation;  // 1.0 = unchanged
    CGFloat tintWhite;   // tint color (0 black .. 1 white)
    CGFloat tintAlpha;
    CGFloat rim;         // specular rim opacity
} LGStyle;

static const LGStyle kStyles[] = {
    //  prefix          blur  sat  tintW tintA rim
    { "Dock",           14.0, 1.6, 1.0,  0.10, 0.55 },
    { "FolderIcon",     10.0, 1.6, 1.0,  0.12, 0.60 },
    { "OpenFolder",     18.0, 1.5, 0.0,  0.22, 0.40 },
    { "Banner",         16.0, 1.6, 1.0,  0.45, 0.50 },
    { "Notification",   16.0, 1.6, 1.0,  0.40, 0.45 },
    { "ControlCenter",  16.0, 1.6, 1.0,  0.12, 0.50 },
    { "Passcode",       12.0, 1.5, 0.0,  0.12, 0.55 },
    { "VolumeHUD",      14.0, 1.6, 1.0,  0.18, 0.50 },
    { "Keyboard",       20.0, 1.5, 1.0,  0.35, 0.35 },
};

static const LGStyle *LGStyleForPrefix(NSString *prefix) {
    for (size_t i = 0; i < sizeof(kStyles) / sizeof(kStyles[0]); i++)
        if (strcmp(kStyles[i].prefix, prefix.UTF8String) == 0) return &kStyles[i];
    return NULL;
}

static const NSUInteger kMaxLiveGlasses = 28;   // hard cap: A8 GPU + 1 GB RAM

#pragma mark - safe private-API helpers

static id LGMakeFilter(NSString *type) {
    Class cls = NSClassFromString(@"CAFilter");
    SEL selector = NSSelectorFromString(@"filterWithType:");
    if (![cls respondsToSelector:selector]) selector = NSSelectorFromString(@"filterWithName:");
    if (![cls respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(Class, SEL, NSString *))objc_msgSend)(cls, selector, type);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void LGSetValue(id object, NSString *key, id value) {
    @try { [object setValue:value forKey:key]; } @catch (__unused NSException *e) {}
}

// only sets a private layer property if its setter really exists on this iOS version
static void LGSetLayerProperty(CALayer *layer, NSString *key, id value) {
    NSString *setter = [NSString stringWithFormat:@"set%@%@:",
                        [key substringToIndex:1].uppercaseString, [key substringFromIndex:1]];
    if (![layer respondsToSelector:NSSelectorFromString(setter)]) return;
    LGSetValue(layer, key, value);
}

static void LGApplyCorner(CALayer *layer, CGFloat radius) {
    layer.cornerRadius = radius;
    // continuous corners: public on iOS 13+, private flag on iOS 12. No @available so
    // there is no dependency on compiler-rt version checks.
    SEL curve = NSSelectorFromString(@"setCornerCurve:");
    SEL legacy = NSSelectorFromString(@"setContinuousCorners:");
    if ([layer respondsToSelector:curve]) LGSetValue(layer, @"cornerCurve", @"continuous");
    else if ([layer respondsToSelector:legacy]) LGSetValue(layer, @"continuousCorners", @YES);
}

BOOL LGGlassSupported(void) {
    static BOOL supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        supported = NSClassFromString(@"CABackdropLayer") != nil && LGMakeFilter(@"gaussianBlur") != nil;
        LGLog(@"glass supported=%d (CABackdropLayer=%d)", supported,
              NSClassFromString(@"CABackdropLayer") != nil);
    });
    return supported;
}

// area budget keeps the capture cost predictable on small GPUs
static CGFloat LGScaleForSize(CGSize size) {
    CGFloat area = size.width * size.height;
    if (area <= 1.0) return 0.5;
    CGFloat quality = fmin(1.0, fmax(0.3, LGPrefFloat(@"Quality", 1.0)));
    CGFloat scale = sqrt((6000.0 * quality) / area);
    return fmin(0.75, fmax(0.2, scale));
}

#pragma mark - glass view

@protocol LGGlassLike <NSObject>
@property (nonatomic, readonly) BOOL lgOperational;
@property (nonatomic, readonly, copy) NSString *lgPrefix;
@property (nonatomic) CGFloat lgRadius;
@end

@interface LGGlassView : UIView <LGGlassLike>
@property (nonatomic, readonly) BOOL lgOperational;
@property (nonatomic, readonly, copy) NSString *lgPrefix;
@property (nonatomic) CGFloat lgRadius;
- (instancetype)initWithPrefix:(NSString *)prefix style:(const LGStyle *)style;
@end

@implementation LGGlassView {
    LGStyle _style;
    UIView *_tint;
    CAGradientLayer *_rim;
    CALayer *_rimMask;
    CGFloat _appliedScale;
    BOOL _filtersApplied;
}

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (instancetype)initWithPrefix:(NSString *)prefix style:(const LGStyle *)style {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _style = *style;
    _lgPrefix = [prefix copy];
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.layer.masksToBounds = YES;

    _tint = [[UIView alloc] initWithFrame:CGRectZero];
    _tint.userInteractionEnabled = NO;
    _tint.backgroundColor = [UIColor colorWithWhite:_style.tintWhite alpha:_style.tintAlpha];
    _tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_tint];

    CGFloat rim = fmax(0.0, fmin(1.0, _style.rim * LGPrefFloat(@"Rim", 1.0)));
    id clear = (id)UIColor.clearColor.CGColor;
    _rim = [CAGradientLayer layer];
    _rim.locations = @[@0.0, @0.12, @0.34, @0.66, @0.88, @1.0];
    _rim.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:rim * 0.90].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:rim * 0.35].CGColor,
        clear, clear,
        (id)[UIColor colorWithWhite:0.0 alpha:rim * 0.12].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:rim * 0.40].CGColor,
    ];
    _rim.startPoint = CGPointMake(0.854, 0.146);   // fixed highlight angle, no motion updates
    _rim.endPoint   = CGPointMake(0.146, 0.854);
    _rimMask = [CALayer layer];
    _rimMask.backgroundColor = UIColor.clearColor.CGColor;
    _rimMask.borderColor = UIColor.blackColor.CGColor;
    _rimMask.borderWidth = 1.0;
    _rim.mask = _rimMask;
    [self.layer addSublayer:_rim];

    [self lgApplyFilters];
    return self;
}

- (BOOL)lgOperational { return _filtersApplied; }

- (void)setLgRadius:(CGFloat)radius {
    if (fabs(_lgRadius - radius) < 0.01) return;
    _lgRadius = radius;
    [self setNeedsLayout];
}

- (void)lgApplyFilters {
    CALayer *layer = self.layer;
    CGFloat scale = LGScaleForSize(self.bounds.size);
    if (fabs(scale - _appliedScale) > 0.02) {
        LGSetLayerProperty(layer, @"scale", @(scale));   // render the backdrop smaller, then blur
        _appliedScale = scale;
    }
    if (_filtersApplied) return;

    NSMutableArray *filters = [NSMutableArray array];
    id blur = LGMakeFilter(@"gaussianBlur");
    if (blur) {
        CGFloat radius = _style.blur * fmax(0.1, LGPrefFloat(@"Blur", 1.0));
        LGSetValue(blur, @"inputRadius", @(radius));
        LGSetValue(blur, @"inputNormalizeEdges", @YES);
        [filters addObject:blur];
    }
    id saturate = LGMakeFilter(@"colorSaturate");
    if (saturate) {
        LGSetValue(saturate, @"inputAmount", @(_style.saturation));
        [filters addObject:saturate];
    }
    if (!blur) return;   // no blur = not operational, caller keeps the stock view

    LGSetLayerProperty(layer, @"enabled", @YES);
    layer.filters = filters;
    _filtersApplied = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    LGApplyCorner(self.layer, _lgRadius);
    _rim.frame = bounds;
    _rimMask.frame = bounds;
    LGApplyCorner(_rimMask, _lgRadius);
    [CATransaction commit];
    [self lgApplyFilters];
}

@end

#pragma mark - metal (LiquidGlassKit) glass

static BOOL sMetalReady;
static NSString *const kLGKDir = @"/Library/PreferenceBundles/LiquidAss12Prefs.bundle/LGK";
static const NSUInteger kMaxLiveMetal = 6;   // each one is a 30 fps Metal view

BOOL LGMetalPrepare(void) {
    static BOOL done;
    if (done) return sMetalReady;
    done = YES;
    @try {
        if (!LGPrefBool(@"Metal.Enabled", YES)) { LGLog(@"metal: off by preference"); return NO; }
        if (!LGMetalAllowed()) { LGLog(@"metal: off by safety flag (/var/mobile/liquidass12-nometal)"); return NO; }
        NSString *dylib = [kLGKDir stringByAppendingPathComponent:@"LGKCore.dylib"];
        if (![NSFileManager.defaultManager fileExistsAtPath:dylib]) { LGLog(@"metal: LGKCore.dylib not installed"); return NO; }

        LGMetalMarkerSet();   // if SpringBoard dies before the marker is cleared, Metal turns itself off next launch
        void *handle = dlopen(dylib.fileSystemRepresentation, RTLD_NOW);
        if (!handle) { LGLog(@"metal: dlopen failed: %s", dlerror()); LGMetalMarkerClear(); return NO; }
        Class core = NSClassFromString(@"LGKCore");
        if (!core || !NSClassFromString(@"LGKGlassPanel")) { LGLog(@"metal: classes missing"); LGMetalMarkerClear(); return NO; }
        ((void (*)(Class, SEL, NSString *))objc_msgSend)(core, NSSelectorFromString(@"configureWithResourceDirectory:"), kLGKDir);
        BOOL ok = ((BOOL (*)(Class, SEL))objc_msgSend)(core, NSSelectorFromString(@"isAvailable"));
        LGLog(@"metal: available=%d", ok);
        if (!ok) { LGMetalMarkerClear(); return NO; }
        sMetalReady = YES;
    } @catch (NSException *exception) {
        LGLog(@"metal: exception %@ %@", exception.name, exception.reason);
        LGMetalMarkerClear();
        sMetalReady = NO;
    }
    return sMetalReady;
}

static BOOL LGUseMetal(NSString *prefix) {
    if (!sMetalReady || !LGPrefBool(@"Metal.Enabled", YES)) return NO;
    // folder icons stay on the cheap blur by default: up to ~16 of them per page
    BOOL fallback = [prefix isEqualToString:@"Dock"] || [prefix isEqualToString:@"Banner"] ||
                    [prefix isEqualToString:@"OpenFolder"];
    return LGPrefBool([prefix stringByAppendingString:@".Metal"], fallback);
}

@interface LGMetalGlassView : UIView <LGGlassLike>
@end

@implementation LGMetalGlassView {
    UIView *_panel;
    NSString *_prefix;
    CGFloat _radius;
}

- (instancetype)initWithPrefix:(NSString *)prefix {
    Class panelClass = NSClassFromString(@"LGKGlassPanel");
    if (!panelClass) return nil;
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _prefix = [prefix copy];
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _panel = [[panelClass alloc] initWithFrame:CGRectZero];
    if (![_panel isKindOfClass:UIView.class]) return nil;
    _panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_panel];
    return self;
}

- (BOOL)lgOperational { return _panel != nil; }
- (NSString *)lgPrefix { return _prefix; }
- (CGFloat)lgRadius { return _radius; }

- (void)setLgRadius:(CGFloat)radius {
    if (fabs(_radius - radius) < 0.01) return;
    _radius = radius;
    SEL setter = NSSelectorFromString(@"setGlassCornerRadius:");
    if ([_panel respondsToSelector:setter])
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(_panel, setter, radius);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _panel.frame = self.bounds;
}

@end

#pragma mark - install / remove

static void *kGlassKey  = &kGlassKey;
static void *kHiddenKey = &kHiddenKey;
static NSHashTable<UIView<LGGlassLike> *> *sLiveGlasses;

static NSUInteger LGLiveCount(BOOL metalOnly) {
    NSUInteger count = 0;
    for (UIView<LGGlassLike> *glass in sLiveGlasses.allObjects)
        if (glass.superview && (!metalOnly || [glass isKindOfClass:LGMetalGlassView.class])) count++;
    return count;
}

void LGRemoveGlass(UIView *stock) {
    if (!stock) return;
    UIView *glass = objc_getAssociatedObject(stock, kGlassKey);
    NSHashTable<UIView *> *hidden = objc_getAssociatedObject(stock, kHiddenKey);
    for (UIView *view in hidden.allObjects) view.hidden = NO;
    objc_setAssociatedObject(stock, kHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stock, kGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [glass removeFromSuperview];
}

UIView *LGInstallGlass(UIView *stock, NSString *prefix, CGFloat radius) {
    if (!stock) return nil;
    if (!LGActive() || !LGGlassSupported() || !LGHostEnabled(prefix)) {
        LGRemoveGlass(stock);
        return nil;
    }

    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    if (backdropClass && [stock.layer isKindOfClass:backdropClass]) {
        // the stock view *is* the blur: we cannot hide its own layer safely, so leave it alone
        static BOOL logged;
        if (!logged) { logged = YES; LGLog(@"stock %@ is itself a backdrop; skipping", NSStringFromClass(stock.class)); }
        return nil;
    }

    UIView<LGGlassLike> *glass = objc_getAssociatedObject(stock, kGlassKey);
    if (glass && ![glass.lgPrefix isEqualToString:prefix]) {   // e.g. platter moved banner <-> list
        LGRemoveGlass(stock);
        glass = nil;
    }
    if (!glass) {
        const LGStyle *style = LGStyleForPrefix(prefix);
        if (!style || LGLiveCount(NO) >= kMaxLiveGlasses) return nil;
        if (LGUseMetal(prefix) && LGLiveCount(YES) < kMaxLiveMetal)
            glass = [[LGMetalGlassView alloc] initWithPrefix:prefix];
        if (!glass.lgOperational)   // Metal not wanted / not available: stock-blur renderer
            glass = [[LGGlassView alloc] initWithPrefix:prefix style:style];
        if (!glass.lgOperational) return nil;
        glass.frame = stock.bounds;
        [stock addSubview:glass];
        objc_setAssociatedObject(stock, kGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!sLiveGlasses) sLiveGlasses = [NSHashTable weakObjectsHashTable];
        [sLiveGlasses addObject:glass];
        LGLog(@"installed %@ (%@) on %@ bounds=%@ radius=%.1f", prefix,
              [glass isKindOfClass:LGMetalGlassView.class] ? @"metal" : @"blur",
              NSStringFromClass(stock.class), NSStringFromCGRect(stock.bounds), radius);
    }

    if (glass.superview != stock) [stock addSubview:glass];
    if (!CGRectEqualToRect(glass.frame, stock.bounds)) glass.frame = stock.bounds;
    glass.lgRadius = radius;

    // child mode: the glass inherits the stock view's alpha, transform and animations,
    // so folder open / dock fades keep working. Everything else inside it is the stock blur.
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

#pragma mark - debug dump

static void LGDumpTree(UIView *view, NSUInteger depth, NSUInteger maxDepth, NSMutableString *out) {
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [out appendFormat:@"%@%@ frame=%@ hidden=%d alpha=%.2f layer=%@ r=%.1f\n", indent,
        NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.hidden, view.alpha,
        NSStringFromClass(view.layer.class), view.layer.cornerRadius];
    if (depth >= maxDepth) return;
    for (UIView *sub in view.subviews) LGDumpTree(sub, depth + 1, maxDepth, out);
}

void LGDumpOnce(UIView *view, NSString *tag) {
    static NSMutableSet<NSString *> *done;
    if (!done) done = [NSMutableSet set];
    if (!view || [done containsObject:tag]) return;
    [done addObject:tag];
    NSMutableString *out = [NSMutableString stringWithFormat:@"--- dump %@ ---\nancestors:", tag];
    for (UIView *a = view; a; a = a.superview) [out appendFormat:@" %@", NSStringFromClass(a.class)];
    UIWindow *window = view.window;
    [out appendFormat:@"\nwindow: %@ level=%.0f\n",
        window ? NSStringFromClass(window.class) : @"nil", window.windowLevel];
    LGDumpTree(view, 0, 3, out);
    LGLog(@"%@", out);
}
