import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ImagePreprocessor {
    enum OCRVariant: String, Codable, Hashable {
        case natural
        case enhanced
    }

    struct OCRCandidate {
        var variant: OCRVariant
        var image: UIImage
        var jpegData: Data
    }

    static func preprocess(_ image: UIImage, maxLongEdge: CGFloat = 1800, jpegQuality: CGFloat = 0.8) -> Data? {
        let candidates = prepareOCRCandidates(image, maxLongEdge: maxLongEdge, jpegQuality: jpegQuality)
        if let natural = candidates.first(where: { $0.variant == .natural }) {
            return natural.jpegData
        }
        return candidates.first?.jpegData
    }

    static func prepareOCRCandidates(
        _ image: UIImage,
        maxLongEdge: CGFloat = 1800,
        jpegQuality: CGFloat = 0.8
    ) -> [OCRCandidate] {
        let normalized = normalizeOrientation(image)
        let perspectiveCorrected = applyPerspectiveCorrectionIfPossible(normalized)
        let resized = resize(perspectiveCorrected, maxLongEdge: maxLongEdge)

        let natural = makeCandidate(from: resized, variant: .natural, jpegQuality: jpegQuality)

        let enhancedImage = enhanceForOCR(resized) ?? resized
        let enhanced = makeCandidate(from: enhancedImage, variant: .enhanced, jpegQuality: jpegQuality)

        return [natural, enhanced].compactMap { $0 }
    }

    private static func makeCandidate(
        from image: UIImage,
        variant: OCRVariant,
        jpegQuality: CGFloat
    ) -> OCRCandidate? {
        let flattened = renderOpaque(image)
        guard let data = flattened.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }
        return OCRCandidate(variant: variant, image: flattened, jpegData: data)
    }

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat(scale: image.scale))
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func applyPerspectiveCorrectionIfPossible(_ image: UIImage) -> UIImage {
        // Corner detection is intentionally deferred in this iteration.
        image
    }

    private static func enhanceForOCR(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else {
            return nil
        }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = input
        colorControls.contrast = 1.25
        colorControls.brightness = 0.02
        colorControls.saturation = 0.2

        let denoise = CIFilter.noiseReduction()
        denoise.inputImage = colorControls.outputImage
        denoise.noiseLevel = 0.02
        denoise.sharpness = 0.4

        guard
            let output = denoise.outputImage,
            let cgImage = ciContext.createCGImage(output, from: output.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func resize(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let maxCurrentEdge = max(size.width, size.height)
        guard maxCurrentEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / maxCurrentEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: rendererFormat(scale: image.scale))
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func renderOpaque(_ image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat(scale: image.scale))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func rendererFormat(scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = max(1, scale)
        return format
    }

    private static let ciContext = CIContext(options: nil)
}
