#import "LGSupport.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>

static NSString *const kLogPath   = @"/var/mobile/liquidass12-debug.txt";
static NSString *const kKillPath  = @"/var/mobile/liquidass12.disabled";
static NSString *const kGuardPath = @"/var/mobile/liquidass12-guard.plist";
static NSString *const kNoMetalPath = @"/var/mobile/liquidass12-nometal";
static NSString *const kMetalMarkerPath = @"/var/mobile/liquidass12-metal-loading";

static const off_t kLogCap = 120 * 1024;

#pragma mark - activation

static BOOL sActive;
BOOL LGActive(void) { return sActive; }
void LGSetActive(BOOL active) { sActive = active; }

#pragma mark - log

void LGLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.jjlulz.liquidass12.log", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(queue, ^{
        struct stat st;
        if (stat(kLogPath.UTF8String, &st) == 0 && st.st_size > kLogCap) return;
        FILE *file = fopen(kLogPath.UTF8String, "a");
        if (!file) return;
        fprintf(file, "%s\n", message.UTF8String ?: "");
        fclose(file);
    });
}

#pragma mark - guard

BOOL LGGuardShouldLoad(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:kKillPath]) {
        LGLog(@"kill switch present (%@); not loading", kKillPath);
        return NO;
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSArray *previous = [NSArray arrayWithContentsOfFile:kGuardPath];
    for (id value in previous) {
        if ([value isKindOfClass:NSNumber.class] && now - [value doubleValue] < 60.0)
            [starts addObject:value];
    }
    [starts addObject:@(now)];
    [starts writeToFile:kGuardPath atomically:YES];

    // 3 SpringBoard launches inside 60 s without surviving to the "stable" mark = crash loop
    if (starts.count >= 3) {
        [@"crash loop detected; delete this file and respring to re-enable\n"
            writeToFile:kKillPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [fm removeItemAtPath:kGuardPath error:nil];
        LGLog(@"crash loop detected; wrote kill switch and not loading");
        return NO;
    }
    return YES;
}

void LGGuardMarkStable(void) {
    [NSFileManager.defaultManager removeItemAtPath:kGuardPath error:nil];
    LGLog(@"stable: survived startup window");
}

#pragma mark - metal guard

void LGGuardCheckMetalMarker(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:kMetalMarkerPath]) return;
    // last run died before Metal glass was proven stable: keep blur only until the flag is deleted
    [@"SpringBoard went down shortly after Metal glass was enabled; delete this file to retry\n"
        writeToFile:kNoMetalPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [fm removeItemAtPath:kMetalMarkerPath error:nil];
    LGLog(@"metal marker found at launch: wrote nometal flag, using blur renderer");
}

BOOL LGMetalAllowed(void) {
    return ![NSFileManager.defaultManager fileExistsAtPath:kNoMetalPath];
}

void LGMetalMarkerSet(void) {
    [@"loading\n" writeToFile:kMetalMarkerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

void LGMetalMarkerClear(void) {
    [NSFileManager.defaultManager removeItemAtPath:kMetalMarkerPath error:nil];
}

#pragma mark - prefs

static NSDictionary *LGPrefs(void) {
    static NSDictionary *cache;
    static CFAbsoluteTime last;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!cache || now - last > 5.0) {
        CFStringRef domain = CFSTR("com.jjlulz.liquidass12");
        CFPreferencesAppSynchronize(domain);
        CFDictionaryRef values = CFPreferencesCopyMultiple(NULL, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSDictionary *dictionary = CFBridgingRelease(values);
        cache = [dictionary isKindOfClass:NSDictionary.class] ? dictionary : @{};
        last = now;
    }
    return cache;
}

BOOL LGPrefBool(NSString *key, BOOL fallback) {
    id value = LGPrefs()[key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

CGFloat LGPrefFloat(NSString *key, CGFloat fallback) {
    id value = LGPrefs()[key];
    return [value isKindOfClass:NSNumber.class] ? (CGFloat)[value doubleValue] : fallback;
}

BOOL LGHostEnabled(NSString *prefix) {
    if (!LGPrefBool(@"Global.Enabled", YES)) return NO;
    // lock screen / notification center platters are many layers on an A8, so off by default
    BOOL fallback = ![prefix isEqualToString:@"Notification"];
    return LGPrefBool([prefix stringByAppendingString:@".Enabled"], fallback);
}

#pragma mark - private view lookup

static UIView *LGIvarView(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return nil;
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding || encoding[0] != '@') return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

UIView *LGFindView(id object, NSArray<NSString *> *names) {
    if (!object) return nil;
    for (NSString *name in names) {
        UIView *view = LGIvarView(object, [@"_" stringByAppendingString:name].UTF8String);
        if (!view) view = LGIvarView(object, name.UTF8String);
        if (view) return view;
        SEL selector = NSSelectorFromString(name);
        if ([object respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
            if ([value isKindOfClass:UIView.class]) return value;
        }
    }
    return nil;
}
