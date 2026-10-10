import UIKit

enum OrientationController {
    /// Applies the orientation immediately, even if the device's rotation lock is on.
    static func apply(_ mode: OrientationMode) {
        AppDelegate.orientationMask = mode.mask

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mode.mask))

        var top = scene.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        top?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
