import UIKit

enum ImagePreprocessor {
    static func preprocess(_ image: UIImage, maxLongEdge: CGFloat = 1800, jpegQuality: CGFloat = 0.8) -> Data? {
        let resized = resize(image, maxLongEdge: maxLongEdge)
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    private static func resize(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let maxCurrentEdge = max(size.width, size.height)
        guard maxCurrentEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / maxCurrentEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
