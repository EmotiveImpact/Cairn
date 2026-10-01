import Foundation

/// Legacy compatibility surface, intentionally inert. Alert-only monitoring is
/// owned by StorageControl. Old clean-on-quit preferences never arm deletion.
@MainActor
final class SmartTriggers {
    static let shared = SmartTriggers()
    private init() {}
    func start(store: ScanStore, isProUnlocked: @escaping () -> Bool) {}
    func stop() {}
}
