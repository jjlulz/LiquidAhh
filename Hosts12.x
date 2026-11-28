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

// marks the materials THIS host put glass on, so it never touches glass installed by another host
// (the dock / banner / folder backgrounds can be MTMaterialViews too)
static void *kH12CCOwnedKey = &kH12CCOwnedKey;

static void H12SyncCCMaterial(UIView *material) {
    BOOL candidate = material.window != nil
        && [NSStringFromClass(material.class) isEqualToString:@"MTMaterialView"]
        && H12HasAncestor(material, @"CCUIContentModule")
        && !H12HasAncestor(material, @"Slider")          // keep slider fills intact
        && CGRectGetWidth(material.bounds) >= 40.0 && CGRectGetHeight(material.bounds) >= 40.0;
    if (!candidate) {
        if (objc_getAssociatedObject(material, kH12CCOwnedKey)) {
            LGRemoveGlass(material);
            objc_setAssociatedObject(material, kH12CCOwnedKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        return;
    }
    LGDumpOnce(material, @"CC module material");
    CGFloat side = MIN(CGRectGetWidth(material.bounds), CGRectGetHeight(material.bounds));
    if (LGInstallGlass(material, @"ControlCenter", H12Radius(material, H12Radius(material.superview, side * 0.22))))
        objc_setAssociatedObject(material, kH12CCOwnedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
