import Foundation

#if canImport(UIKit)
    import UIKit

    public extension Data {
        var asImage: UIImage? {
            UIImage(data: self)
        }
    }

    public extension UIImage {
        var jpegData: Data? {
            jpegData(compressionQuality: 0.7)
        }

        func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0) -> UIImage {
            let mySizePixelWidth = size.width
            let mySizePixelHeight = size.height

            let outputImagePixelWidth = targetSize.width
            let outputImagePixelHeight = targetSize.height

            let widthRatio = outputImagePixelWidth / mySizePixelWidth
            let heightRatio = outputImagePixelHeight / mySizePixelHeight

            let ratio: CGFloat = if limitTo < 1 {
                min(widthRatio, heightRatio) * limitTo
            } else {
                max(widthRatio, heightRatio) * limitTo
            }

            let drawnImageWidthPixels = Int(mySizePixelWidth * ratio)
            let drawnImageHeightPixels = Int(mySizePixelHeight * ratio)

            let offsetX = (Int(outputImagePixelWidth) - drawnImageWidthPixels) / 2
            let offsetY = (Int(outputImagePixelHeight) - drawnImageHeightPixels) / 2

            let c = CGContext(data: nil,
                              width: Int(outputImagePixelWidth),
                              height: Int(outputImagePixelHeight),
                              bitsPerComponent: 8,
                              bytesPerRow: Int(outputImagePixelWidth) * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!
            c.interpolationQuality = .high

            let imageRef = cgImage!
            c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: drawnImageWidthPixels, height: drawnImageHeightPixels))
            return UIImage(cgImage: c.makeImage()!)
        }
    }
#endif
