#import "LGKBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kNoLGK   = @"/var/mobile/liquidass12-nolgk";            // create to force fallback controls
static NSString *const kMarker  = @"/var/mobile/liquidass12-lgk-loading";      // present = last attempt did not survive
static NSString *const kLogPath = @"/var/mobile/liquidass12-prefs-debug.txt";

@interface LGKAnchor : NSObject
@end
@implementation LGKAnchor
@end

static void LGKLog(NSString *message) {
    NSString *line = [message stringByAppendingString:@"\n"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!handle) {
        [line writeToFile:kLogPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    if (handle.seekToEndOfFile < 50 * 1024) [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

BOOL LGKAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            NSFileManager *fm = NSFileManager.defaultManager;
            if ([fm fileExistsAtPath:kNoLGK]) { LGKLog(@"nolgk flag present; using fallback controls"); return; }
            if ([fm fileExistsAtPath:kMarker]) {
                // the previous attempt to use LiquidGlassKit never reached the "survived" mark
                [@"previous attempt crashed\n" writeToFile:kNoLGK atomically:YES encoding:NSUTF8StringEncoding error:nil];
                [fm removeItemAtPath:kMarker error:nil];
                LGKLog(@"previous LGK attempt crashed; wrote nolgk flag, using fallback controls");
                return;
            }

            NSString *dir = [[NSBundle bundleForClass:LGKAnchor.class].bundlePath stringByAppendingPathComponent:@"LGK"];
            NSString *dylib = [dir stringByAppendingPathComponent:@"LGKCore.dylib"];
            if (![fm fileExistsAtPath:dylib]) { LGKLog(@"LGKCore.dylib not in package; using fallback controls"); return; }

            [@"loading\n" writeToFile:kMarker atomically:YES encoding:NSUTF8StringEncoding error:nil];
            void *handle = dlopen(dylib.fileSystemRepresentation, RTLD_NOW);
            if (!handle) {
                LGKLog([NSString stringWithFormat:@"dlopen failed: %s", dlerror()]);
                [fm removeItemAtPath:kMarker error:nil];
                return;
            }
            Class core = NSClassFromString(@"LGKCore");
            if (!core || !NSClassFromString(@"LGKSwitch") || !NSClassFromString(@"LGKSlider")) {
                LGKLog(@"LGK classes missing after dlopen");
                [fm removeItemAtPath:kMarker error:nil];
                return;
            }
            ((void (*)(Class, SEL, NSString *))objc_msgSend)(core, NSSelectorFromString(@"configureWithResourceDirectory:"), dir);
            BOOL ok = ((BOOL (*)(Class, SEL))objc_msgSend)(core, NSSelectorFromString(@"isAvailable"));
            LGKLog([NSString stringWithFormat:@"LGK available=%d", ok]);
            if (!ok) { [fm removeItemAtPath:kMarker error:nil]; return; }
            available = YES;

            // if Settings is still alive 2 s after the glass views started, this attempt is considered safe
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [NSFileManager.defaultManager removeItemAtPath:kMarker error:nil];
            });
        } @catch (NSException *exception) {
            LGKLog([NSString stringWithFormat:@"exception: %@ %@", exception.name, exception.reason]);
            [NSFileManager.defaultManager removeItemAtPath:kMarker error:nil];
        }
    });
    return available;
}

UIControl<LGKSwitchLike> *LGKMakeSwitch(void) {
    if (!LGKAvailable()) return nil;
    Class cls = NSClassFromString(@"LGKSwitch");
    return cls ? (UIControl<LGKSwitchLike> *)[[cls alloc] initWithFrame:CGRectZero] : nil;
}

UIControl<LGKSliderLike> *LGKMakeSlider(void) {
    if (!LGKAvailable()) return nil;
    Class cls = NSClassFromString(@"LGKSlider");
    return cls ? (UIControl<LGKSliderLike> *)[[cls alloc] initWithFrame:CGRectZero] : nil;
}
