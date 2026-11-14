import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Helpers that run outside the main actor (archives, folder sizes).
nonisolated enum FileTools {
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return error.localizedDescription }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0 { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? "The command failed." : text
    }

    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func unique(_ url: URL) -> URL {
        guard exists(url) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        var candidate = url
        repeat {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appending(path: name)
            n += 1
        } while exists(candidate)
        return candidate
    }

    static func compress(_ urls: [URL], in dir: URL) -> String? {
        guard let first = urls.first else { return nil }
        if urls.count == 1 {
            let dest = unique(dir.appending(path: first.lastPathComponent + ".zip"))
            return run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, dest.path])
        }
        let dest = unique(dir.appending(path: "Archive.zip"))
        return run("/usr/bin/zip", ["-r", "-y", dest.path] + urls.map(\.lastPathComponent), cwd: dir)
    }

    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz"]

    static func isArchive(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    static func decompress(_ urls: [URL], in dir: URL) -> String? {
        let urls = urls.filter(isArchive)
        if urls.isEmpty { return "Select one or more archives (zip, tar, gz, bz2, xz)." }
        var errors: [String] = []
        for url in urls {
            let dest = unique(dir.appending(path: url.deletingPathExtension().lastPathComponent))
            do { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)"); continue }
            let err: String?
            if url.pathExtension.lowercased() == "zip" {
                err = run("/usr/bin/ditto", ["-x", "-k", url.path, dest.path])
            } else {
                err = run("/usr/bin/tar", ["-xf", url.path, "-C", dest.path])
            }
            if let err { errors.append("\(url.lastPathComponent): \(err)") }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    // MARK: Images (through the built-in sips tool)

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Rotates images in place (90 = right, 270 = left), like Finder.
    static func rotate(_ urls: [URL], degrees: Int) -> String? {
        let images = urls.filter(isImage)
        if images.isEmpty { return "Select one or more image files." }
        var errors: [String] = []
        for url in images {
            if let err = run("/usr/bin/sips", ["-r", String(degrees), url.path]) {
                errors.append("\(url.lastPathComponent): \(err)")
            }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    /// Writes a converted copy next to each image and leaves the original untouched.
    static func convert(_ urls: [URL], format: String, ext: String) -> String? {
        let images = urls.filter(isImage)
        if images.isEmpty { return "Select one or more image files." }
        var errors: [String] = []
        for url in images {
            let dest = unique(url.deletingLastPathComponent()
                .appending(path: url.deletingPathExtension().lastPathComponent + "." + ext))
            if let err = run("/usr/bin/sips", ["-s", "format", format, url.path, "--out", dest.path]) {
                errors.append("\(url.lastPathComponent): \(err)")
            }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    /// Writes a copy without EXIF, GPS, IPTC and XMP next to each image ("name-clean"). The original stays untouched.
    /// The orientation is kept, otherwise a rotated photo would show sideways.
    static func stripMetadata(_ urls: [URL]) -> String? {
        let images = urls.filter(isImage)
        if images.isEmpty { return "Select one or more image files." }
        var errors: [String] = []
        for url in images {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(src) else {
                errors.append("\(url.lastPathComponent): Could not read the image.")
                continue
            }
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let ext = url.pathExtension
            let name = url.deletingPathExtension().lastPathComponent + "-clean" + (ext.isEmpty ? "" : "." + ext)
            let dest = unique(url.deletingLastPathComponent().appending(path: name))

            let metadata = CGImageMetadataCreateMutable()
            if orientation != 1 {
                CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyTIFFDictionary,
                                                             kCGImagePropertyTIFFOrientation, NSNumber(value: orientation))
            }
            var ok = false
            if let out = CGImageDestinationCreateWithURL(dest as CFURL, type, 1, nil) {
                let options: [CFString: Any] = [
                    kCGImageDestinationMetadata: metadata,
                    kCGImageDestinationMergeMetadata: false,
                    kCGImageMetadataShouldExcludeGPS: true,
                ]
                // Copies the image data as it is, without recompressing.
                ok = CGImageDestinationCopyImageSource(out, src, options as CFDictionary, nil)
            }
            if !ok {
                // Formats that cannot be copied are written again from the pixels.
                try? FileManager.default.removeItem(at: dest)
                if let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                   let out = CGImageDestinationCreateWithURL(dest as CFURL, type, 1, nil) {
                    CGImageDestinationAddImage(out, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
                    ok = CGImageDestinationFinalize(out)
                }
            }
            if !ok {
                try? FileManager.default.removeItem(at: dest)
                errors.append("\(url.lastPathComponent): Could not write the clean copy.")
            }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    static func size(of url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard v?.isDirectory == true && v?.isSymbolicLink != true else { return Int64(v?.fileSize ?? 0) }
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let u as URL in e {
                let r = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if r?.isRegularFile == true { total += Int64(r?.fileSize ?? 0) }
            }
        }
        return total
    }
}

// MARK: - Optimize for web

nonisolated struct OptimizeOptions: Sendable {
    var maxSide: Int?
    var quality: Double
    var srgb: Bool
    var strip: Bool
    var replace: Bool
    var pngPalette = false
}

nonisolated struct OptimizedItem: Sendable {
    let original: URL
    let result: URL
    var trashedOriginal: URL?
}

nonisolated extension FileTools {
    /// Resizes (never enlarges), converts to sRGB, drops or keeps metadata and writes "name-web" next to the original,
    /// or replaces the original, which then goes to the Trash. The format stays the same, except BMP becomes PNG.
    static func optimize(_ url: URL, options: OptimizeOptions) -> (item: OptimizedItem?, error: String?) {
        func fail(_ message: String) -> (item: OptimizedItem?, error: String?) {
            (nil, "\(url.lastPathComponent): \(message)")
        }
        let fm = FileManager.default
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), var type = CGImageSourceGetType(src) else {
            return fail("Could not read the image.")
        }
        if let t = UTType(type as String), t.conforms(to: .bmp) { type = UTType.png.identifier as CFString }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard w > 0, h > 0 else { return fail("Could not read the size.") }
        let longSide = max(w, h)
        let target = min(options.maxSide ?? longSide, longSide)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // applies the orientation to the pixels
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else {
            return fail("Could not read the image.")
        }

        let isJPEG = UTType(type as String)?.conforms(to: .jpeg) == true
        if options.srgb, let space = CGColorSpace(name: CGColorSpace.sRGB) {
            let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
            let alpha: CGImageAlphaInfo = (hasAlpha && !isJPEG) ? .premultipliedLast : .noneSkipLast
            if let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: space, bitmapInfo: alpha.rawValue) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                if let converted = ctx.makeImage() { image = converted }
            }
        }

        var dict: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: options.quality]
        if !options.strip {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
                if let v = props[key] { dict[key] = v }
            }
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = nil
                dict[kCGImagePropertyTIFFDictionary] = tiff
            }
        }

        let ext = (type as String) == (CGImageSourceGetType(src) as String?) ? url.pathExtension
            : (UTType(type as String)?.preferredFilenameExtension ?? url.pathExtension)
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let writeURL = options.replace
            ? dir.appending(path: ".filetor-\(UUID().uuidString)." + ext)
            : unique(dir.appending(path: base + "-web." + ext))
        guard let out = CGImageDestinationCreateWithURL(writeURL as CFURL, type, 1, nil) else {
            return fail("This format cannot be written.")
        }
        CGImageDestinationAddImage(out, image, dict as CFDictionary)
        guard CGImageDestinationFinalize(out) else {
            try? fm.removeItem(at: writeURL)
            return fail("Could not write the image.")
        }
        if options.pngPalette, options.strip, UTType(type as String)?.conforms(to: .png) == true,
           let data = PNGQuantizer.encode(image),
           let written = (try? writeURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, data.count < written {
            try? data.write(to: writeURL)
        }
        if !options.replace { return (OptimizedItem(original: url, result: writeURL, trashedOriginal: nil), nil) }

        var trashed: NSURL?
        do { try fm.trashItem(at: url, resultingItemURL: &trashed) }
        catch {
            try? fm.removeItem(at: writeURL)
            return fail("The original could not be moved to the Trash. \(error.localizedDescription)")
        }
        let final = unique(dir.appending(path: base + "." + ext))
        do { try fm.moveItem(at: writeURL, to: final) }
        catch {
            try? fm.removeItem(at: writeURL)
            return fail(error.localizedDescription)
        }
        return (OptimizedItem(original: url, result: final, trashedOriginal: trashed as URL?), nil)
    }
}

// MARK: - PNG palette (256 colours)

import Compression

/// Median-cut quantizer that writes an indexed PNG (PLTE + tRNS) by hand, because ImageIO cannot write palette PNGs with alpha.
nonisolated enum PNGQuantizer {
    static func encode(_ image: CGImage, maxColors: Int = 256) -> Data? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        // Histogram over 5-bit colour and 3-bit alpha cells.
        let cells = 1 << 18
        let n = w * h
        var keys = [Int32](repeating: 0, count: n)
        var count = [Int](repeating: 0, count: cells)
        var sums = [Int](repeating: 0, count: cells * 4)
        for i in 0..<n {
            let a = Int(pixels[i * 4 + 3])
            var r = 0, g = 0, b = 0
            if a > 0 {
                r = Int(pixels[i * 4]); g = Int(pixels[i * 4 + 1]); b = Int(pixels[i * 4 + 2])
                if a < 255 { r = min(255, r * 255 / a); g = min(255, g * 255 / a); b = min(255, b * 255 / a) }
            }
            let key = ((r >> 3) << 13) | ((g >> 3) << 8) | ((b >> 3) << 3) | (a >> 5)
            keys[i] = Int32(key)
            count[key] += 1
            sums[key * 4] += r; sums[key * 4 + 1] += g; sums[key * 4 + 2] += b; sums[key * 4 + 3] += a
        }
        var entryKey: [Int] = [], cnt: [Int] = []
        var avg: [[Int]] = [[], [], [], []]
        for key in 0..<cells where count[key] > 0 {
            entryKey.append(key); cnt.append(count[key])
            for c in 0..<4 { avg[c].append(sums[key * 4 + c] / count[key]) }
        }
        let m = entryKey.count
        guard m > 0 else { return nil }

        // Median cut.
        struct Box { var items: [Int]; var channel: Int; var score: Int }
        func makeBox(_ items: [Int]) -> Box {
            var lo = [255, 255, 255, 255], hi = [0, 0, 0, 0], pop = 0
            for e in items {
                pop += cnt[e]
                for c in 0..<4 { lo[c] = min(lo[c], avg[c][e]); hi[c] = max(hi[c], avg[c][e]) }
            }
            var ch = 0, range = -1
            for c in 0..<4 where hi[c] - lo[c] > range { range = hi[c] - lo[c]; ch = c }
            return Box(items: items, channel: ch, score: items.count > 1 ? (range + 1) * Int(Double(pop).squareRoot()) : 0)
        }
        var boxes = [makeBox(Array(0..<m))]
        while boxes.count < maxColors {
            var bi = -1, best = 0
            for (i, b) in boxes.enumerated() where b.score > best { best = b.score; bi = i }
            guard bi >= 0 else { break }
            let box = boxes[bi]
            let sorted = box.items.sorted { avg[box.channel][$0] < avg[box.channel][$1] }
            let total = sorted.reduce(0) { $0 + cnt[$1] }
            var run = 0, cut = 1
            for (i, e) in sorted.enumerated() {
                run += cnt[e]
                if run * 2 >= total { cut = i + 1; break }
            }
            cut = min(max(cut, 1), sorted.count - 1)
            boxes[bi] = makeBox(Array(sorted[0..<cut]))
            boxes.append(makeBox(Array(sorted[cut...])))
        }

        // Palette: weighted averages, transparent entries first so tRNS stays short.
        var palette: [[Int]] = boxes.map { box in
            var s = [0, 0, 0, 0], pop = 0
            for e in box.items { pop += cnt[e]; for c in 0..<4 { s[c] += avg[c][e] * cnt[e] } }
            return s.map { $0 / max(pop, 1) }
        }
        palette.sort { $0[3] < $1[3] }

        // Nearest palette entry per histogram cell.
        var lut = [UInt8](repeating: 0, count: cells)
        for e in 0..<m {
            var bestIndex = 0, bestDist = Int.max
            for (i, p) in palette.enumerated() {
                let dr = p[0] - avg[0][e], dg = p[1] - avg[1][e], db = p[2] - avg[2][e], da = p[3] - avg[3][e]
                let d = dr * dr + dg * dg + db * db + da * da
                if d < bestDist { bestDist = d; bestIndex = i }
            }
            lut[entryKey[e]] = UInt8(bestIndex)
        }

        // Scanlines with filter type 0.
        var raw = [UInt8](repeating: 0, count: h * (w + 1))
        for y in 0..<h {
            let row = y * (w + 1)
            for x in 0..<w { raw[row + 1 + x] = lut[Int(keys[y * w + x])] }
        }

        var dst = [UInt8](repeating: 0, count: raw.count + raw.count / 8 + 1024)
        let size = raw.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_encode_buffer(d.baseAddress!, d.count, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard size > 0 else { return nil }
        let zlib: [UInt8] = [0x78, 0x9C] + dst[0..<size] + be32(adler32(raw))

        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", be32(UInt32(w)) + be32(UInt32(h)) + [8, 3, 0, 0, 0])
        png += chunk("PLTE", palette.flatMap { [UInt8($0[0]), UInt8($0[1]), UInt8($0[2])] })
        if let last = palette.lastIndex(where: { $0[3] < 255 }) {
            png += chunk("tRNS", palette[0...last].map { UInt8($0[3]) })
        }
        png += chunk("IDAT", zlib)
        png += chunk("IEND", [])
        return Data(png)
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]
    }

    private static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let t = Array(type.utf8)
        return be32(UInt32(body.count)) + t + body + be32(crc32(t + body))
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 255)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for v in bytes { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        return (b << 16) | a
    }
}
