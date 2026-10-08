import ImageIO
import UIKit

/// Image work for background pictures: shrink on import, crop, and render the small files the widget reads.
enum ImageTools {
    /// Decode and shrink in one step (also applies the photo's rotation).
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// The largest centred rect with the given aspect (width / height), normalised to 0...1.
    static func centeredCrop(imageSize: CGSize, aspect: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let imageAspect = imageSize.width / imageSize.height
        if imageAspect > aspect {
            let w = aspect / imageAspect
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        } else {
            let h = imageAspect / aspect
            return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
    }

    /// Draw the cropped part of `image` into a canvas of `size` pixels.
    static func render(_ image: UIImage, crop: CGRect, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let iw = image.size.width, ih = image.size.height
        let scale = size.width / max(1, crop.width * iw)
        let drawRect = CGRect(x: -crop.minX * iw * scale,
                              y: -crop.minY * ih * scale,
                              width: iw * scale,
                              height: ih * scale)
        return renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: drawRect)
        }
    }

    /// Render and save one target's file.
    static func writeTarget(id: String, original: UIImage, crop: CGRect, target: BGTarget) {
        let out = render(original, crop: crop, size: target.pixelSize)
        if let data = out.jpegData(compressionQuality: 0.82) {
            try? data.write(to: BackgroundStore.fileURL(id, target), options: .atomic)
        }
    }

    /// Import one picture: keep a shrunk original plus one rendered file per target.
    static func importPicture(_ data: Data) -> BGImage? {
        guard let original = downsample(data, maxPixel: 2400),
              let jpeg = original.jpegData(compressionQuality: 0.88) else { return nil }
        let id = UUID().uuidString
        try? jpeg.write(to: BackgroundStore.originalURL(id), options: .atomic)
        var crops: [String: CGRect] = [:]
        for t in BGTarget.allCases {
            let c = centeredCrop(imageSize: original.size, aspect: t.aspect)
            crops[t.rawValue] = c
            writeTarget(id: id, original: original, crop: c, target: t)
        }
        return BGImage(id: id, crops: crops)
    }
}
