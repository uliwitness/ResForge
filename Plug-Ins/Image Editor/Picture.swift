import AppKit
import RFSupport

// https://developer.apple.com/library/archive/documentation/mac/pdf/ImagingWithQuickDraw.pdf#page=727

struct Picture {
    static let version1: UInt16 = 0x1101 // 1-byte versionOp + version number
    static let version2: Int16 = -1
    static let extendedVersion2: Int16 = -2
    private var v1: Bool
    private var frame: QDRect
    private var clipRect: QDRect
    private var clipPath: NSBezierPath?
    private var origin = QDPoint(x: 0, y: 0)
    private var penPos = QDPoint(x: 0, y: 0)
    private var lastRect = QDRect(top: 0, left: 0, bottom: 0, right: 0)
    private var roundRectCornerSize = QDPoint(x: 8, y: 8)
    private var penSize = QDPoint(x: 1, y: 1)
    private var fgColor = CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    private var bgColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    private var penColor = CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // FG + BG + penPattern
    private var fillColor = CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // FG + BG + fillPattern
    private var penPatternImage: CGImage?
    private var fillPatternImage: CGImage?
    private var penPattern: Data?
    private var fillPattern: Data?

    var imageRep: NSBitmapImageRep
    var format: ImageFormat = .unknown
}

extension Picture {
    init(_ reader: BinaryDataReader, _ readOps: Bool = true) throws {
        try reader.advance(2) // v1 size
        frame = try QDRect(reader)

        let versionOp = try reader.read() as UInt16
        v1 = versionOp == Self.version1
        if !v1 {
            guard versionOp == PictOpcode.versionOp.rawValue,
                  try PictOpcode.read2(reader) == .version,
                  try PictOpcode.read2(reader) == .headerOp
            else {
                throw ImageReaderError.invalid
            }
            let headerVersion = try reader.read() as Int16
            if headerVersion == Self.version2 {
                try reader.advance(2 + 16 + 4) // ??, fixed-point bounding box, reserved
            } else if headerVersion == Self.extendedVersion2 {
                try reader.advance(2 + 4 + 4) // reserved, hRes, vRes
                // Set the frame to the source rect. This isn't strictly correct but it allows us
                // to decode some images which would otherwise fail due to mismatched frame sizes
                // (QuickDraw would normally scale such images to fit the frame).
                frame = try QDRect(reader)
                try reader.advance(4) // reserved
            } else {
                throw ImageReaderError.invalid
            }
        }

        origin = frame.origin
        clipRect = frame
        penPos = QDPoint(x: 0, y: 0)
        lastRect = QDRect(top: 0, left: 0, bottom: 0, right: 0)
        roundRectCornerSize = QDPoint(x: 8, y: 8)
        penSize = QDPoint(x: 1, y: 1)
        imageRep = ImageFormat.rgbaRep(width: frame.width, height: frame.height)
        if readOps {
            try self.readOps(reader)
        }
    }

    static func rep(_ data: Data, format: inout ImageFormat) -> NSBitmapImageRep? {
        let reader = BinaryDataReader(data)
        guard var pict = try? Self(reader, false) else {
            return nil
        }
        do {
            try pict.readOps(reader)
            format = pict.format
            return pict.imageRep
        } catch {
            // We may still be able to show the format even if decoding failed
            format = pict.format
            return nil
        }
    }

    enum ShapeMode {
        case stroke
        case fill
    }
    
    private func flipped(point: QDPoint) -> CGPoint {
        return CGPoint(x: point.x, y: frame.bottom - point.y - frame.top)
    }
    
    private func flipped(rect: QDRect, for shapeMode: ShapeMode) -> CGRect {
        let sizeInset = (shapeMode == .stroke) ? CGFloat(max(penSize.x, penSize.y)) : 0.0
        let lineInset = (shapeMode == .stroke) ? CGFloat(sizeInset / 2.0) : 0.0
        return CGRect(origin: CGPoint(x: CGFloat(rect.left) + lineInset, y: CGFloat(frame.bottom - rect.bottom - frame.top) + lineInset),
                      size: CGSize(width: CGFloat(rect.right - rect.left) - sizeInset, height: CGFloat(rect.bottom - rect.top) - sizeInset))
    }
    
    private mutating func updatePenColor(pattern: Data? = nil) {
        let bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { info, ctx in
            ctx.saveGState()
            let penPattern: CGImage = Unmanaged.fromOpaque(info!).takeUnretainedValue()
            ctx.draw(penPattern, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            ctx.restoreGState()
        }, releaseInfo: { info in
            Unmanaged<CGImage>.fromOpaque(info!).release()
        })

        let fr = UInt8(fgColor.components![0] * 255.0), fg = UInt8(fgColor.components![1] * 255.0), fb = UInt8(fgColor.components![2] * 255.0)
        let br = UInt8(bgColor.components![0] * 255.0), bg = UInt8(bgColor.components![1] * 255.0), bb = UInt8(bgColor.components![2] * 255.0)
        var patBytes = [UInt8](repeating: 0xff, count: 4 * Int(bounds.width) * Int(bounds.height))
        for ry in 0..<Int(bounds.height) {
            let y = Int(bounds.height - 1.0) - ry
            let currByte = pattern?[pattern!.startIndex + y] ?? 0xff
            assert(bounds.width == 8.0)
            for xr in 0..<8 {
                let x = 7 - xr
                let blackPixel = (currByte & (1 << xr)) != 0
                patBytes[(Int(bounds.height) * y + x) * 4 + 0] = blackPixel ? fr : br
                patBytes[(Int(bounds.height) * y + x) * 4 + 1] = blackPixel ? fg : bg
                patBytes[(Int(bounds.height) * y + x) * 4 + 2] = blackPixel ? fb : bb
                patBytes[(Int(bounds.height) * y + x) * 4 + 3] = 0x00
            }
        }
        let bir = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 4 * 8, bitsPerPixel: 32)
        patBytes.withUnsafeBytes { (patternBytes: UnsafeRawBufferPointer) in
            _ = memcpy(bir?.bitmapData, patternBytes.baseAddress, 4 * Int(bounds.width) * Int(bounds.height))
        }
        penPatternImage = bir?.cgImage
        if pattern != nil { penPattern = pattern }

        let cgPattern = CGPattern(info: Unmanaged.passRetained(self.penPatternImage!).toOpaque(), bounds: bounds, matrix: .identity, xStep: bounds.width, yStep: bounds.height, tiling: .noDistortion, isColored: false, callbacks: &callbacks)!
        let bs = CGColorSpace(name: CGColorSpace.sRGB)!
        let cs = CGColorSpace(patternBaseSpace: bs)!
        penColor = CGColor(patternSpace: cs, pattern: cgPattern, components: [CGFloat(0.0), CGFloat(0.0), CGFloat(0.0), CGFloat(1.0)])!
    }
    
    private mutating func updateFillColor(pattern: Data? = nil) {
        let bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { info, ctx in
            ctx.saveGState()
            let penPattern: CGImage = Unmanaged.fromOpaque(info!).takeUnretainedValue()
            ctx.draw(penPattern, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            ctx.restoreGState()
        }, releaseInfo: { info in
            Unmanaged<CGImage>.fromOpaque(info!).release()
        })

        let fr = UInt8(fgColor.components![0] * 255.0), fg = UInt8(fgColor.components![1] * 255.0), fb = UInt8(fgColor.components![2] * 255.0)
        let br = UInt8(bgColor.components![0] * 255.0), bg = UInt8(bgColor.components![1] * 255.0), bb = UInt8(bgColor.components![2] * 255.0)
        var patBytes = [UInt8](repeating: 0xff, count: 4 * Int(bounds.width) * Int(bounds.height))
        for ry in 0..<Int(bounds.height) {
            let y = Int(bounds.height - 1.0) - ry
            let currByte = pattern?[pattern!.startIndex + y] ?? 0x00
            assert(bounds.width == 8.0)
            for xr in 0..<8 {
                let x = 7 - xr
                let blackPixel = (currByte & (1 << xr)) != 0
                patBytes[(Int(bounds.height) * y + x) * 4 + 0] = blackPixel ? fr : br
                patBytes[(Int(bounds.height) * y + x) * 4 + 1] = blackPixel ? fg : bg
                patBytes[(Int(bounds.height) * y + x) * 4 + 2] = blackPixel ? fb : bb
                patBytes[(Int(bounds.height) * y + x) * 4 + 3] = 0x00
            }
        }
        let bir = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 4 * 8, bitsPerPixel: 32)
        patBytes.withUnsafeBytes { (patternBytes: UnsafeRawBufferPointer) in
            _ = memcpy(bir?.bitmapData, patternBytes.baseAddress, 4 * Int(bounds.width) * Int(bounds.height))
        }
        fillPatternImage = bir?.cgImage
        if pattern != nil { fillPattern = pattern }

        let cgPattern = CGPattern(info: Unmanaged.passRetained(self.penPatternImage!).toOpaque(), bounds: bounds, matrix: .identity, xStep: bounds.width, yStep: bounds.height, tiling: .noDistortion, isColored: false, callbacks: &callbacks)!
        let bs = CGColorSpace(name: CGColorSpace.sRGB)!
        let cs = CGColorSpace(patternBaseSpace: bs)!
        fillColor = CGColor(patternSpace: cs, pattern: cgPattern, components: [CGFloat(0.0), CGFloat(0.0), CGFloat(0.0), CGFloat(1.0)])!
    }
    
    private mutating func readOps(_ reader: BinaryDataReader) throws {
        let readOp = v1 ? PictOpcode.read1 : PictOpcode.read2
        var bitmapInfo: UInt32 = 0
        if imageRep.bitmapFormat.contains(.floatingPointSamples) {
            bitmapInfo |= CGBitmapInfo.floatComponents.rawValue
        }
        if imageRep.bitmapFormat.contains(.sixteenBitLittleEndian) {
            bitmapInfo |= CGBitmapInfo.byteOrder16Little.rawValue
        }
        if imageRep.bitmapFormat.contains(.thirtyTwoBitLittleEndian) {
            bitmapInfo |= CGBitmapInfo.byteOrder32Little.rawValue
        }
        if imageRep.bitmapFormat.contains(.sixteenBitBigEndian) {
            bitmapInfo |= CGBitmapInfo.byteOrder16Big.rawValue
        }
        if imageRep.bitmapFormat.contains(.thirtyTwoBitBigEndian) {
            bitmapInfo |= CGBitmapInfo.byteOrder32Big.rawValue
        }
        if imageRep.bitmapFormat.contains(.alphaFirst) {
            if imageRep.bitmapFormat.contains(.alphaNonpremultiplied) {
                bitmapInfo |= CGImageAlphaInfo.first.rawValue
            } else {
                bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue
            }
        } else {
            if imageRep.bitmapFormat.contains(.alphaNonpremultiplied) {
                bitmapInfo |= CGImageAlphaInfo.last.rawValue
            } else {
                bitmapInfo |= CGImageAlphaInfo.premultipliedLast.rawValue
            }
        }
        guard let ctx = CGContext(data: imageRep.bitmapData,
                                  width: imageRep.pixelsWide,
                                  height: imageRep.pixelsHigh,
                                  bitsPerComponent: imageRep.bitsPerSample,
                                  bytesPerRow: imageRep.bytesPerRow,
                                  space: imageRep.colorSpace.cgColorSpace!,
                                  bitmapInfo: bitmapInfo,
                                  releaseCallback: nil,
                                  releaseInfo: nil) else {
            throw  PictureError.cantCreateContext
        }
        ctx.move(to: flipped(point: penPos))

    ops:while true {
            let currOp = try readOp(reader)
            switch currOp {
            case .opEndPicture:
                break ops
            case .clipRegion:
                try self.readClipRegion(reader)
            case .origin:
                try self.readOrigin(reader)
            case .bitsRect:
                try self.readIndirectBitsRect(reader, packed: false, withMaskRegion: false)
            case .bitsRegion:
                try self.readIndirectBitsRect(reader, packed: false, withMaskRegion: true)
            case .packBitsRect:
                try self.readIndirectBitsRect(reader, packed: true, withMaskRegion: false)
            case .packBitsRegion:
                try self.readIndirectBitsRect(reader, packed: true, withMaskRegion: true)
            case .directBitsRect:
                try self.readDirectBits(reader, withMaskRegion: false)
            case .directBitsRegion:
                try self.readDirectBits(reader, withMaskRegion: true)
            case .nop, .hiliteMode, .defHilite:
                continue
            case .frameSameRect:
                ctx.setStrokeColor(penColor)
                let cgBox = flipped(rect: lastRect, for: .stroke)
                ctx.addRect(cgBox)
                ctx.strokePath()
            case .paintSameRect, .invertSameRect:
                ctx.setFillColor(penColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addRect(cgBox)
                ctx.fillPath()
            case .fillSameRect:
                ctx.setFillColor(fillColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addRect(cgBox)
                ctx.fillPath()
            case .eraseSameRect:
                ctx.setFillColor(bgColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addRect(cgBox)
                ctx.fillPath()
            case .frameSameOval:
                ctx.setStrokeColor(penColor)
                let cgBox = flipped(rect: lastRect, for: .stroke)
                ctx.addEllipse(in: cgBox)
                ctx.strokePath()
            case .paintSameOval, .invertSameOval:
                ctx.setFillColor(penColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addEllipse(in: cgBox)
                ctx.fillPath()
            case .fillSameOval:
                ctx.setFillColor(fillColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addEllipse(in: cgBox)
                ctx.fillPath()
            case .eraseSameOval:
                ctx.setFillColor(bgColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addEllipse(in: cgBox)
                ctx.fillPath()
            case .frameSameRoundRect:
                ctx.setStrokeColor(penColor)
                let cgBox = flipped(rect: lastRect, for: .stroke)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.strokePath()
            case .paintSameRoundRect, .invertSameRoundRect:
                ctx.setFillColor(penColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.fillPath()
            case .fillSameRoundRect:
                ctx.setFillColor(fillColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.fillPath()
            case .eraseSameRoundRect:
                ctx.setFillColor(bgColor)
                let cgBox = flipped(rect: lastRect, for: .fill)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.fillPath()
            case .penMode:
                try reader.advance(2)
            case .shortLineFrom:
                ctx.setStrokeColor(penColor)
                let dh: Int8 = try reader.read(bigEndian: true)
                let dv: Int8 = try reader.read(bigEndian: true)
                let ep = flipped(point: QDPoint(x: penPos.x + Int(dh), y: penPos.y + Int(dv)))
                ctx.move(to: flipped(point: penPos))
                ctx.addLine(to: ep)
                ctx.strokePath()
                penPos = QDPoint(x: Int(ep.x), y: Int(ep.y))
                ctx.move(to: flipped(point: penPos))
            case .shortComment:
                try reader.advance(2)
            case .penSize:
                penSize = try QDPoint(reader)
                ctx.setLineWidth(CGFloat(max(penSize.x, penSize.y)))
            case .lineFrom:
                ctx.setStrokeColor(penColor)
                let dh: Int16 = try reader.read(bigEndian: true)
                let dv: Int16 = try reader.read(bigEndian: true)
                let ep = flipped(point: QDPoint(x: penPos.x + Int(dh), y: penPos.y + Int(dv)))
                ctx.move(to: flipped(point: penPos))
                ctx.addLine(to: ep)
                ctx.strokePath()
                penPos = QDPoint(x: Int(ep.x), y: Int(ep.y))
                ctx.move(to: flipped(point: penPos))
            case .shortLine:
                ctx.setStrokeColor(penColor)
                let sh = Int(try reader.read(bigEndian: true) as Int16)
                let sv = Int(try reader.read(bigEndian: true) as Int16)
                let sp = flipped(point: QDPoint(x: sh, y: sv))
                let eh = Int(try reader.read(bigEndian: true) as Int8)
                let ev = Int(try reader.read(bigEndian: true) as Int8)
                let ep = flipped(point: QDPoint(x: sh + eh, y: sv + ev))
                ctx.move(to: sp)
                ctx.addLine(to: ep)
                ctx.strokePath()
                penPos = QDPoint(x: Int(ep.x), y: Int(ep.y))
                ctx.move(to: flipped(point: penPos))
            case .rgbFgColor:
                let red = try reader.read() as UInt16
                let green = try reader.read() as UInt16
                let blue = try reader.read() as UInt16
                fgColor = CGColor(red: CGFloat(red) / 65535.0, green: CGFloat(green) / 65535.0, blue: CGFloat(blue) / 65535.0, alpha: 1.0)
                updatePenColor(pattern: penPattern)
                updateFillColor(pattern: fillPattern)
            case .rgbBkCcolor:
                let red = try reader.read() as UInt16
                let green = try reader.read() as UInt16
                let blue = try reader.read() as UInt16
                bgColor = CGColor(red: CGFloat(red) / 65535.0, green: CGFloat(green) / 65535.0, blue: CGFloat(blue) / 65535.0, alpha: 1.0)
                updatePenColor(pattern: penPattern)
                updateFillColor(pattern: fillPattern)
            case .hiliteColor, .opColor:
                try reader.advance(6)
            case .line:
                ctx.setStrokeColor(penColor)
                let sp = flipped(point: try QDPoint(reader))
                let e = try QDPoint(reader)
                let ep = flipped(point: e)
                penPos = e
                ctx.move(to: sp)
                ctx.addLine(to: ep)
                ctx.strokePath()
            case .penPattern:
                updatePenColor(pattern: try reader.readData(length: 8))
            case .fillPattern:
                updateFillColor(pattern: try reader.readData(length: 8))
            case .frameRect:
                ctx.setStrokeColor(penColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .stroke)
                ctx.addRect(cgBox)
                ctx.strokePath()
                lastRect = box
            case .paintRect, .invertRect:
                ctx.setFillColor(penColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addRect(cgBox)
                ctx.fillPath()
                lastRect = box
            case .fillRect:
                ctx.setFillColor(fillColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addRect(cgBox)
                ctx.fillPath()
                lastRect = box
            case .eraseRect:
                ctx.setFillColor(bgColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addRect(cgBox)
                ctx.fillPath()
                lastRect = box
            case .frameOval:
                ctx.setStrokeColor(penColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .stroke)
                ctx.addEllipse(in: cgBox)
                ctx.strokePath()
                lastRect = box
            case .paintOval, .invertOval:
                ctx.setFillColor(penColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addEllipse(in: cgBox)
                ctx.fillPath()
                lastRect = box
            case .fillOval:
                ctx.setFillColor(fillColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addEllipse(in: cgBox)
                ctx.fillPath()
                lastRect = box
            case .eraseOval:
                ctx.setFillColor(bgColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addEllipse(in: cgBox)
                ctx.fillPath()
                lastRect = box
            case .frameRoundRect:
                ctx.setStrokeColor(penColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .stroke)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.strokePath()
                lastRect = box
            case .paintRoundRect, .invertRoundRect:
                ctx.setFillColor(penColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.fillPath()
                lastRect = box
            case .fillRoundRect:
                ctx.setFillColor(fillColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.fillPath()
                lastRect = box
            case .eraseRoundRect:
                ctx.setFillColor(bgColor)
                let box = try QDRect(reader)
                let cgBox = flipped(rect: box, for: .fill)
                ctx.addPath(CGPath(roundedRect: cgBox, cornerWidth: CGFloat(roundRectCornerSize.x), cornerHeight: CGFloat(roundRectCornerSize.y), transform: nil))
                ctx.fillPath()
                lastRect = box
            case .frameRegion, .paintRegion, .eraseRegion, .invertRegion, .fillRegion:
                try self.skipRegion(reader)
            case .longComment:
                try self.skipLongComment(reader)
            case .compressedQuickTime:
                try self.readQuickTime(reader)
                // A successful QuickTime decode will replace the imageRep and we should stop processing.
                return
            case .uncompressedQuickTime:
                // Uncompressed QuickTime contains a matte which we can skip over. Actual image data should follow.
                let length = Int(try reader.read() as UInt32)
                try reader.advance(length)
            case .versionOp, .version, .headerOp:
                break // We already parsed these at the start.
            case .roundRectOvalSize:
                let ovalV = Int(try reader.read() as Int16)
                let ovalH = Int(try reader.read() as Int16)
                roundRectCornerSize = QDPoint(x: ovalH, y: ovalV)
            }
        }

        // If we reached the end and have nothing to show for it then we should fail
        if case .unknown = format {
            throw ImageReaderError.unsupportedFormat
        }
    }

    private mutating func readIndirectBitsRect(_ reader: BinaryDataReader, packed: Bool, withMaskRegion: Bool) throws {
        let pixMap = try PixelMap(reader, skipBaseAddr: true)
        format = pixMap.format
        let colorTable = if pixMap.isPixmap {
            try ColorTable.read(reader)
        } else {
            ColorTable.system1
        }

        let (srcRect, destRect) = try self.readSrcAndDestRects(reader)

        try reader.advance(2) // transfer mode
        if withMaskRegion {
            try self.skipRegion(reader)
        }

        // Row bytes less than 8 is never packed
        let pixelData = if packed && pixMap.rowBytes >= 8 {
            try PackBits<UInt8>.readRows(reader: reader, pixMap: pixMap)
        } else {
            try reader.readData(length: pixMap.pixelDataSize)
        }

        try pixMap.draw(pixelData, colorTable: colorTable, to: imageRep, in: destRect, from: srcRect)
    }

    private mutating func readDirectBits(_ reader: BinaryDataReader, withMaskRegion: Bool) throws {
        let pixMap = try PixelMap(reader)
        format = pixMap.format

        let (srcRect, destRect) = try self.readSrcAndDestRects(reader)

        try reader.advance(2) // transfer mode
        if withMaskRegion {
            try self.skipRegion(reader)
        }

        let pixelData = switch pixMap.resolvedPackType {
        case .rlePixel:
            try PackBits<UInt16>.readRows(reader: reader, pixMap: pixMap)
        case .rleComponent:
            try PackBits<UInt8>.readRows(reader: reader, pixMap: pixMap)
        default:
            try reader.readData(length: pixMap.pixelDataSize)
        }

        try pixMap.draw(pixelData, to: imageRep, in: destRect, from: srcRect)
    }

    private func readSrcAndDestRects(_ reader: BinaryDataReader) throws -> (srcRect: QDRect, destRect: QDRect) {
        var srcRect = try QDRect(reader)
        var destRect = try QDRect(reader)
        // Apply clip rect to dest rect, adjusting source rect by matching amount
        if clipRect.top > destRect.top {
            srcRect.top += clipRect.top - destRect.top
            destRect.top = clipRect.top
        }
        if clipRect.left > destRect.left {
            srcRect.left += clipRect.left - destRect.left
            destRect.left = clipRect.left
        }
        if clipRect.bottom < destRect.bottom {
            srcRect.bottom -= destRect.bottom - clipRect.bottom
            destRect.bottom = clipRect.bottom
        }
        if clipRect.right < destRect.right {
            srcRect.right -= destRect.right - clipRect.right
            destRect.right = clipRect.right
        }
        guard destRect.isValid else {
            throw ImageReaderError.invalid
        }
        // Align dest rect to the origin
        destRect.alignTo(origin)
        return (srcRect, destRect)
    }

    private mutating func readClipRegion(_ reader: BinaryDataReader) throws {
        let length = Int(try reader.read() as UInt16)
        clipRect = try QDRect(reader)
        try reader.advance(length - 10)
    }

    private mutating func readOrigin(_ reader: BinaryDataReader) throws {
        let delta = try QDPoint(reader)
        origin.x += delta.x
        origin.y += delta.y
    }

    private func skipRegion(_ reader: BinaryDataReader) throws {
        let length = Int(try reader.read() as UInt16)
        try reader.advance(length - 2)
    }

    private func skipLongComment(_ reader: BinaryDataReader) throws {
        try reader.advance(2) // kind
        let length = Int(try reader.read() as UInt16)
        try reader.advance(length)
    }

    private mutating func readQuickTime(_ reader: BinaryDataReader) throws {
        // https://vintageapple.org/inside_r/pdf/QuickTime_1993.pdf#484
        let size = Int(try reader.read() as UInt32)

        // Construct a new reader constrained to the specified size
        let reader = BinaryDataReader(try reader.readData(length: size))
        try reader.advance(2 + 36) // version, matrix
        let matteSize = Int(try reader.read() as UInt32)
        try reader.advance(8 + 2 + 8 + 4) // matteRect, transferMode, srcRect, accuracy
        let maskSize = Int(try reader.read() as UInt32)
        if matteSize > 0 {
            try reader.advance(matteSize)
        }
        if maskSize > 0 {
            try reader.advance(maskSize)
        }

        let imageDesc = try QTImageDesc(reader)
        format = .quickTime(imageDesc.compressor, imageDesc.resolvedDepth)
        imageRep = try imageDesc.readImage(reader)
    }
}

// MARK: Writer

extension Picture {
    init(imageRep: NSBitmapImageRep) throws {
        self.imageRep = ImageFormat.normalize(imageRep)
        v1 = false
        frame = try QDRect(for: imageRep)
        clipRect = frame
        origin = frame.origin
        penPos = QDPoint(x: 0, y: 0)
        lastRect = QDRect(top: 0, left: 0, bottom: 0, right: 0)
        roundRectCornerSize = QDPoint(x: 8, y: 8)
        penSize = QDPoint(x: 1, y: 1)
    }

    static func data(from rep: NSBitmapImageRep, format: inout ImageFormat) throws -> Data {
        var pict = try Self(imageRep: rep)
        let writer = BinaryDataWriter()
        try pict.write(writer, format: format)
        format = pict.format
        return writer.data
    }

    mutating func write(_ writer: BinaryDataWriter, format: ImageFormat) throws {
        // Header
        writer.advance(2) // v1 size
        frame.write(writer)
        writer.write(PictOpcode.versionOp.rawValue)
        writer.write(PictOpcode.version.rawValue)
        writer.write(PictOpcode.headerOp.rawValue)
        writer.write(Self.extendedVersion2)
        writer.advance(2) // reserved
        writer.write(0x00480000 as UInt32) // hRes
        writer.write(0x00480000 as UInt32) // vRes
        frame.write(writer) // source rect
        writer.advance(4) // reserved

        // Clip region (required)
        writer.write(PictOpcode.clipRegion.rawValue)
        writer.write(10 as UInt16) // size
        clipRect.write(writer)

        // Image data
        self.format = format
        switch format {
        case .monochrome:
            try self.writeIndirectBits(writer, mono: true)
        case let .color(depth) where depth <= 8:
            try self.writeIndirectBits(writer)
        case .color(16):
            try self.writeDirectBits(writer, rgb555: true)
        case .color(24):
            try self.writeDirectBits(writer)
        case let .quickTime(compressor, _):
            try self.writeQuickTime(writer, compressor: compressor)
        default:
            throw ImageWriterError.unsupported
        }

        // Align and end
        writer.advance(writer.bytesWritten % 2)
        writer.write(PictOpcode.opEndPicture.rawValue)
    }

    private mutating func writeIndirectBits(_ writer: BinaryDataWriter, mono: Bool = false) throws {
        writer.write(PictOpcode.packBitsRect.rawValue)
        var (pixMap, pixelData, colorTable) = try PixelMap.build(from: imageRep, startingColors: mono ? ColorTable.system1 : nil)
        if mono {
            guard colorTable.count == 2 else {
                throw ImageWriterError.tooManyColors
            }
            pixMap.isPixmap = false
            pixMap.write(writer, skipBaseAddr: true)
        } else {
            pixMap.write(writer, skipBaseAddr: true)
            ColorTable.write(writer, colors: colorTable)
        }
        pixMap.bounds.write(writer) // source rect
        frame.write(writer) // dest rect
        writer.advance(2) // transfer mode (0 = Source Copy)

        let rowBytes = pixMap.rowBytes
        if rowBytes >= 8 {
            pixelData.withUnsafeBytes { inBuffer in
                var input = inBuffer.assumingMemoryBound(to: UInt8.self).baseAddress!
                for _ in 0..<imageRep.pixelsHigh {
                    PackBits<UInt8>.writeRow(input, writer: writer, pixMap: pixMap)
                    input += rowBytes
                }
            }
        } else {
            writer.writeData(pixelData)
        }

        // Update format (may be different than what was specified)
        format = pixMap.format
    }

    private func writeDirectBits(_ writer: BinaryDataWriter, rgb555: Bool = false) throws {
        let pixMap = try PixelMap(for: imageRep, rgb555: rgb555)
        writer.write(PictOpcode.directBitsRect.rawValue)
        pixMap.write(writer)
        pixMap.bounds.write(writer) // source rect
        frame.write(writer) // dest rect
        writer.advance(2) // transfer mode (0 = Source Copy)

        var bitmap = imageRep.bitmapData!
        switch pixMap.resolvedPackType {
        case .rleComponent:
            withUnsafeTemporaryAllocation(of: UInt8.self, capacity: imageRep.pixelsWide * 3) { inBuffer in
                for _ in 0..<imageRep.pixelsHigh {
                    // Convert RGBA to channels
                    for x in 0..<imageRep.pixelsWide {
                        inBuffer[x] = bitmap[0]
                        inBuffer[x + imageRep.pixelsWide] = bitmap[1]
                        inBuffer[x + imageRep.pixelsWide * 2] = bitmap[2]
                        bitmap += 4
                    }
                    PackBits<UInt8>.writeRow(inBuffer.baseAddress!, writer: writer, pixMap: pixMap)
                }
            }
        case .rlePixel:
            withUnsafeTemporaryAllocation(of: UInt16.self, capacity: imageRep.pixelsWide) { inBuffer in
                for _ in 0..<imageRep.pixelsHigh {
                    // Convert RGBA to RGB555
                    for x in 0..<imageRep.pixelsWide {
                        inBuffer[x] = RGBColor(red: bitmap[0], green: bitmap[1], blue: bitmap[2]).rgb555().bigEndian
                        bitmap += 4
                    }
                    PackBits<UInt16>.writeRow(inBuffer.baseAddress!, writer: writer, pixMap: pixMap)
                }
            }
        case .none where pixMap.pixelSize == 16:
            // Convert RGBA to RGB555
            for _ in 0..<(imageRep.pixelsHigh * imageRep.pixelsWide) {
                writer.write(RGBColor(red: bitmap[0], green: bitmap[1], blue: bitmap[2]).rgb555())
                bitmap += 4
            }
        default:
            // Convert RGBA to XRGB by shifting the data 1 byte
            writer.advance(1)
            writer.data.append(bitmap, count: imageRep.bytesPerPlane-1)
        }
    }

    private func writeQuickTime(_ writer: BinaryDataWriter, compressor: UInt32) throws {
        writer.write(PictOpcode.compressedQuickTime.rawValue)
        writer.advance(4) // Size will be written later
        let start = writer.bytesWritten
        writer.advance(2 + 36) // version, matrix
        writer.advance(4) // matteSize
        writer.advance(8 + 2 + 8 + 4) // matteRect, transferMode, srcRect, accuracy
        writer.advance(4) // maskSize

        try QTImageDesc.write(rep: imageRep, to: writer, using: compressor)
        let size = UInt32(writer.bytesWritten - start)
        writer.write(size, at: start-4)
    }
}


enum PictOpcode: UInt16 {
    case nop = 0x0000
    case clipRegion = 0x0001
    case penSize = 0x0007
    case penMode = 0x0008
    case penPattern = 0x0009
    case fillPattern = 0x000A
    case roundRectOvalSize = 0x000B
    case origin = 0x000C
    case versionOp = 0x0011
    case rgbFgColor = 0x001A
    case rgbBkCcolor = 0x001B
    case hiliteMode = 0x001C
    case hiliteColor = 0x001D
    case defHilite = 0x001E
    case opColor = 0x001F
    case line = 0x0020
    case lineFrom = 0x0021
    case shortLine = 0x0022
    case shortLineFrom = 0x0023
    case frameRect = 0x0030
    case paintRect = 0x0031
    case eraseRect = 0x0032
    case invertRect = 0x0033
    case fillRect = 0x0034
    case frameSameRect = 0x0038
    case paintSameRect = 0x0039
    case eraseSameRect = 0x003A
    case invertSameRect = 0x003B
    case fillSameRect = 0x003C
    case frameRoundRect = 0x0040
    case paintRoundRect = 0x0041
    case eraseRoundRect = 0x0042
    case invertRoundRect = 0x0043
    case fillRoundRect = 0x0044
    case frameSameRoundRect = 0x0048
    case paintSameRoundRect = 0x0049
    case eraseSameRoundRect = 0x004A
    case invertSameRoundRect = 0x004B
    case fillSameRoundRect = 0x004C
    case frameOval = 0x0050
    case paintOval = 0x0051
    case eraseOval = 0x0052
    case invertOval = 0x0053
    case fillOval = 0x0054
    case frameSameOval = 0x0058
    case paintSameOval = 0x0059
    case eraseSameOval = 0x005A
    case invertSameOval = 0x005B
    case fillSameOval = 0x005C
    case bitsRect = 0x0090
    case bitsRegion = 0x0091
    case packBitsRect = 0x0098
    case packBitsRegion = 0x0099
    case directBitsRect = 0x009A
    case directBitsRegion = 0x009B
    case frameRegion = 0x0080
    case paintRegion = 0x0081
    case eraseRegion = 0x0082
    case invertRegion = 0x0083
    case fillRegion = 0x0084
    case shortComment = 0x00A0
    case longComment = 0x00A1
    case opEndPicture = 0x00FF
    case version = 0x02FF
    case headerOp = 0x0C00
    case compressedQuickTime = 0x8200
    case uncompressedQuickTime = 0x8201

    static func read2(_ reader: BinaryDataReader) throws -> Self {
        if reader.bytesRead % 2 == 1 {
            try reader.advance(1)
        }
        let currOp: RawValue = try reader.read()
        guard let op = Self.init(rawValue: currOp) else {
            throw ImageReaderError.unsupported(opcode: currOp)
        }
        return op
    }

    static func read1(_ reader: BinaryDataReader) throws -> Self {
        let currOp = UInt16(try reader.read() as UInt8)
        guard let op = Self.init(rawValue: currOp) else {
            throw ImageReaderError.unsupported(opcode: currOp)
        }
        return op
    }
}

public enum PictureError: LocalizedError {
    case cantCreateContext
    public var errorDescription: String? {
        switch self {
        case .cantCreateContext:
            return NSLocalizedString("Failed to create graphics context.", comment: "")
        }
    }
}
