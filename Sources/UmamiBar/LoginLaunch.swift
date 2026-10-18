import AppKit
import ServiceManagement

/// Reads the OS registration rather than mirroring a potentially stale boolean preference.
final class LoginLaunch {
    enum Status: Equatable { case off, enabled, requiresApproval, unavailable }
    private let bundleURL: URL
    private let legacyURL: URL
    init(bundleURL: URL = Bundle.main.bundleURL, legacyDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")) {
        self.bundleURL = bundleURL
        legacyURL = legacyDirectory.appendingPathComponent("app.umamibar.login.plist")
    }
    var status: Status {
        guard bundleURL.pathExtension == "app" else { return .unavailable }
        if #available(macOS 13.0, *) {
            let current = Self.registrationStatus(SMAppService.mainApp.status)
            if current == .off, FileManager.default.fileExists(atPath: legacyURL.path) {
                return Self.registrationStatus(SMAppService.statusForLegacyPlist(at: legacyURL))
            }
            return current
        }
        return FileManager.default.fileExists(atPath: legacyURL.path) ? .enabled : .off
    }
    @available(macOS 13.0, *)
    static func registrationStatus(_ status: SMAppService.Status) -> Status {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        // A main app may not have a service record until its first registration.
        // Keep the switch actionable so register() can create that record.
        case .notRegistered, .notFound: return .off
        @unknown default: return .unavailable
        }
    }
    func setEnabled(_ enabled: Bool) throws {
        guard bundleURL.pathExtension == "app" else { throw ServiceError.message(L("请从已安装的 UmamiBar.app 设置登录启动。")) }
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() }
            else if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            if FileManager.default.fileExists(atPath: legacyURL.path) { try FileManager.default.removeItem(at: legacyURL) }
        } else if enabled {
            // Catalina–Monterey: launchd reads this user agent on the next login. Do not start a second copy now.
            let values: [String: Any] = ["Label": "app.umamibar.login", "ProgramArguments": ["/usr/bin/open", "-g", "-a", bundleURL.path, "--args", "--launch-at-login"], "RunAtLoad": true]
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: legacyURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileManager.default.removeItem(at: legacyURL)
        }
    }
    func openSystemSettings() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
        else if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.users?startupItemsPref") { NSWorkspace.shared.open(url) }
    }
}
