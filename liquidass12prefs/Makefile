# the Swift/Metal part (LiquidGlassKit) needs the Swift 5 ABI runtime that ships with iOS 12.2+
TARGET := iphone:clang:latest:12.2

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LiquidAss12Prefs

LiquidAss12Prefs_FILES = LGRootListController.m LGGlassSwitchCell.m LGGlassSliderCell.m LGKBridge.m
LiquidAss12Prefs_FRAMEWORKS = UIKit QuartzCore Preferences
LiquidAss12Prefs_INSTALL_PATH = /Library/PreferenceBundles
LiquidAss12Prefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk

# Builds LGKCore.dylib (LiquidGlassKit ported to iOS 12) into the bundle. If this step fails the
# package still builds and Settings uses the Objective-C glass controls instead.
internal-stage::
	@sh ../scripts/build-lgk.sh "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/$(BUNDLE_NAME).bundle" || echo "[LGK] skipped: build failed, Settings will use the fallback controls"
