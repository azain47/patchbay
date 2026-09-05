import AppKit
import CoreAudio
import Foundation

// MARK: - Model

/// One app sent to one output device, optionally through its own chain.
struct Route: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var name: String
    var outputUID: String
    var enabled = true
    var rack = RackSettings(modules: [])
}

final class RoutesStore {
    private let key = "routes.v1"
    private(set) var routes: [Route]

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let decoded = try? JSONDecoder().decode([Route].self, from: data) {
            routes = decoded
        } else {
            routes = []
        }
    }

    func save(_ routes: [Route]) {
        self.routes = routes
        if let data = try? JSONEncoder().encode(routes) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Apps connected to Core Audio

/// An application, as seen through the Core Audio process objects it (or its helpers) own.
struct AudioApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    var objects: [AudioObjectID]
    var playing: Bool
    var id: String { bundleID }

    static func icon(for bundleID: String) -> NSImage? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, let icon = app.icon { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum AudioProcesses {
    /// Every Core Audio client process grouped by the application that owns it.
    /// A process whose executable lives inside a `.app` bundle belongs to the nearest
    /// ancestor that is a real application (browser renderers, Electron utilities); one
    /// that lives outside any bundle (afplay, mpv, ffplay) is its own identity, so a player
    /// launched from a terminal is not swallowed by the terminal.
    static func apps() -> [AudioApp] {
        var byApp: [String: AudioApp] = [:]
        for object in processObjects() {
            guard let pid = pid(of: object), pid != getpid(), let path = executablePath(of: pid) else { continue }
            let playing = flag(object, kAudioProcessPropertyIsRunningOutput)
            let identity = path.contains(".app/") ? owningApplication(of: pid) ?? executableIdentity(path: path) : executableIdentity(path: path)
            guard let owner = identity else { continue }
            if var app = byApp[owner.bundleID] {
                app.objects.append(object)
                app.playing = app.playing || playing
                byApp[owner.bundleID] = app
            } else {
                byApp[owner.bundleID] = AudioApp(bundleID: owner.bundleID, name: owner.name, objects: [object], playing: playing)
            }
        }
        return byApp.values.sorted { ($0.playing ? 0 : 1, $0.name.lowercased()) < ($1.playing ? 0 : 1, $1.name.lowercased()) }
    }

    static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    /// Walks up the parent chain until a process that is a real application (regular or
    /// accessory activation policy), so helpers route with the app that spawned them.
    /// Nil when nothing in the chain is an application (a player launched from a shell).
    private static func owningApplication(of pid: pid_t) -> (bundleID: String, name: String)? {
        var current = pid
        var fallback: (String, String)?
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current), let bundleID = app.bundleIdentifier {
                let name = app.localizedName ?? bundleID
                if app.activationPolicy != .prohibited { return (bundleID, name) }
                if fallback == nil { fallback = (bundleID, name) }
            }
            guard let parent = parentPID(of: current), parent > 1, parent != current else { break }
            current = parent
        }
        return fallback
    }

    /// Command-line players (afplay, mpv, ffplay) have no application above them; they are
    /// grouped by executable name so a route can still target them. System daemons that
    /// happen to hold a Core Audio client (conference, accessibility, audio helpers) are
    /// recognised by where they live and left out.
    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func executableIdentity(path: String) -> (bundleID: String, name: String)? {
        let daemonPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/", "/private/var/"]
        if daemonPrefixes.contains(where: path.hasPrefix) || path.contains(".framework/") || path.contains(".xpc/") { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ("exec:\(name)", name)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
