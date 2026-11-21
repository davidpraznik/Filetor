import AppKit

/// The colour choice for glass folders: each folder its own colour ("multi") or one colour for all.
enum FolderTint {
    private static func c(_ hex: Int) -> NSColor {
        NSColor(deviceRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static let all: [(id: String, name: String, light: NSColor, dark: NSColor)] = [
        ("multi", "Multicolour", c(0x56a8ff), c(0x2f7fe8)),
        ("blue", "Blue", c(0x56a8ff), c(0x2f7fe8)),
        ("purple", "Purple", c(0x8b6cff), c(0x5a3df0)),
        ("pink", "Pink", c(0xff4fa8), c(0xd91f7c)),
        ("red", "Red", c(0xff5c78), c(0xe5254a)),
        ("orange", "Orange", c(0xff9a4d), c(0xf26a1b)),
        ("yellow", "Yellow", c(0xffd54a), c(0xf0b400)),
        ("green", "Green", c(0x46d96f), c(0x1fa84b)),
        ("graphite", "Graphite", c(0x98a3bd), c(0x69748f)),
    ]
    static var currentID: String { UserDefaults.standard.string(forKey: "folderColor") ?? "multi" }
    /// nil for Multicolour.
    static var current: (light: NSColor, dark: NSColor)? {
        let id = currentID
        if id == "multi" { return nil }
        return all.first { $0.id == id }.map { ($0.light, $0.dark) }
    }
    static func index(_ id: String) -> Int { all.firstIndex { $0.id == id } ?? 0 }
}

/// Folders that get a coloured glass icon with a symbol. The theme is chosen by the folder name.
enum FolderTheme: CaseIterable {
    case documents, downloads, desktop, pictures, music, movies, designs, code, publicShare, applications
    /// Any other folder: the same glass folder, without a symbol.
    case plain

    init?(folderName name: String) {
        let n = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        switch n {
        case "documents", "dokumenti": self = .documents
        case "downloads", "prenosi": self = .downloads
        case "desktop", "namizje": self = .desktop
        case "pictures", "slike": self = .pictures
        case "music", "glasba": self = .music
        case "movies", "filmi", "footage", "video", "videos": self = .movies
        case "designs", "design", "oblikovanje": self = .designs
        case "code", "dev", "projects", "projekti": self = .code
        case "public", "javno": self = .publicShare
        case "applications", "aplikacije", "programi": self = .applications
        default:
            let words = n.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            // A keyword counts only in short names ("Projekti 2026", "Web design"). In a long name it is part of a title.
            let short = words.count <= 3
            if n.hasSuffix("_dev") || n.hasSuffix("-dev") || (short && words.contains("projekti")) { self = .code }
            else if short && (words.contains("design") || words.contains("designs")) { self = .designs }
            else { return nil }
        }
    }

    /// Light colour (glass tint) and dark colour (back of the folder).
    fileprivate var colors: (light: NSColor, dark: NSColor) {
        func c(_ hex: Int) -> NSColor {
            NSColor(deviceRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        if let tint = FolderTint.current { return tint }
        switch self {
        case .code: return (c(0x8b6cff), c(0x5a3df0))
        case .designs: return (c(0xff4fa8), c(0xd91f7c))
        case .movies: return (c(0x3d90ff), c(0x1b62ee))
        case .documents: return (c(0x34bbff), c(0x0f86dd))
        case .downloads: return (c(0x1fdcc0), c(0x08ac98))
        case .music: return (c(0xff5c78), c(0xe5254a))
        case .pictures: return (c(0x46d96f), c(0x1fa84b))
        case .desktop: return (c(0x98a3bd), c(0x69748f))
        case .plain: return (c(0x56a8ff), c(0x2f7fe8))
        case .publicShare: return (c(0xff7a59), c(0xe84a2a))
        case .applications: return (c(0x6f7bff), c(0x4350e8))
        }
    }
}

/// Draws the themed glass folders. Everything is drawn in a 120 x 100 grid, like the mockup.
enum ThemedFolderIcon {
    private static let cache = NSCache<NSString, NSImage>()

    private static let linkCache = NSCache<NSString, NSNumber>()

    /// Whether an alias or symbolic link points to a folder.
    static func linksToFolder(_ url: URL) -> Bool {
        let key = url.path as NSString
        if let hit = linkCache.object(forKey: key) { return hit.boolValue }
        var target: URL?
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            target = url.resolvingSymlinksInPath()
        } else {
            target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting])
        }
        let isFolder = target.flatMap { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory } ?? false
        linkCache.setObject(NSNumber(value: isFolder), forKey: key)
        return isFolder
    }

    /// The glass look for an item, or nil for files and apps. Aliases of folders get the arrow badge.
    static func style(for item: FileItem) -> (theme: FolderTheme, link: Bool)? {
        if item.isPackage { return nil }
        if item.isLink, linksToFolder(item.url) { return (FolderTheme(folderName: item.name) ?? .plain, true) }
        if item.isDirectory { return (FolderTheme(folderName: item.name) ?? .plain, false) }
        return nil
    }

    /// The glass icon for a folder when the theme is on, otherwise the system icon.
    static func icon(forFile url: URL, side: CGFloat) -> NSImage {
        if UserDefaults.standard.bool(forKey: "themedFolders"), let style = style(for: FileItem(url: url)) {
            return image(style.theme, side: side, link: style.link)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The icon is only drawn with its symbol when it is big enough to read it.
    static let minimumGlyphSide: CGFloat = 26

    static func image(_ theme: FolderTheme, side: CGFloat, glyph: Bool? = nil, link: Bool = false) -> NSImage {
        let withGlyph = glyph ?? (side >= minimumGlyphSide)
        let key = "\(FolderTint.currentID)|\(theme)|\(Int(side.rounded()))|\(withGlyph)|\(link)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = render(theme, side: side, glyph: withGlyph, link: link)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func render(_ theme: FolderTheme, side: CGFloat, glyph: Bool, link: Bool) -> NSImage {
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let px = max(1, Int((side * backing).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage(size: NSSize(width: side, height: side)) }

        // Drawn in pixels: the bitmap is exactly px x px, and the image is scaled to its size in points afterwards.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let ctx = context.cgContext
        let full = CGFloat(px)
        ctx.translateBy(x: 0, y: full)
        ctx.scaleBy(x: 1, y: -1)
        let u = full / 110
        ctx.translateBy(x: (full - 104 * u) / 2 - 8 * u, y: (full - 88 * u) / 2 - 8 * u)
        ctx.scaleBy(x: u, y: u)
        draw(theme, in: ctx, shadowScale: u, glyph: glyph, link: link)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }

    private static func white(_ stops: [(CGFloat, CGFloat)]) -> CGGradient {
        let colors = stops.map { NSColor(deviceRed: 1, green: 1, blue: 1, alpha: $0.1).cgColor } as CFArray
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: stops.map { $0.0 })!
    }

    private static func draw(_ theme: FolderTheme, in ctx: CGContext, shadowScale: CGFloat, glyph: Bool, link: Bool) {
        let (light, dark) = theme.colors
        let all: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

        // Back of the folder with its tab, darker than the glass in front. It also casts the soft shadow.
        let back = SVGPath.make("M8 14a8 8 0 0 1 8-8h26a8 8 0 0 1 6 3l5 6h51a8 8 0 0 1 8 8v63a8 8 0 0 1-8 8H16a8 8 0 0 1-8-8z")
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4 * shadowScale), blur: 7 * shadowScale,
                      color: NSColor.black.withAlphaComponent(0.2).cgColor)
        ctx.addPath(back)
        ctx.setFillColor(dark.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(back)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.fillPath()

        // Glass panel in front.
        func panel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
            CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
        }
        let glass = panel(8, 22, 104, 72, 8)
        ctx.addPath(glass)
        ctx.setFillColor(light.withAlphaComponent(0.6).cgColor)
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.drawLinearGradient(white([(0, 0.42), (0.45, 0.08), (1, 0.16)]),
                               start: CGPoint(x: 0, y: 22), end: CGPoint(x: 0, y: 94), options: all)
        ctx.translateBy(x: 28.8, y: 25.6)
        ctx.scaleBy(x: 78, y: 54)
        ctx.drawRadialGradient(white([(0, 0.45), (1, 0)]), startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()

        func line(_ path: CGPath, width: CGFloat, gradient: CGGradient, from: CGPoint, to: CGPoint) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setLineWidth(width)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(gradient, start: from, end: to, options: all)
            ctx.restoreGState()
        }
        // Soft light along the lower edge, as if it passed through the glass.
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.drawLinearGradient(white([(0.5, 0), (1, 0.3)]), start: CGPoint(x: 0, y: 22), end: CGPoint(x: 0, y: 94), options: all)
        // Glow of light at the top of the glass, in the middle.
        ctx.translateBy(x: 60, y: 22)
        ctx.scaleBy(x: 42, y: 15)
        ctx.drawRadialGradient(white([(0, 0.75), (0.45, 0.25), (1, 0)]), startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
        // Edge light: bright at the top left, gone by the middle, nothing at the bottom right.
        line(panel(8.6, 22.6, 102.8, 70.8, 7.5), width: 1.1,
             gradient: white([(0, 0.7), (0.3, 0.18), (0.6, 0), (1, 0)]), from: CGPoint(x: 8.6, y: 22.6), to: CGPoint(x: 111.4, y: 93.4))
        // Bright spot on the upper edge, in the middle.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 20, width: 120, height: 12))
        line(panel(8.6, 22.6, 102.8, 70.8, 7.5), width: 1.1,
             gradient: white([(0, 0), (0.5, 0.9), (1, 0)]), from: CGPoint(x: 8.6, y: 0), to: CGPoint(x: 111.4, y: 0))
        ctx.restoreGState()

        if glyph { drawGlyph(theme, ctx) }
        if link { drawLinkBadge(ctx, shadowScale: shadowScale) }
    }

    /// The small arrow of an alias, at the lower left, like the one macOS puts on aliases.
    private static func drawLinkBadge(_ ctx: CGContext, shadowScale: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -shadowScale), blur: 2 * shadowScale,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 12, y: 76, width: 18, height: 18))
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(SVGPath.make("M17.5 89L24.5 82M19 82H24.5V87.5"))
        ctx.strokePath()
    }

    /// The symbols, as paths on the same grid. Positions are the final ones from the mockup.
    private static func drawGlyph(_ theme: FolderTheme, _ ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setFillColor(NSColor.white.cgColor)

        func stroke(_ d: String, _ width: CGFloat, round: Bool = true) {
            ctx.addPath(SVGPath.make(d))
            ctx.setLineWidth(width)
            ctx.setLineCap(round ? .round : .butt)
            ctx.setLineJoin(round ? .round : .miter)
            ctx.strokePath()
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat, _ width: CGFloat) {
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setLineWidth(width)
            ctx.setLineJoin(.miter)
            ctx.strokePath()
        }
        func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, degrees: CGFloat) {
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: degrees * .pi / 180)
            ctx.fillEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            ctx.restoreGState()
        }

        ctx.saveGState()
        switch theme {
        case .code:
            ctx.translateBy(x: 0, y: -9)
            stroke("M54 58l-9 9 9 9M66 58l9 9-9 9", 2.06)
        case .designs:
            ctx.translateBy(x: -1.0607, y: -8.9393)
            ctx.translateBy(x: 60, y: 68)
            ctx.rotate(by: .pi / 4)
            ctx.translateBy(x: -60, y: -68)
            stroke("M54 49a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v28l-6 10-6-10z", 1.84)
            stroke("M54 57h12M54 77h12", 1.84)
        case .movies:
            ctx.translateBy(x: 0, y: -9)
            box(46, 55, 28, 24, radius: 3, 1.84)
            stroke("M53 55v24M67 55v24M46 63h7M46 71h7M67 63h7M67 71h7", 1.38, round: false)
        case .documents:
            ctx.translateBy(x: -1, y: -10)
            stroke("M52 52h12l9 9v20a3 3 0 0 1-3 3H52a3 3 0 0 1-3-3V55a3 3 0 0 1 3-3z", 1.84)
            stroke("M64 52v6a3 3 0 0 0 3 3h6", 1.84)
            stroke("M55 72h12M55 78h12", 1.63)
        case .downloads:
            ctx.translateBy(x: 0, y: -11)
            stroke("M60 52v24M50 68l10 10 10-10M48 86h24", 2.06)
        case .music:
            ctx.translateBy(x: 1.74, y: 2.06)
            stroke("M52.475 66.34V43.34l21.825-5.06v23", 2.22)
            oval(47.34, 67.35, 6.375, 4.5, degrees: -18)
            oval(69.18, 62.18, 6.375, 4.5, degrees: -18)
        case .pictures:
            ctx.translateBy(x: 0, y: -9)
            box(46, 54, 28, 26, radius: 4, 1.84)
            stroke("M46 76l9-9 8 8 5-5 6 6", 1.61)
            ctx.fillEllipse(in: CGRect(x: 63, y: 59, width: 6, height: 6))
        case .plain:
            break
        case .publicShare:
            ctx.translateBy(x: 0, y: -8)
            stroke("M60 48L78 66L60 84L42 66Z", 1.84)
            ctx.addEllipse(in: CGRect(x: 57.4, y: 57.4, width: 5.2, height: 5.2))
            ctx.setLineWidth(1.84)
            ctx.strokePath()
            stroke("M60 65V72M54.5 68.5H65.5M60 72L56.5 78M60 72L63.5 78", 1.84)
        case .applications:
            ctx.translateBy(x: -0.5, y: -9)
            stroke("M57.9 51.8L74.5 82.2M63.3 51.8L46 81.4M41.7 73.4H48.5M52.9 73.4H67.7M72.1 73.4H79.3", 1.84)
        case .desktop:
            ctx.translateBy(x: 0, y: -8)
            box(44, 53, 32, 26, radius: 5, 1.84)
            stroke("M44 59.5H76", 1.84, round: false)
            stroke("M55 73H65", 2.52)
        }
        ctx.restoreGState()
    }
}

/// Reads the part of SVG path syntax the icons use: M L H V A Z, absolute and relative.
enum SVGPath {
    static func make(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let chars = Array(d)
        var i = 0
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var cmd: Character = " "

        func skip() { while i < chars.count, chars[i] == " " || chars[i] == "," { i += 1 } }
        func number() -> CGFloat {
            skip()
            var s = ""
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            while i < chars.count, chars[i].isNumber || chars[i] == "." { s.append(chars[i]); i += 1 }
            return CGFloat(Double(s) ?? 0)
        }

        while true {
            skip()
            guard i < chars.count else { break }
            if chars[i].isLetter {
                cmd = chars[i]
                i += 1
            } else if cmd == "M" {
                cmd = "L"
            } else if cmd == "m" {
                cmd = "l"
            }
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                let x = number(), y = number()
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                start = cur
                path.move(to: cur)
            case "L", "l":
                let x = number(), y = number()
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: cur)
            case "H", "h":
                let x = number()
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
            case "V", "v":
                let y = number()
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
            case "A", "a":
                let rx = number(), ry = number(), rot = number()
                let large = number() != 0, sweep = number() != 0
                let x = number(), y = number()
                let end = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                arc(path, from: cur, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep, to: end)
                cur = end
            case "Z", "z":
                path.closeSubpath()
                cur = start
            default:
                return path
            }
        }
        return path
    }

    /// An SVG elliptical arc as cubic curves.
    private static func arc(_ path: CGMutablePath, from p0: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rotation: CGFloat,
                            large: Bool, sweep: Bool, to p1: CGPoint) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cp = cos(phi), sp = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy
        let y1 = -sp * dx + cp * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var co = sqrt(max(0, num / den))
        if large == sweep { co = -co }
        let cxp = co * rx * y1 / ry
        let cyp = -co * ry * x1 / rx
        let cx = cp * cxp - sp * cyp + (p0.x + p1.x) / 2
        let cy = sp * cxp + cp * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry
        let vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
        var a = angle(1, 0, ux, uy)
        var sweepAngle = angle(ux, uy, vx, vy)
        if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }

        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        let t = 4 / 3 * tan(delta / 4)
        func map(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: cp * rx * u - sp * ry * v + cx, y: sp * rx * u + cp * ry * v + cy)
        }
        for _ in 0..<segments {
            let ca = cos(a), sa = sin(a), cb = cos(a + delta), sb = sin(a + delta)
            path.addCurve(to: map(cb, sb), control1: map(ca - t * sa, sa + t * ca), control2: map(cb + t * sb, sb - t * cb))
            a += delta
        }
    }
}
