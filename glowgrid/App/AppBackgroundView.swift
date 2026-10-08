import SwiftUI
import UIKit

/// The app's background: the paper colour, or the user's pictures as a slideshow.
struct AppBackgroundView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.bg
        Group {
            if s.appEnabled && !s.images.isEmpty {
                TimelineView(.periodic(from: .now, by: s.appInterval > 0 ? s.appInterval : 3600)) { ctx in
                    SlideshowLayer(imageID: s.imageID(at: ctx.date, slotSeconds: s.appInterval) ?? "",
                                   effect: s.effect,
                                   interval: s.appInterval,
                                   version: model.bgVersion)
                }
                .overlay(Palette.paper.opacity(s.dim))
            } else {
                Palette.paper
            }
        }
        .ignoresSafeArea()
    }
}

struct SlideshowLayer: View {
    let imageID: String
    let effect: BGEffect
    let interval: Double
    let version: Int

    var body: some View {
        ZStack {
            BGPicture(imageID: imageID, target: .app, effect: effect, interval: interval, version: version)
                .id("\(imageID)-\(version)")
                .transition(swapTransition)
        }
        .animation(.easeInOut(duration: effect == .kenBurns ? 2.0 : 1.2), value: imageID)
    }

    private var swapTransition: AnyTransition {
        switch effect {
        case .fade, .kenBurns: return .opacity
        case .push: return .push(from: .trailing)
        case .slide: return .move(edge: .trailing).combined(with: .opacity)
        case .zoom: return .scale(scale: 1.12).combined(with: .opacity)
        case .blur: return .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
        }
    }
}

struct BlurFade: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 24 * amount)
            .opacity(Double(1 - amount))
    }
}

/// One background picture filling its space. "缓慢推镜" slowly zooms in while it shows.
struct BGPicture: View {
    let imageID: String
    let target: BGTarget
    let effect: BGEffect
    let interval: Double
    let version: Int

    @State private var zoomed = false

    private static let cache = NSCache<NSString, UIImage>()

    static func load(_ id: String, _ target: BGTarget, version: Int) -> UIImage? {
        let key = "\(id)-\(target.rawValue)-\(version)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = BackgroundStore.image(id, target) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    var body: some View {
        GeometryReader { geo in
            if let ui = Self.load(imageID, target, version: version) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(effect == .kenBurns && zoomed ? 1.12 : 1.0)
                    .clipped()
            } else {
                Palette.paper
            }
        }
        .onAppear {
            guard effect == .kenBurns else { return }
            withAnimation(.linear(duration: max(4, interval > 0 ? interval : 20))) { zoomed = true }
        }
    }
}
