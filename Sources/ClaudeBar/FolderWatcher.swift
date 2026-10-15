import Foundation

/// Watches one folder's entries. The writers rename finished files into place, which the
/// folder reports as a write, so no polling is needed.
/// Adapted from Lunavect's SessionStore (MIT, see THIRD_PARTY_NOTICES).
final class FolderWatcher {
    private let source: DispatchSourceFileSystemObject

    /// `folderGone`: the folder itself was deleted or renamed. The descriptor still points at
    /// the old folder, so a folder created again under the same name goes unnoticed until the
    /// owner makes a new watcher.
    init?(url: URL, onChange: @escaping @Sendable (_ folderGone: Bool) -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )
        self.source = source
        source.setEventHandler { [weak source] in
            onChange(!(source?.data.isDisjoint(with: [.delete, .rename]) ?? true))
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
