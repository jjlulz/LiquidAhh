#pragma once
#import <UIKit/UIKit.h>

// logging (capped file: /var/mobile/liquidass12-debug.txt)
void LGLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// crash-loop guard + kill switch
BOOL LGKillSwitchPresent(void);   // /var/mobile/liquidass12.disabled
BOOL LGGuardShouldLoad(void);
void LGGuardMarkStable(void);

// Metal glass safety: a crash soon after Metal was enabled turns Metal off (blur stays)
void LGGuardCheckMetalMarker(void);   // call early in the ctor
BOOL LGMetalAllowed(void);
void LGMetalMarkerSet(void);
void LGMetalMarkerClear(void);

// activation gate (hooks record views always, but only touch them once active)
BOOL LGActive(void);
void LGSetActive(BOOL active);

// prefs: /var/mobile/Library/Preferences/com.jjlulz.liquidass12.plist
BOOL    LGPrefBool(NSString *key, BOOL fallback);
CGFloat LGPrefFloat(NSString *key, CGFloat fallback);
BOOL    LGHostEnabled(NSString *prefix);

// safe runtime lookup of a private child view (ivar first, then selector)
UIView *LGFindView(id object, NSArray<NSString *> *names);
