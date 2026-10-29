import Foundation

/// An exclusive lock on a file, held while an export runs, so two exports into one folder, like the
/// app's and the command line tool's, never overlap. The lock file is left in place, empty, so
/// there's nothing to clean up afterward.
enum FileLock {
    /// Runs `body` holding the lock, or returns nil straight away if someone else holds it. Throws
    /// if the lock can't be taken for any other reason.
    static func run<T>(at url: URL, _ body: () throws -> T) throws -> T? {
        // Never through a link, so a planted one can't make an empty file somewhere else.
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o644)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path]) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            // Someone else holding it means try later; anything else, like a disk that can't lock
            // files, is a failure of its own.
            let code = errno
            if code == EWOULDBLOCK { return nil }
            throw CocoaError(.fileLocking, userInfo: [NSFilePathErrorKey: url.path, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
