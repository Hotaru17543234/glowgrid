import SwiftUI
import UIKit

/// Where a background picture is shown. Each one has its own crop.
enum BGTarget: String, Codable, CaseIterable, Identifiable {
    case app, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .app: return "App 背景"
        case .medium: return "中号小组件"
        case .large: return "大号小组件"
        }
    }

    /// width / height
    var aspect: CGFloat {
        switch self {
        case .app: return 9.0 / 19.5
        case .medium: return 338.0 / 158.0
        case .large: return 338.0 / 354.0
        }
    }

    /// Pixel size of the pre-rendered file (kept small so the widget stays under its memory limit).
    var pixelSize: CGSize {
        switch self {
        case .app: return CGSize(width: 1080, height: 2340)
        case .medium: return CGSize(width: 1014, height: 474)
        case .large: return CGSize(width: 1014, height: 1062)
        }
    }
}

enum BGEffect: String, Codable, CaseIterable, Identifiable {
    case fade, push, slide, zoom, blur, kenBurns

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fade: return "淡入淡出"
        case .push: return "推入"
        case .slide: return "滑入"
        case .zoom: return "缩放淡入"
        case .blur: return "模糊溶解"
        case .kenBurns: return "缓慢推镜"
        }
    }

    /// Widgets only animate built-in transitions (max 2 s), so blur and slow zoom fall back to a fade there.
    var widgetTransition: AnyTransition {
        switch self {
        case .push: return .push(from: .trailing)
        case .slide: return .move(edge: .trailing).combined(with: .opacity)
        case .zoom: return .scale(scale: 1.15).combined(with: .opacity)
        default: return .opacity
        }
    }
}

struct BGImage: Codable, Identifiable, Equatable {
    var id: String
    /// Normalised crop rect (0...1) per target.
    var crops: [String: CGRect]

    func crop(_ t: BGTarget) -> CGRect? { crops[t.rawValue] }
}

struct BGSettings: Codable, Equatable {
    var images: [BGImage] = []
    var appEnabled = false
    var widgetEnabled = false
    /// Seconds between pictures in the app (0 = never change).
    var appInterval: Double = 30
    /// Minutes between pictures in the widget.
    var widgetInterval: Int = 60
    var effect: BGEffect = .fade
    /// How much the paper colour covers the picture (higher = text easier to read).
    var dim: Double = 0.55
    var shuffle = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case images, appEnabled, widgetEnabled, appInterval, widgetInterval, effect, dim, shuffle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        images = (try? c.decodeIfPresent([BGImage].self, forKey: .images)) ?? []
        appEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .appEnabled)) ?? false
        widgetEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .widgetEnabled)) ?? false
        appInterval = (try? c.decodeIfPresent(Double.self, forKey: .appInterval)) ?? 30
        widgetInterval = (try? c.decodeIfPresent(Int.self, forKey: .widgetInterval)) ?? 60
        let raw = (try? c.decodeIfPresent(String.self, forKey: .effect)) ?? ""
        effect = BGEffect(rawValue: raw) ?? .fade
        dim = (try? c.decodeIfPresent(Double.self, forKey: .dim)) ?? 0.55
        shuffle = (try? c.decodeIfPresent(Bool.self, forKey: .shuffle)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(images, forKey: .images)
        try c.encode(appEnabled, forKey: .appEnabled)
        try c.encode(widgetEnabled, forKey: .widgetEnabled)
        try c.encode(appInterval, forKey: .appInterval)
        try c.encode(widgetInterval, forKey: .widgetInterval)
        try c.encode(effect.rawValue, forKey: .effect)
        try c.encode(dim, forKey: .dim)
        try c.encode(shuffle, forKey: .shuffle)
    }

    /// Which picture is showing at a moment, for a given slot length.
    func imageID(at date: Date, slotSeconds: Double) -> String? {
        guard !images.isEmpty else { return nil }
        let n = images.count
        guard slotSeconds > 0 else { return images[0].id }
        let slot = Int(floor(date.timeIntervalSince1970 / slotSeconds))
        if !shuffle || n < 3 { return images[((slot % n) + n) % n].id }
        // A fixed shuffle that never shows the same picture twice in a row.
        func pick(_ s: Int) -> Int { Int((UInt64(abs(s)) &* 2654435761) % UInt64(n)) }
        var i = pick(slot)
        if i == pick(slot - 1) { i = (i + 1) % n }
        return images[i].id
    }
}

/// Files live in the shared container so the widget can read the small pre-rendered versions.
enum BackgroundStore {
    static var dir: URL {
        let d = AppGroup.containerURL.appendingPathComponent("Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var settingsURL: URL { dir.appendingPathComponent("settings.json") }

    static func originalURL(_ id: String) -> URL { dir.appendingPathComponent("\(id)-original.jpg") }

    static func fileURL(_ id: String, _ target: BGTarget) -> URL {
        dir.appendingPathComponent("\(id)-\(target.rawValue).jpg")
    }

    static func load() -> BGSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let s = try? JSONDecoder().decode(BGSettings.self, from: data) else { return BGSettings() }
        return s
    }

    static func save(_ s: BGSettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    static func image(_ id: String, _ target: BGTarget) -> UIImage? {
        UIImage(contentsOfFile: fileURL(id, target).path)
    }

    static func delete(_ id: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: originalURL(id))
        for t in BGTarget.allCases { try? fm.removeItem(at: fileURL(id, t)) }
    }
}
