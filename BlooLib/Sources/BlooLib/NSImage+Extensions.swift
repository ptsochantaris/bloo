#if canImport(AppKit)
    import AppKit

    public extension Data {
        var asImage: NSImage? {
            NSImage(data: self)
        }
    }

    public extension NSImage {
        var jpegData: Data? {
            guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        }

        static func block(color: NSColor, size: CGSize) -> NSImage {
            let image = NSImage(size: size)
            image.lockFocus()
            color.drawSwatch(in: NSRect(origin: .zero, size: size))
            image.unlockFocus()
            return image
        }

        func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0) -> NSImage {
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

            let imageRef = cgImage(forProposedRect: nil, context: nil, hints: nil)!
            c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: drawnImageWidthPixels, height: drawnImageHeightPixels))
            return NSImage(cgImage: c.makeImage()!, size: targetSize)
        }

        convenience init?(systemName _: String) {
            self.init(systemSymbolName: "circle", accessibilityDescription: nil)
        }

        func template(with tint: NSColor) -> NSImage {
            let image = copy() as! NSImage
            image.isTemplate = false
            image.lockFocus()
            tint.set()

            let imageRect = NSRect(origin: .zero, size: image.size)
            imageRect.fill(using: .sourceAtop)
            image.unlockFocus()
            return image
        }

        static func tintedShape(systemName: String, coloured: NSColor) -> NSImage? {
            let img = NSImage(systemName: systemName)
            return img?.template(with: coloured)
        }
    }
#endif
