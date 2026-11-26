// Settings pane. Uses PreferenceLoader. Minimal declarations of the private Preferences classes
// so the bundle does not depend on header availability in the SDK.
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)setSpecifiers:(NSArray *)specifiers;
@end

@interface LGRootListController : PSListController
@end

@implementation LGRootListController

- (NSArray *)specifiers {
    NSArray *specs = [self valueForKey:@"_specifiers"];
    if (!specs) {
        specs = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self setSpecifiers:specs];
    }
    return specs;
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

