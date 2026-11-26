// Settings pane. Uses PreferenceLoader. Minimal declarations of the private Preferences classes
// so the bundle does not depend on header availability in the SDK.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface LGRootListController : PSListController
@end

static void *kSpecifiersKey = &kSpecifiersKey;

@implementation LGRootListController

// cached via an associated object so we never touch the superclass ivar directly
- (NSArray *)specifiers {
    NSArray *cached = objc_getAssociatedObject(self, kSpecifiersKey);
    if (!cached) {
        cached = [self loadSpecifiersFromPlistName:@"Root" target:self];
        objc_setAssociatedObject(self, kSpecifiersKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cached;
}

- (void)reenableMetal {
    unlink("/var/mobile/liquidass12-nometal");
    unlink("/var/mobile/liquidass12-metal-loading");
    [self respring];
}

- (void)respring {
    const char *path = access("/usr/bin/sbreload", X_OK) == 0 ? "/usr/bin/sbreload" : "/usr/bin/killall";
    const char *argvSB[] = { "sbreload", NULL };
    const char *argvKA[] = { "killall", "-9", "SpringBoard", NULL };
    pid_t pid;
    posix_spawn(&pid, path, NULL, NULL,
                (char *const *)(strstr(path, "sbreload") ? argvSB : argvKA), environ);
}

@end
