import Foundation
import CryptoKit
import Darwin

/// The filesystem steps behind every move to a drive. Nothing here touches the
/// UI, so the diagnostics can drive it against disposable folders.
///
/// The rule throughout: the original is only removed after the drive copy has
/// been read back from the drive itself and matched, file by file. Every
/// failure before that point leaves the original where it was.
enum Relocation {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static let movingSuffix = ".cairn-moving"
    static let restoringSuffix = ".cairn-restoring"
    static let partialSuffix = ".partial"
    static let chunk = 1 << 20

    /// How the owning app keeps finding its files after a move.
    enum Mode: String, Codable, Sendable {
        /// A link is left behind; the app follows it while the drive is plugged in.
        case linkBack
        /// Moved, not linked. Brought back with one click when needed.
        case archive
        /// Rebuildable data: nothing is copied, future data goes to the drive.
        case freshOnDrive
    }

    /// What a file looked like when it was listed. A change in any of these
    /// means something wrote to it.
    struct Stamp: Equatable, Sendable {
        let inode: UInt64
        let size: Int64
        let modified: Int64
        let changed: Int64
        init(_ info: stat) {
            inode = UInt64(info.st_ino); size = Int64(info.st_size)
            modified = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
            changed = Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
        }
    }

    /// Every entry under a root, by path relative to it. A root that is a
    /// single file has one file entry, "".
    struct Inventory: Sendable {
        var directories: [String] = []
        var files: [String] = []
        var links: [String] = []
        var sizes: [String: Int64] = [:]
        var linkTargets: [String: String] = [:]
        var stamps: [String: Stamp] = [:]
        var bytes: Int64 = 0
        var isSingleFile: Bool { files == [""] }

        /// Same names, sizes and link targets. Stamps differ between copies.
        func sameContent(as other: Inventory) -> Bool {
            directories.sorted() == other.directories.sorted() && files.sorted() == other.files.sorted()
                && links.sorted() == other.links.sorted() && sizes == other.sizes && linkTargets == other.linkTargets
        }
        /// Nothing written, added or removed since `other` was listed.
        func unchanged(since other: Inventory) -> Bool { sameContent(as: other) && stamps == other.stamps }
    }

    private static func fileType(_ path: String) -> mode_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }
    static func isRealDirectory(_ url: URL) -> Bool { fileType(url.path) == S_IFDIR }
    static func isRegularFile(_ url: URL) -> Bool { fileType(url.path) == S_IFREG }
    static func isLink(_ url: URL) -> Bool { fileType(url.path) == S_IFLNK }
    static func exists(_ url: URL) -> Bool { fileType(url.path) != nil }
    static func linkDestination(_ url: URL) -> String? {
        guard isLink(url) else { return nil }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }
    private static func url(_ root: URL, _ relative: String) -> URL {
        relative.isEmpty ? root : root.appendingPathComponent(relative)
    }

    // SF_DATALESS: a cloud placeholder whose contents live online. Reading it
    // would start a download, so it is never copied.
    private static let datalessFlag: UInt32 = 0x4000_0000

    /// Lists a folder (or one file). Ordinary files, folders and links that
    /// stay inside the folder are fine. Hard links, sockets, devices, links
    /// that point outside and cloud placeholders stop the move, because
    /// copying them would not give the app back what it had.
    static func inventory(_ root: URL, cancel: CancelBox) throws -> Inventory {
        var result = Inventory()
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0 else { throw Failure(message: "\(root.path) could not be found.") }
        func addFile(_ relative: String, _ path: URL, _ info: stat) throws {
            if info.st_nlink > 1 {
                throw Failure(message: "\(path.path) is shared with another file (a hard link). Cairn cannot move it without breaking that.")
            }
            if info.st_flags & datalessFlag != 0 {
                throw Failure(message: "\(path.path) is only in the cloud. Nothing was moved.")
            }
            result.files.append(relative)
            result.sizes[relative] = Int64(info.st_size)
            result.stamps[relative] = Stamp(info)
            result.bytes += Int64(info.st_size)
        }
        switch rootInfo.st_mode & S_IFMT {
        case S_IFREG: try addFile("", root, rootInfo); return result
        case S_IFDIR: break
        default: throw Failure(message: "\(root.path) is not an ordinary file or folder.")
        }
        var stack: [String] = [""]
        while let relative = stack.popLast() {
            if cancel.isCancelled { throw Failure(message: "Stopped. Nothing was moved.") }
            let folder = url(root, relative)
            let names: [String]
            do { names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() }
            catch { throw Failure(message: "Cairn could not open \(folder.path). It may need Full Disk Access.") }
            for name in names {
                let child = relative.isEmpty ? name : relative + "/" + name
                let path = root.appendingPathComponent(child)
                var info = stat()
                guard lstat(path.path, &info) == 0 else { throw Failure(message: "Could not read \(path.path).") }
                switch info.st_mode & S_IFMT {
                case S_IFDIR: result.directories.append(child); stack.append(child)
                case S_IFREG: try addFile(child, path, info)
                case S_IFLNK:
                    guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path.path),
                          staysInside(link: child, target: target) else {
                        throw Failure(message: "\(path.path) points outside the folder. Cairn only moves folders that hold their own files.")
                    }
                    result.links.append(child)
                    result.linkTargets[child] = target
                default:
                    throw Failure(message: "\(path.path) is a special file that is in use. Close the app that owns it and try again.")
                }
            }
        }
        return result
    }

    /// A relative link that resolves inside the moved folder keeps working on
    /// the drive. An absolute link, or one that climbs out, would not.
    static func staysInside(link: String, target: String) -> Bool {
        guard !target.hasPrefix("/"), !target.isEmpty else { return false }
        var parts = link.split(separator: "/").dropLast().map(String.init)
        for piece in target.split(separator: "/", omittingEmptySubsequences: true) {
            if piece == "." { continue }
            if piece == ".." { guard !parts.isEmpty else { return false }; parts.removeLast() }
            else { parts.append(String(piece)) }
        }
        return true
    }

    private static func allZero(_ bytes: UnsafeRawBufferPointer) -> Bool {
        var index = 0
        let count = bytes.count
        while index + 8 <= count {
            if bytes.loadUnaligned(fromByteOffset: index, as: UInt64.self) != 0 { return false }
            index += 8
        }
        while index < count { if bytes[index] != 0 { return false }; index += 1 }
        return true
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// Copies one file, hashing the original as it is read. Whole empty chunks
    /// become holes, so a mostly-empty disk image stays small on the drive.
    /// The copy is written past the Mac's memory cache and flushed to the
    /// drive's media before returning.
    static func copyFile(_ from: URL, _ to: URL, expected: Stamp?, cancel: CancelBox,
                         progress: (Int64) -> Void = { _ in }) throws -> String {
        let input = open(from.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard input >= 0 else { throw Failure(message: "Could not open \(from.path).") }
        defer { close(input) }
        var opened = stat()
        guard fstat(input, &opened) == 0, (opened.st_mode & S_IFMT) == S_IFREG else { throw Failure(message: "\(from.path) is not an ordinary file.") }
        if let expected, Stamp(opened) != expected {
            throw Failure(message: "\(from.path) changed after it was listed. Close the app using it and try again. The original is untouched.")
        }
        let output = open(to.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw Failure(message: "Could not create \(to.path). The drive may be full or read-only.") }
        var closed = false
        defer { if !closed { close(output) } }
        _ = fcntl(output, F_NOCACHE, 1)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            if cancel.isCancelled { throw Failure(message: "Stopped. The original is untouched.") }
            let count = read(input, buffer, chunk)
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure(message: "Could not read \(from.path). The original is untouched.")
            }
            if count == 0 { break }
            let bytes = UnsafeRawBufferPointer(start: buffer, count: count)
            hasher.update(bufferPointer: bytes)
            if count == chunk && allZero(bytes) {
                guard lseek(output, off_t(count), SEEK_CUR) >= 0 else { throw Failure(message: "Could not write to \(to.path).") }
            } else {
                var written = 0
                while written < count {
                    let step = write(output, buffer.advanced(by: written), count - written)
                    if step < 0 {
                        if errno == EINTR { continue }
                        throw Failure(message: errno == ENOSPC ? "The drive is full. The original is untouched."
                                                               : "Could not write to \(to.path). The original is untouched.")
                    }
                    written += step
                }
            }
            total += Int64(count)
            progress(Int64(count))
        }
        guard ftruncate(output, off_t(total)) == 0 else { throw Failure(message: "Could not finish \(to.path). The original is untouched.") }
        var ended = stat()
        guard fstat(input, &ended) == 0, Stamp(ended) == Stamp(opened), total == Int64(opened.st_size) else {
            throw Failure(message: "\(from.path) changed while it was copied. Close the app using it and try again. The original is untouched.")
        }
        // Permissions, dates, Finder tags and other details. A file whose
        // details cannot all be copied keeps its contents, which is what counts.
        _ = copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_SECURITY | COPYFILE_XATTR | COPYFILE_STAT))
        // F_FULLFSYNC asks the drive to put the data on its media, not just in
        // its own cache. Some drives refuse it; plain fsync is the fallback.
        if fcntl(output, F_FULLFSYNC) != 0 && fsync(output) != 0 {
            throw Failure(message: "The drive did not confirm it saved \(to.lastPathComponent). The original is untouched.")
        }
        closed = true
        guard close(output) == 0 else { throw Failure(message: "The drive did not confirm it saved \(to.lastPathComponent). The original is untouched.") }
        return hex(hasher.finalize())
    }

    /// Reads a file back with the Mac's cache bypassed, so the check reflects
    /// what is really on the drive.
    static func readBackDigest(_ url: URL, cancel: CancelBox) -> String? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_NOCACHE, 1)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        while true {
            if cancel.isCancelled { return nil }
            let count = read(descriptor, buffer, chunk)
            if count < 0 { if errno == EINTR { continue }; return nil }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
        }
        return hex(hasher.finalize())
    }

    /// Copies a folder (or one file) into a fresh `.partial` beside the
    /// destination, reads every file back and matches it, then gives the copy
    /// its real name. Nothing that already exists is ever replaced.
    @discardableResult
    static func copyTree(from source: URL, to destination: URL, cancel: CancelBox,
                         destinationValid: () -> Bool, progress: (Int64) -> Void = { _ in }) throws -> Inventory {
        let plan = try inventory(source, cancel: cancel)
        guard !exists(destination) else { throw Failure(message: "\(destination.path) already exists. Nothing was replaced.") }
        let partial = URL(fileURLWithPath: destination.path + partialSuffix)
        guard !exists(partial) else { throw Failure(message: "An unfinished copy is at \(partial.path). Cairn will tidy it away; try again in a moment.") }
        guard destinationValid() else { throw Failure(message: "The drive is no longer available. Nothing was moved.") }
        var copied: Int64 = 0
        func interrupted() -> Failure { Failure(message: "The drive went away during the copy. The original is untouched.") }
        if plan.isSingleFile {
            let digest = try copyFile(source, partial, expected: plan.stamps[""], cancel: cancel) { copied += $0; progress(copied) }
            guard destinationValid() else { throw interrupted() }
            guard readBackDigest(partial, cancel: cancel) == digest else {
                throw Failure(message: "The copy on the drive did not match the original. Try another cable or drive. The original is untouched.")
            }
        } else {
            guard mkdir(partial.path, 0o700) == 0 else { throw Failure(message: "Could not create a folder on the drive. It may be full or read-only.") }
            for folder in plan.directories.sorted() {
                guard mkdir(partial.appendingPathComponent(folder).path, 0o700) == 0 else {
                    throw Failure(message: "Could not create \(folder) on the drive.")
                }
            }
            for file in plan.files {
                guard !cancel.isCancelled else { throw Failure(message: "Stopped. The original is untouched.") }
                guard destinationValid() else { throw interrupted() }
                let to = partial.appendingPathComponent(file)
                let digest = try copyFile(source.appendingPathComponent(file), to, expected: plan.stamps[file], cancel: cancel) {
                    copied += $0; progress(copied)
                }
                guard destinationValid() else { throw interrupted() }
                guard readBackDigest(to, cancel: cancel) == digest else {
                    if cancel.isCancelled { throw Failure(message: "Stopped. The original is untouched.") }
                    throw Failure(message: "\(file) did not match on the drive. Try another cable or drive. The original is untouched.")
                }
            }
            for link in plan.links {
                guard let target = plan.linkTargets[link], symlink(target, partial.appendingPathComponent(link).path) == 0 else {
                    throw Failure(message: "Could not recreate the link \(link) on the drive.")
                }
            }
            // Folder details last, deepest first: writing into a folder changes its dates.
            for folder in plan.directories.sorted(by: { $0.count > $1.count }) {
                _ = copyfile(source.appendingPathComponent(folder).path, partial.appendingPathComponent(folder).path, nil,
                             copyfile_flags_t(COPYFILE_SECURITY | COPYFILE_XATTR | COPYFILE_STAT))
            }
            _ = copyfile(source.path, partial.path, nil, copyfile_flags_t(COPYFILE_SECURITY | COPYFILE_XATTR | COPYFILE_STAT))
            guard let landed = try? inventory(partial, cancel: cancel), landed.sameContent(as: plan) else {
                throw Failure(message: "The copy on the drive is incomplete. The original is untouched.")
            }
        }
        // The original must not have changed while it was copied.
        guard let after = try? inventory(source, cancel: cancel), after.unchanged(since: plan) else {
            throw Failure(message: "Something changed in \(source.lastPathComponent) while it was copied. Close the app using it and try again. The original is untouched.")
        }
        guard destinationValid(), renamex_np(partial.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw Failure(message: "The checked copy could not be finished on the drive. The original is untouched.")
        }
        let parent = open(destination.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if parent >= 0 { _ = fcntl(parent, F_FULLFSYNC); close(parent) }
        return plan
    }

    /// Removes an unfinished `.partial` copy Cairn made. Only ever a path that
    /// ends in the suffix, so it cannot reach anything else.
    static func discardPartial(for destination: URL) {
        let partial = URL(fileURLWithPath: destination.path + partialSuffix)
        guard partial.lastPathComponent.hasSuffix(partialSuffix), exists(partial), !isLink(partial) else { return }
        try? FileManager.default.removeItem(at: partial)
    }

    /// Copy, check, set the original aside, leave a link (for app data), check
    /// the link, then remove the original. Every failure before the last step
    /// leaves the original in place under its own name.
    static func offload(source: URL, destination: URL, mode: Mode = .linkBack, cancel: CancelBox,
                        destinationValid: () -> Bool, progress: (Int64) -> Void = { _ in }) throws -> Inventory {
        guard isRealDirectory(source) || (mode == .archive && isRegularFile(source)) else {
            throw Failure(message: "\(source.path) is not an ordinary folder. It may already be on the drive.")
        }
        let moving = URL(fileURLWithPath: source.path + movingSuffix)
        guard !exists(moving) else { throw Failure(message: "A previous move did not finish at \(moving.path). Cairn sorts this out when it next starts.") }
        let copied: Inventory
        do {
            copied = try copyTree(from: source, to: destination, cancel: cancel, destinationValid: destinationValid, progress: progress)
        } catch {
            discardPartial(for: destination)
            throw error
        }
        func dropCopy(_ reason: String) -> Failure {
            try? FileManager.default.removeItem(at: destination)
            return Failure(message: reason)
        }
        // One last look in case something wrote to it after the copy finished.
        guard let current = try? inventory(source, cancel: cancel), current.unchanged(since: copied) else {
            throw dropCopy("Something changed in \(source.lastPathComponent) at the last moment. The original is untouched.")
        }
        guard renamex_np(source.path, moving.path, UInt32(RENAME_EXCL)) == 0 else {
            throw dropCopy("Could not set the original aside. It is untouched.")
        }
        func putBack(_ reason: String) -> Failure {
            if isLink(source) { unlink(source.path) }
            let restored = renamex_np(moving.path, source.path, UInt32(RENAME_EXCL)) == 0
            return Failure(message: reason + (restored ? " The original was put back." : " The original is at \(moving.path)."))
        }
        if mode == .linkBack {
            guard symlink(destination.path, source.path) == 0 else { throw putBack("Could not create the link.") }
            guard linkDestination(source) == destination.path, destinationValid(),
                  let linked = try? inventory(destination, cancel: cancel), linked.sameContent(as: copied) else {
                throw putBack("The link did not check out.")
            }
        } else {
            guard destinationValid(), let landed = try? inventory(destination, cancel: cancel), landed.sameContent(as: copied) else {
                throw putBack("The drive copy could not be checked a final time.")
            }
        }
        try FileManager.default.removeItem(at: moving)
        return copied
    }

    /// Rebuildable data (Xcode build files): the old files are removed, an
    /// empty folder is made on the drive and linked, so future data goes there.
    static func redirect(source: URL, destination: URL, destinationValid: () -> Bool) throws {
        guard isRealDirectory(source) || !exists(source) else { throw Failure(message: "\(source.path) is not an ordinary folder.") }
        let moving = URL(fileURLWithPath: source.path + movingSuffix)
        guard !exists(moving) else { throw Failure(message: "A previous move did not finish at \(moving.path).") }
        guard destinationValid() else { throw Failure(message: "The drive is no longer available. Nothing was changed.") }
        if !exists(destination) {
            guard mkdir(destination.path, 0o755) == 0 else { throw Failure(message: "Could not create a folder on the drive.") }
        } else {
            guard isRealDirectory(destination) else { throw Failure(message: "\(destination.path) already exists and is not a folder.") }
        }
        let hadFolder = exists(source)
        if hadFolder {
            guard renamex_np(source.path, moving.path, UInt32(RENAME_EXCL)) == 0 else { throw Failure(message: "Could not set the old folder aside. Nothing was changed.") }
        }
        guard symlink(destination.path, source.path) == 0, linkDestination(source) == destination.path else {
            if isLink(source) { unlink(source.path) }
            if hadFolder { _ = renamex_np(moving.path, source.path, UInt32(RENAME_EXCL)) }
            throw Failure(message: "Could not create the link. Nothing was changed.")
        }
        if hadFolder { try? FileManager.default.removeItem(at: moving) }
    }

    /// Copies the data back beside its old place, checks it, swaps it in, then
    /// removes the drive copy. The drive copy stays until the Mac copy checks out.
    static func restore(source: URL, destination: URL, mode: Mode = .linkBack, removeDriveCopy: Bool = true,
                        cancel: CancelBox, destinationValid: () -> Bool,
                        progress: (Int64) -> Void = { _ in }) throws -> Inventory {
        if mode == .linkBack {
            guard linkDestination(source) == destination.path else {
                throw Failure(message: "\(source.path) is no longer Cairn's link to \(destination.path). Nothing was changed.")
            }
        } else {
            guard !exists(source) else { throw Failure(message: "Something is already at \(source.path). Nothing was replaced.") }
        }
        let incoming = URL(fileURLWithPath: source.path + restoringSuffix)
        guard !exists(incoming) else { throw Failure(message: "A previous bring-back did not finish at \(incoming.path). Cairn sorts this out when it next starts.") }
        let copied: Inventory
        do {
            copied = try copyTree(from: destination, to: incoming, cancel: cancel, destinationValid: destinationValid, progress: progress)
        } catch {
            discardPartial(for: incoming)
            throw error
        }
        if mode == .linkBack {
            guard linkDestination(source) == destination.path, unlink(source.path) == 0 else {
                try? FileManager.default.removeItem(at: incoming)
                throw Failure(message: "The link changed during the bring-back. Nothing was changed.")
            }
        }
        guard renamex_np(incoming.path, source.path, UInt32(RENAME_EXCL)) == 0 else {
            if mode == .linkBack { _ = symlink(destination.path, source.path) }
            try? FileManager.default.removeItem(at: incoming)
            throw Failure(message: "Could not put the folder back in place. Nothing was changed.")
        }
        if removeDriveCopy, destinationValid() { try? FileManager.default.removeItem(at: destination) }
        return copied
    }

    /// A free name beside a drive copy kept after a bring-back, e.g.
    /// "models (kept 23 Oct 2026)", so a later move never collides with it.
    static func spareName(for destination: URL, date: Date = Date()) -> URL {
        let day = date.formatted(.dateTime.day().month(.abbreviated).year())
        let base = destination.deletingLastPathComponent()
        var candidate = base.appendingPathComponent("\(destination.lastPathComponent) (kept \(day))")
        var number = 2
        while exists(candidate) {
            candidate = base.appendingPathComponent("\(destination.lastPathComponent) (kept \(day) \(number))")
            number += 1
        }
        return candidate
    }

    /// Renames a kept drive copy to its spare name. Never replaces anything.
    static func keepAsSpare(_ destination: URL, at spare: URL) -> Bool {
        exists(destination) && !isLink(destination) && renamex_np(destination.path, spare.path, UInt32(RENAME_EXCL)) == 0
    }

    /// Takes a redirected folder back: an empty local folder replaces the link
    /// and the rebuildable files on the drive are removed.
    static func unredirect(source: URL, destination: URL, destinationValid: () -> Bool) throws {
        guard linkDestination(source) == destination.path else {
            throw Failure(message: "\(source.path) is no longer Cairn's link. Nothing was changed.")
        }
        guard unlink(source.path) == 0, mkdir(source.path, 0o755) == 0 else {
            if !exists(source) { _ = symlink(destination.path, source.path) }
            throw Failure(message: "Could not make a local folder again. The link was kept.")
        }
        if destinationValid(), isRealDirectory(destination) { try? FileManager.default.removeItem(at: destination) }
    }

    /// After a crash or power cut. Returns the state the item is really in,
    /// or nil when nothing was left half done.
    ///  - Original set aside, no link yet: put it back.
    ///  - Original set aside and the drive copy matches it: finish the move.
    ///  - Anything else unclear: leave both and ask.
    static func reconcile(source: URL, destination: URL? = nil, mode: Mode = .linkBack) -> RelocationRecord.Status? {
        let moving = URL(fileURLWithPath: source.path + movingSuffix)
        let incoming = URL(fileURLWithPath: source.path + restoringSuffix)
        let cancel = CancelBox()
        if let destination { discardPartial(for: destination) }
        discardPartial(for: incoming)
        if exists(incoming) {
            // A bring-back stopped after its checked copy landed. While the
            // link is still there the drive copy is the real one; drop the spare.
            if let destination, linkDestination(source) == destination.path || (mode == .archive && !exists(source)) {
                try? FileManager.default.removeItem(at: incoming)
                return .offloaded
            }
            return .needsReview
        }
        guard exists(moving) else { return nil }
        let linkReady = destination.map { mode == .linkBack ? linkDestination(source) == $0.path : !exists(source) } ?? false
        if linkReady, let destination,
           let original = try? inventory(moving, cancel: cancel),
           let copy = try? inventory(destination, cancel: cancel), copy.sameContent(as: original) {
            try? FileManager.default.removeItem(at: moving)
            return .offloaded
        }
        if let destination, linkDestination(source) == destination.path { unlink(source.path) }
        if !exists(source), renamex_np(moving.path, source.path, UInt32(RENAME_EXCL)) == 0 {
            if let destination, exists(destination) { try? FileManager.default.removeItem(at: destination) }
            return .interrupted
        }
        return .needsReview
    }
}
