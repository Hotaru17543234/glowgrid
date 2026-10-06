import Foundation

/// The shared container that both the app and the widget read and write.
///
/// When the app is sideloaded with a free Apple ID, SideStore / AltStore re-sign it and
/// rename the App Group (the team ID is appended). They list the real name under the
/// `ALTAppGroups` key in Info.plist, and it is also in the embedded provisioning profile,
/// so we look in all of those places and use the first group we can actually open.
enum AppGroup {
    static let configured = "group.com.hotaru.glowgrid"

    static let identifier: String? = {
        var candidates: [String] = [AppGroup.configured]

        var bundles: [Bundle] = [Bundle.main]
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex",
           let app = Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent()) {
            bundles.append(app)
        }
        for b in bundles {
            if let list = b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
                candidates.append(contentsOf: list)
            }
            candidates.append(contentsOf: AppGroup.profileGroups(in: b))
        }

        let fm = FileManager.default
        for c in candidates where c == AppGroup.configured || c.hasPrefix(AppGroup.configured + ".") {
            if fm.containerURL(forSecurityApplicationGroupIdentifier: c) != nil { return c }
        }
        for c in candidates {
            if fm.containerURL(forSecurityApplicationGroupIdentifier: c) != nil { return c }
        }
        return nil
    }()

    /// True when the app and the widget really share one container.
    static var isShared: Bool { identifier != nil }

    static var containerURL: URL {
        let fm = FileManager.default
        if let id = identifier, let u = fm.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return u
        }
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// App groups listed in embedded.mobileprovision (a signed plist).
    private static func profileGroups(in bundle: Bundle) -> [String] {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else { return [] }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = xml.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any],
              let groups = ent["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups
    }
}
