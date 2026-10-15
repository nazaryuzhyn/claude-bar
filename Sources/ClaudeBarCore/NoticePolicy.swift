import Foundation

public enum NoticePolicy {
    /// No banner while the app the session runs in is in front: the user is most likely
    /// looking at it. Only the app is known, not its window, so a session in another
    /// window of that app is held back too; its sound still plays.
    public static func showsBanner(host: String?, frontmost: String?) -> Bool {
        guard let host, let frontmost else { return true }
        return host != frontmost
    }
}
