import Foundation
import LocalAuthentication

enum Authenticator {
    /// True when the device has Face ID, Touch ID or a passcode to authenticate with.
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Face ID / Touch ID with passcode fallback. Completion runs on the main thread.
    /// Devices without any passcode have nothing to lock with and pass straight through.
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async { completion(true) }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
