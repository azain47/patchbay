import Cocoa
import Combine
import Sparkle

/// In-app updates through Sparkle. The feed (SUFeedURL) is the appcast.xml attached to the
/// latest GitHub release; every update is verified against SUPublicEDKey and must be signed
/// with the same certificate as the running app before Sparkle installs it.
///
/// patchbay lives in the menu bar, so a scheduled check that finds an update doesn't throw a
/// window over whatever the user is doing: it raises `available`, shown as a dot on the
/// settings gear and a row in Settings, unless Sparkle judges the moment right for focus
/// (just launched, or the machine was idle).
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// Version string of an update found by a background check and not yet looked at.
    @Published private(set) var available: String?
    @Published private(set) var canCheck = false

    private var controller: SPUStandardUpdaterController!
    private var sink: AnyCancellable?

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    }

    func start() {
        controller.startUpdater()
        sink = controller.updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).sink { [weak self] in self?.canCheck = $0 }
    }

    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    /// User-initiated check, or bringing a found update into focus. The popover's app is an
    /// accessory, so activate first or Sparkle's window opens behind the frontmost app.
    func check() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { available = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { available = nil }

    func standardUserDriverWillFinishUpdateSession() { available = nil }
}
