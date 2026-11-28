// Keyboard glass for iOS 12. Separate dylib (LiquidAss12KB) because the keyboard is drawn inside
// each app's own process, not SpringBoard. Only the keyboard background is replaced: no geometry,
// font or key-rendering changes (the original's iOS 14+ keyboard host does those).

#import <UIKit/UIKit.h>
#import "LGSupport.h"
#import "LGGlass.h"

static NSHashTable<UIView *> *sBackdrops;
static BOOL sBusy;

static void LGSyncKeyboardBackdrop(UIView *host) {
    if (!host.window) { LGRemoveGlass(host); return; }
    LGDumpOnce(host, @"UIKBBackdropView");
    LGInstallGlass(host, @"Keyboard", 0.0);
}

static void LGKeyboardRun(UIView *host) {
    if (!host || sBusy) return;
    if (!sBackdrops) sBackdrops = [NSHashTable weakObjectsHashTable];
    [sBackdrops addObject:host];
    if (!LGActive()) return;
    sBusy = YES;
    @try {
        LGSyncKeyboardBackdrop(host);
    } @catch (NSException *exception) {
        LGLog(@"keyboard exception: %@ %@", exception.name, exception.reason);
    } @finally {
        sBusy = NO;
    }
}

%group LGKeyboard
%hook UIKBBackdropView
- (void)didMoveToWindow { %orig; LGKeyboardRun((UIView *)self); }
- (void)layoutSubviews  { %orig; LGKeyboardRun((UIView *)self); }
%end
%end

%ctor {
    @autoreleasepool {
        NSBundle *main = NSBundle.mainBundle;
        NSString *bundleID = main.bundleIdentifier;
        if (!bundleID || [bundleID isEqualToString:@"com.apple.springboard"]) return;   // SpringBoard has its own dylib
        if (![main.bundlePath hasSuffix:@".app"]) return;                                // apps only, no daemons/extensions
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 12) return;
        if (LGKillSwitchPresent()) return;
        if (!LGPrefBool(@"Global.Enabled", YES) || !LGHostEnabled(@"Keyboard")) return;
        if (!NSClassFromString(@"UIKBBackdropView") || !LGGlassSupported()) return;

        %init(LGKeyboard);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            LGSetActive(YES);
            for (UIView *host in sBackdrops.allObjects)
                if (host.window) [host setNeedsLayout];
        });
    }
}
