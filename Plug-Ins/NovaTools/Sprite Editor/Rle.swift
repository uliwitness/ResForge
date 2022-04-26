import Cocoa
import RFSupport

enum RleError: Error {
    case invalid
    case unsupported
}

typealias RleOp = UInt32
extension RleOp {
    enum code: UInt32 {
        case frameEnd   = 0x00000000
        case lineStart  = 0x01000000
        case pixels     = 0x02000000
        case skip       = 0x03000000
        case colorRun   = 0x04000000
    }
    var count: Int { Int(self & 0x00FFFFFF) / 2 }
    var code: RleOp.code? { RleOp.code(rawValue: self & 0xFF000000) }
    init(_ code: RleOp.code, count: Int) {
        self = code.rawValue | UInt32(count*2)
    }
    init(_ code: RleOp.code, bytes: Int = 0) {
        self = code.rawValue | UInt32(bytes)
    }
}

class Rle {
    let frameWidth: Int
    let frameHeight: Int
    let frameCount: Int
    private var reader: BinaryDataReader!
    private var writer: BinaryDataWriter!
    
    var data: Data {
        writer?.data ?? reader.data
    }
    
    // Init for reading
    init(_ data: Data) throws {
        reader = BinaryDataReader(data)
        frameWidth = Int(try reader.read() as UInt16)
        frameHeight = Int(try reader.read() as UInt16)
        let depth = try reader.read() as UInt16
        guard depth == 16 else {
            throw RleError.unsupported
        }
        try reader.advance(2) // Palette is ignored for 16-bit
        frameCount = Int(try reader.read() as UInt16)
        try reader.advance(6)
    }
    
    // Init for writing
    init(width: Int, height: Int, count: Int) {
        frameWidth = width
        frameHeight = height
        frameCount = count
        
        writer = BinaryDataWriter(capacity: 16)
        writer.write(UInt16(frameWidth))
        writer.write(UInt16(frameHeight))
        writer.write(UInt16(16))
        writer.advance(2)
        writer.write(UInt16(frameCount))
        writer.advance(6)
    }
    
    func readFrame() throws -> NSBitmapImageRep {
        let frame = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: frameWidth,
                                     pixelsHigh: frameHeight,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: frameWidth*4,
                                     bitsPerPixel: 0)!
        try self.readFrame(to: frame.bitmapData!, lineAdvance: frameWidth)
        return frame
    }
    
    func readSheet() throws -> NSBitmapImageRep {
        if reader == nil {
            reader = BinaryDataReader(self.data)
        }
        try reader.setPosition(16)
        var gridX = 6
        if frameCount <= gridX {
            gridX = frameCount
        } else {
            while frameCount % gridX != 0 {
                gridX += 1
            }
        }
        let gridY = frameCount / gridX
        let sheet = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: frameWidth * gridX,
                                     pixelsHigh: frameHeight * gridY,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: frameWidth * gridX * 4,
                                     bitsPerPixel: 0)!
        let framePointer = sheet.bitmapData!
        for y in 0..<gridY {
            for x in 0..<gridX {
                let advance = (y*frameHeight*sheet.pixelsWide + x*frameWidth) * 4
                try self.readFrame(to: framePointer.advanced(by: advance), lineAdvance: sheet.pixelsWide)
            }
        }
        return sheet
    }
    
    private func readFrame(to framePointer: UnsafeMutablePointer<UInt8>, lineAdvance: Int) throws {
        var y = 0
        var x = 0
        var framePointer = framePointer
        while true {
            let op = try reader.read() as RleOp
            let count = op.count
            switch op.code {
            case .lineStart:
                guard y < frameHeight else {
                    throw RleError.invalid
                }
                if y != 0 {
                    framePointer = framePointer.advanced(by: (lineAdvance-x)*4)
                }
                x = 0
                y += 1
            case .skip:
                x += count
                guard x <= frameWidth else {
                    throw RleError.invalid
                }
                framePointer = framePointer.advanced(by: count*4)
            case .pixels:
                x += count
                guard x <= frameWidth else {
                    throw RleError.invalid
                }
                // Work directly with the bytes - this is much faster than reading the pixels one at a time
                try reader.readData(length: count * 2).withUnsafeBytes { bytes in
                    for pixel in bytes.bindMemory(to: UInt16.self) {
                        self.draw(UInt16(bigEndian: pixel), to: &framePointer)
                    }
                }
                if count % 2 != 0 {
                    try reader.advance(2)
                }
            case .colorRun:
                x += count
                guard x <= frameWidth else {
                    throw RleError.invalid
                }
                // The intention of this token is simply to repeat a single colour. But since the format is
                // 4-byte aligned, it's technically possible to repeat two different 16-bit colour values.
                // On big-endian machines this would presumably repeat them in order (untested), but on x86
                // versions of EV Nova they appear to be swapped. Here we reproduce the x86 behaviour.
                let pixels: [UInt16] = [try reader.read(), try reader.read()]
                for i in 1...count {
                    self.draw(pixels[i%2], to: &framePointer)
                }
            case .frameEnd:
                return
            default:
                throw RleError.invalid
            }
        }
    }
    
    func writeSheet(_ image: NSImage, dither: Bool = false) -> [NSBitmapImageRep] {
        let rep = image.representations[0]
        // Reset the resolution
        rep.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let gridX = rep.pixelsWide / frameWidth
        var frames: [NSBitmapImageRep] = []
        for i in 0..<frameCount {
            let originX = i % gridX * frameWidth
            let originY = i / gridX * frameHeight
            let frame = self.newFrame()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: frame)
            rep.draw(in: NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight),
                     from: NSRect(x: originX, y: rep.pixelsHigh-originY-frameHeight, width: frameWidth, height: frameHeight),
                     operation: .copy,
                     fraction: 1,
                     respectFlipped: true,
                     hints: nil)
            self.writeFrame(frame, dither: dither)
            frames.append(frame)
        }
        return frames
    }
    
    func writeFrames(_ images: [NSImage], dither: Bool = false) -> [NSBitmapImageRep] {
        var frames: [NSBitmapImageRep] = []
        for image in images {
            let rep = image.representations[0]
            // Reset the resolution
            rep.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            let frame = self.newFrame()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: frame)
            rep.draw()
            self.writeFrame(frame, dither: dither)
            frames.append(frame)
        }
        return frames
    }
    
    private func newFrame() -> NSBitmapImageRep {
        return NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: frameWidth,
                                pixelsHigh: frameHeight,
                                bitsPerSample: 8,
                                samplesPerPixel: 4,
                                hasAlpha: true,
                                isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: frameWidth*4,
                                bitsPerPixel: 32)!
    }
    
    private func writeFrame(_ frame: NSBitmapImageRep, dither: Bool = false) {
        if dither {
            self.dither(frame)
        }
        
        var framePointer = frame.bitmapData!
        var lineCount = 0
        var linePos = 0
        var pixels: [UInt16] = []
        for _ in 0..<frameHeight {
            lineCount += 1
            var transparent = 0
            for _ in 0..<frameWidth {
                if framePointer[3] == 0 {
                    framePointer = framePointer.advanced(by: 4)
                    transparent += 1
                } else {
                    if lineCount != 0 {
                        // First pixel data for this line, write the line start
                        // Doing this only on demand allows us to omit trailing blank lines in the frame
                        for _ in 0..<lineCount {
                            writer.write(RleOp(.lineStart))
                        }
                        lineCount = 0
                        linePos = writer.position
                    }
                    if transparent != 0 {
                        // Starting pixel data after transparency, write the skip
                        if !pixels.isEmpty {
                            // We have previous unwritten pixel data, write this first
                            self.write(bigEndianPixels: pixels)
                            pixels.removeAll(keepingCapacity: true)
                        }
                        writer.write(RleOp(.skip, count: transparent))
                        transparent = 0
                    }
                    let pixel = UInt16(framePointer[0] & 0xF8) * 0x80
                              + UInt16(framePointer[1] & 0xF8) * 0x04
                              + UInt16(framePointer[2] & 0xF8) / 0x08
                    self.draw(pixel, to: &framePointer)
                    pixels.append(pixel.bigEndian)
                }
            }
            if !pixels.isEmpty {
                self.write(bigEndianPixels: pixels)
                pixels.removeAll(keepingCapacity: true)
                // Rewrite the line length
                writer.write(RleOp(.lineStart, bytes: writer.position-linePos), at: linePos-4)
            }
        }
        writer.write(RleOp(.frameEnd))
    }
    
    private func dither(_ frame: NSBitmapImageRep) {
        // QuickDraw dithering algorithm.
        // Half the error is diffused right on even rows, left on odd rows. The remainder is diffused down.
        let rowBytes = frame.bytesPerRow // This is a computed property, only access it once.
        let framePointer = frame.bitmapData!
        for y in 0..<frameHeight {
            let even = y % 2 == 0
            let row = even ? stride(from: 0, through: frameWidth-1, by: 1) : stride(from: frameWidth-1, through: 0, by: -1)
            for x in row {
                let p = y * rowBytes + x * 4
                for i in p...p+2 {
                    // To perfectly replicate QuickDraw we would simply take the error as the lower 3 bits of the value.
                    // This is not entirely accurate though and has the side-effect that repeat dithers will degrade the image.
                    // To fix this we subtract from that the upper 3 bits (see 5-bit restoration in `draw` function).
                    let error = Int(framePointer[i] & 0x7) - Int(framePointer[i] / 0x20)
                    if error != 0 {
                        if even && x+1 < frameWidth {
                            framePointer[i+4] = UInt8(clamping: Int(framePointer[i+4]) + error / 2)
                        } else if !even && x > 0 {
                            framePointer[i-4] = UInt8(clamping: Int(framePointer[i-4]) + error / 2)
                        }
                        if y+1 < frameHeight {
                            framePointer[i+rowBytes] = UInt8(clamping: Int(framePointer[i+rowBytes]) + (error+1) / 2)
                        }
                    }
                }
            }
        }
    }
    
    private func draw(_ pixel: UInt16, to framePointer: inout UnsafeMutablePointer<UInt8>) {
        // Note: division is used here instead of bitshifts as it is much faster in unoptimised debug builds.
        let r = UInt8((pixel & 0x7C00) / 0x80)
        let g = UInt8((pixel & 0x03E0) / 0x04)
        let b = UInt8((pixel & 0x001F) * 0x08)
        // To accurately restore 5-bits to 8-bits (and match QuickDraw output), copy the upper 3 bits to the lower 3 bits.
        framePointer[0] = r | (r / 0x20)
        framePointer[1] = g | (g / 0x20)
        framePointer[2] = b | (b / 0x20)
        framePointer[3] = 0xFF
        framePointer = framePointer.advanced(by: 4)
    }
    
    private func write(bigEndianPixels pixels: [UInt16]) {
        writer.write(RleOp(.pixels, count: pixels.count))
        // Append the bytes directly to the data - this is much faster than writing the pixels one at a time
        pixels.withUnsafeBufferPointer {
            writer.data.append($0)
        }
        if pixels.count % 2 != 0 {
            writer.advance(2)
        }
    }
}
