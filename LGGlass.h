#pragma once
#import <UIKit/UIKit.h>

// YES only if CABackdropLayer + CAFilter(gaussianBlur) exist on this system
BOOL LGGlassSupported(void);

// Loads LiquidGlassKit (Metal) into SpringBoard. Safe to call once; returns whether Metal glass is usable.
BOOL LGMetalPrepare(void);

// Adds a glass layer as a child of `stock` (a stock blur/background view) and hides
// the stock view's own children. Returns nil (and leaves stock untouched) on any doubt.
UIView *LGInstallGlass(UIView *stock, NSString *prefix, CGFloat cornerRadius);

// Removes the glass and un-hides whatever it hid.
void LGRemoveGlass(UIView *stock);

// One-shot view tree dump to the debug log (tag is used once).
void LGDumpOnce(UIView *view, NSString *tag);
