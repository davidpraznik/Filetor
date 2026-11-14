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
