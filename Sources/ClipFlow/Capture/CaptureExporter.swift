import AppKit

/// Seçili bölgeyi işaretlemeleriyle birlikte tam çözünürlükte üretir ve
/// panoya yazar. ClipFlow'un pano izleyicisi bu görüntüyü normal yoldan
/// yakalayıp geçmişe ekler.
enum CaptureExporter {
    /// - Parameters:
    ///   - image: Ekranın donmuş görüntüsü (piksel).
    ///   - viewSize: Overlay görünümünün nokta boyutu (= ekran boyutu).
    ///   - selection: Görünüm koordinatlarında seçim (sol alt köken).
    static func render(
        image: CGImage,
        viewSize: CGSize,
        selection: CGRect,
        annotations: [Annotation]
    ) -> CGImage? {
        let sx = CGFloat(image.width) / viewSize.width
        let sy = CGFloat(image.height) / viewSize.height

        // CGImage kırpma sol üst kökenlidir.
        let pixelRect = CGRect(
            x: selection.minX * sx,
            y: (viewSize.height - selection.maxY) * sy,
            width: selection.width * sx,
            height: selection.height * sy
        ).integral
        guard let cropped = image.cropping(to: pixelRect) else { return nil }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: cropped.width,
            height: cropped.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) ?? CGContext(
            data: nil,
            width: cropped.width,
            height: cropped.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))

        // İşaretlemeler görünüm koordinatlarında: aynı dönüşümle çiz.
        ctx.scaleBy(x: sx, y: sy)
        ctx.translateBy(x: -pixelRect.minX / sx, y: -(viewSize.height * sy - pixelRect.maxY) / sy)
        ctx.clip(to: selection)
        annotations.forEach { $0.draw(in: ctx) }

        return ctx.makeImage()
    }

    /// PNG + TIFF olarak yazar; görüntünün nokta boyutu Retina DPI'ını taşır.
    @discardableResult
    static func copyToPasteboard(_ image: CGImage, pointSize: CGSize) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }
}
