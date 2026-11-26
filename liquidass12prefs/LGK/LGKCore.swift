// Entry points used by the Objective-C settings bundle (loaded with dlopen at runtime).
import UIKit

@objc(LGKCore)
public final class LGKCore: NSObject {

    static var resourceDirectory = ""

    /// Directory that holds the .metal sources shipped next to this dylib.
    @objc public class func configure(withResourceDirectory path: String) {
        resourceDirectory = path
    }

    /// True only if Metal works and the glass shaders compile and link on this device.
    @MainActor @objc public class func isAvailable() -> Bool {
        LiquidGlassRenderer.shared != nil
    }
}
