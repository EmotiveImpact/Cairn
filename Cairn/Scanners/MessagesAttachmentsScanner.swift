import Foundation

/// Messages attachments are often the biggest personal thing on a small Mac.
/// Cairn shows how much they take and where to review them, and never removes
/// them itself (Library/Messages stays protected in SafePaths).
struct MessagesAttachmentsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "messages-attachments",
        title: "Messages Attachments",
        subtitle: "Photos and videos sent in chats",
        systemImage: "message.fill",
        group: .general,
        requiresFDA: true
    )

    func scan(_ ctx: ScanContext) async {
        ctx.progress("Messages attachments")
        let url = MessagesAttachments.folder()
        guard let found = MessagesAttachments.measure(url), found.bytes >= ctx.minSizeBytes else { return }
        if ctx.isCancelled() { return }
        var note = "Messages · \(found.breakdown). Review and delete them in System Settings › General › Storage › Messages, so chats stay intact. With Messages in iCloud, a delete there removes them from every device."
        if found.partial { note += " · large (partial size)" }
        ctx.emit(ScanItem(
            url: url,
            allocatedSize: found.bytes,
            itemCount: found.count,
            categoryID: info.id,
            severity: .review,
            isRegenerable: false,
            cleanMethod: .adviceOnly,
            note: note,
            volumeURL: FileScan.volumeURL(of: url),
            selected: false
        ))
    }
}
