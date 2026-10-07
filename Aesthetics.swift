//  Aesthetics.swift
//  SHARED FILE — add to BOTH the app target and the widget extension target.
//
//  The scene is built once as a grid of meanings (frame, glass, rain, hill, wall…).
//  Each aesthetic here is just a different way of drawing that grid, so every
//  window, weather, animation frame and widget size works in every look.

import SwiftUI

enum Aesthetic: String, PixelOption {
    case pixel, dither, halftone, ascii, terminal, blueprint, neon
    static let titles: [Aesthetic: String] = [
        .pixel: "Pixel Art", .dither: "1-Bit Dither", .halftone: "Risograph", .ascii: "ASCII Typewriter",
        .terminal: "Terminal", .blueprint: "Blueprint", .neon: "Neon",
    ]

    /// Outline looks draw their labels as real text instead of pixel letters.
    var textLabels: Bool { self == .blueprint || self == .neon }

    /// ASCII & Terminal compose the whole scene directly in characters.
    var isCharacterGrid: Bool { self == .ascii || self == .terminal }

    /// Background behind everything (also used for the widget's container background).
    func background(_ wallpaper: Wallpaper) -> UInt32 {
        switch self {
        case .pixel: wallpaper.colors.wall
        case .dither: Look.ditherDark
        case .halftone: Look.paper
        case .ascii: Look.typewriterPaper
        case .terminal: Look.terminalBlack
        case .blueprint: Look.blueprintBlue
        case .neon: Look.neonNight
        }
    }
}

extension WindowStyle {
    var backgroundHex: UInt32 { aesthetic.background(wallpaper) }
}

/// Fixed colours for each look.
enum Look {
    static let ditherDark: UInt32 = 0x1F1D1A, ditherLight: UInt32 = 0xE9E4D6
    static let paper: UInt32 = 0xF2EBDD, risoBlue: UInt32 = 0x2F5DA8, risoPink: UInt32 = 0xFF5C8A
    // ASCII Typewriter: dark ink on warm cream. Terminal: soft pale lime on charcoal.
    static let typewriterPaper: UInt32 = 0xF6EFE4, typewriterInk: UInt32 = 0x161514
    static let typeHi: UInt32 = 0x161514, typeMid: UInt32 = 0x2C2A27, typeLo: UInt32 = 0xA59D90
    static let terminalBlack: UInt32 = 0x121413, terminalGreen: UInt32 = 0xC2E8A4, terminalDim: UInt32 = 0x7E9A72
    static let termHi: UInt32 = 0xEAFFD0, termMid: UInt32 = 0xC2E8A4, termLo: UInt32 = 0x5E7656
    static let blueprintBlue: UInt32 = 0x1C4E8E
    static let neonNight: UInt32 = 0x0B0A16, neonPink: UInt32 = 0xFF4FD8, neonCyan: UInt32 = 0x5CE1FF

    /// Neon frame colour follows the frame material, so changing the window changes the glow.
    static func neonFrame(_ m: WindowMaterial) -> UInt32 {
        switch m {
        case .wood: 0xFFB347        // amber
        case .painted: 0xEAF4FF     // ice white
        case .stone: 0xB28CFF       // violet
        case .brick: 0xFF4F6D       // red
        case .metal: 0x3DFFC8       // aqua
        }
    }
}

// MARK: - Canvas

struct AestheticCanvas: View {
    let buffer: PixelBuffer
    let palette: PixelPalette
    let pixelSize: CGFloat
    let aesthetic: Aesthetic
    let material: WindowMaterial
    let isDay: Bool
    let tick: Int

    var body: some View {
        Canvas { ctx, size in
            let r = RenderInput(buffer: buffer, palette: palette, ps: pixelSize, size: size,
                                origin: CGPoint(x: ((size.width - CGFloat(buffer.width) * pixelSize) / 2).rounded(.down),
                                                y: ((size.height - CGFloat(buffer.height) * pixelSize) / 2).rounded(.down)),
                                full: palette.fullColor, isDay: isDay, tick: tick,
                                frameNeon: Look.neonFrame(material))
            switch aesthetic {
            case .pixel, .ascii, .terminal: Painters.pixel(&ctx, r)   // ASCII & Terminal use CharGridView instead
            case .dither: Painters.dither(&ctx, r)
            case .halftone: Painters.halftone(&ctx, r)
            case .blueprint: Painters.lines(&ctx, r, neon: false)
            case .neon: Painters.lines(&ctx, r, neon: true)
            }
        }
    }
}

struct RenderInput {
    let buffer: PixelBuffer
    let palette: PixelPalette
    let ps: CGFloat
    let size: CGSize
    let origin: CGPoint
    let full: Bool
    let isDay: Bool
    let tick: Int
    let frameNeon: UInt32

    func rect(_ x: Int, _ y: Int, w: Int = 1, h: Int = 1) -> CGRect {
        CGRect(x: origin.x + CGFloat(x) * ps, y: origin.y + CGFloat(y) * ps, width: CGFloat(w) * ps, height: CGFloat(h) * ps)
    }
}

enum Painters {

    // MARK: Pixel art — the original look

    static func pixel(_ ctx: inout GraphicsContext, _ r: RenderInput) {
        let b = r.buffer
        var paths: [Ink: Path] = [:]
        for y in 0..<b.height {
            var x = 0
            while x < b.width {
                let ink = b[x, y]
                var run = 1
                while x + run < b.width && b[x + run, y] == ink { run += 1 }
                if ink != .clear { paths[ink, default: Path()].addRect(r.rect(x, y, w: run)) }
                x += run
            }
        }
        for (ink, path) in paths { ctx.fill(path, with: .color(r.palette.color(ink))) }
    }

    // MARK: 1-bit dither — two colours, ordered (Bayer) dithering at 1-point dots

    static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        .map { $0.map { ($0 + 0.5) / 16 } }

    static func dither(_ ctx: inout GraphicsContext, _ r: RenderInput) {
        let b = r.buffer
        if r.full { ctx.fill(Path(CGRect(origin: .zero, size: r.size)), with: .color(Color(hex: Look.ditherDark))) }
        let s = max(1, Int(r.ps.rounded()))          // dots per art pixel
        let d = r.ps / CGFloat(s)
        var lum = [Double](repeating: -1, count: b.width * b.height)
        for y in 0..<b.height {
            for x in 0..<b.width where b[x, y] != .clear {
                lum[y * b.width + x] = min(1, max(0, (r.palette.luminance(b[x, y]) - 0.08) / 0.84))
            }
        }
        // Labels stay crisp: solid letters with a solid halo around them, never dithered.
        for y in 0..<b.height {
            for x in 0..<b.width where b[x, y] == .text || b[x, y] == .textDim {
                let lightText = r.palette.luminance(b[x, y]) >= 0.5
                lum[y * b.width + x] = lightText ? 2 : -2
                for dy in -2...2 {                     // a solid plate 2px wide behind every letter
                    for dx in -2...2 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < b.width, ny < b.height else { continue }
                        let k = b[nx, ny]
                        if k == .text || k == .textDim || k == .clear { continue }
                        lum[ny * b.width + nx] = lightText ? -2 : 2
                    }
                }
            }
        }
        var light = Path()
        for gy in 0..<(b.height * s) {
            var gx = 0
            while gx < b.width * s {
                let L = lum[(gy / s) * b.width + gx / s]
                if L >= 0 && L > bayer[gy & 3][gx & 3] {
                    var run = 1
                    while gx + run < b.width * s {
                        let L2 = lum[(gy / s) * b.width + (gx + run) / s]
                        if L2 >= 0 && L2 > bayer[gy & 3][(gx + run) & 3] { run += 1 } else { break }
                    }
                    light.addRect(CGRect(x: r.origin.x + CGFloat(gx) * d, y: r.origin.y + CGFloat(gy) * d,
                                         width: CGFloat(run) * d, height: d))
                    gx += run
                } else { gx += 1 }
            }
        }
        ctx.fill(light, with: .color(r.full ? Color(hex: Look.ditherLight) : .white))
    }

    // MARK: Risograph — blue and fluoro-pink halftone dots, slightly misregistered, on cream paper.
    // The wall is left as bare paper so the window is the print's subject.

    static func halftone(_ ctx: inout GraphicsContext, _ r: RenderInput) {
        let b = r.buffer
        if r.full { ctx.fill(Path(CGRect(origin: .zero, size: r.size)), with: .color(Color(hex: Look.paper))) }
        let cellPx = 2
        let cell = r.ps * CGFloat(cellPx)
        var blue = Path(), pink = Path(), solid = Path()
        for cy in stride(from: 0, to: b.height, by: cellPx) {
            for cx in stride(from: 0, to: b.width, by: cellPx) {
                var a = 0.0, m = 0.0, n = 0.0
                for y in cy..<min(cy + cellPx, b.height) {
                    for x in cx..<min(cx + cellPx, b.width) {
                        let ink = b[x, y]
                        if ink == .clear { continue }
                        if ink == .text || ink == .textDim || ink == .outline { solid.addRect(r.rect(x, y)); continue }
                        if ink == .wall || ink == .wallLine || ink == .wallAccent { n += 1; continue }   // bare paper
                        if r.full {
                            let (rr, gg, _) = r.palette.rgb(ink)
                            a += pow(1 - rr, 1.4); m += pow(1 - gg, 1.4)   // blue absorbs red, pink absorbs green
                        } else {
                            a += r.palette.luminance(ink)
                        }
                        n += 1
                    }
                }
                guard n > 0 else { continue }
                a /= n; m /= n
                if !r.isDay { a *= 0.7; m *= 0.7 }      // keep night prints from filling in
                let center = CGPoint(x: r.origin.x + CGFloat(cx) * r.ps + cell / 2, y: r.origin.y + CGFloat(cy) * r.ps + cell / 2)
                func dot(_ amount: Double, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
                    let rad = CGFloat(amount.squareRoot()) * cell * 0.62
                    return CGRect(x: center.x + dx - rad, y: center.y + dy - rad, width: rad * 2, height: rad * 2)
                }
                if a > 0.04 { blue.addEllipse(in: dot(a, 0, 0)) }
                if r.full && m > 0.04 { pink.addEllipse(in: dot(m, cell * 0.3, cell * 0.22)) }
            }
        }
        if r.full {
            ctx.fill(blue, with: .color(Color(hex: Look.risoBlue).opacity(0.9)))
            ctx.blendMode = .multiply
            ctx.fill(pink, with: .color(Color(hex: Look.risoPink).opacity(0.9)))
            ctx.blendMode = .normal
            ctx.fill(solid, with: .color(Color(hex: Look.risoBlue)))
        } else {
            ctx.fill(blue, with: .color(.white))
            ctx.fill(solid, with: .color(.white))
        }
    }

    // MARK: Blueprint & Neon — outlines of every shape

    static func lines(_ ctx: inout GraphicsContext, _ r: RenderInput, neon: Bool) {
        let b = r.buffer
        if r.full {
            ctx.fill(Path(CGRect(origin: .zero, size: r.size)), with: .color(Color(hex: neon ? Look.neonNight : Look.blueprintBlue)))
        }
        if !neon {
            // drafting grid: fine lines every 4 art pixels, stronger every 16
            var minor = Path(), major = Path()
            var i = 0
            for x in stride(from: r.origin.x, through: r.origin.x + CGFloat(b.width) * r.ps, by: r.ps * 4) {
                let line = CGRect(x: x, y: 0, width: 0.5, height: r.size.height)
                if i % 4 == 0 { major.addRect(line) } else { minor.addRect(line) }; i += 1
            }
            i = 0
            for y in stride(from: r.origin.y, through: r.origin.y + CGFloat(b.height) * r.ps, by: r.ps * 4) {
                let line = CGRect(x: 0, y: y, width: r.size.width, height: 0.5)
                if i % 4 == 0 { major.addRect(line) } else { minor.addRect(line) }; i += 1
            }
            ctx.fill(minor, with: .color(.white.opacity(0.07)))
            ctx.fill(major, with: .color(.white.opacity(0.15)))
        }

        var edges: [Shape2D: Path] = [:]
        var specks: [Shape2D: Path] = [:]
        func shape(_ x: Int, _ y: Int) -> Shape2D {
            let s = Shape2D(b[x, y])
            return s.isSpeck ? .glass : s           // tiny things don't break outlines
        }
        for y in 0..<b.height {
            for x in 0..<b.width {
                let raw = Shape2D(b[x, y])
                if raw.isSpeck { specks[raw, default: Path()].addRect(r.rect(x, y)); continue }
                let here = shape(x, y)
                if x + 1 < b.width {
                    let right = shape(x + 1, y)
                    if right != here {
                        let owner = max(here, right)
                        let px = r.origin.x + CGFloat(x + 1) * r.ps, py = r.origin.y + CGFloat(y) * r.ps
                        edges[owner, default: Path()].move(to: CGPoint(x: px, y: py))
                        edges[owner, default: Path()].addLine(to: CGPoint(x: px, y: py + r.ps))
                    }
                }
                if y + 1 < b.height {
                    let below = shape(x, y + 1)
                    if below != here {
                        let owner = max(here, below)
                        let px = r.origin.x + CGFloat(x) * r.ps, py = r.origin.y + CGFloat(y + 1) * r.ps
                        edges[owner, default: Path()].move(to: CGPoint(x: px, y: py))
                        edges[owner, default: Path()].addLine(to: CGPoint(x: px + r.ps, y: py))
                    }
                }
            }
        }
        for (s, path) in edges where s != .wall && s != .glass {
            let hue = (s == .frame || s == .box) ? r.frameNeon : s.neon
            let color = !r.full ? Color.white : (neon ? Color(hex: hue) : .white.opacity(0.88))
            if neon {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 2.4))
                    layer.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 2.2)
                }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: neon ? 1 : 0.9, lineCap: .square))
        }
        for (s, path) in specks {
            let color = !r.full ? Color.white : (neon ? Color(hex: s.neon) : .white.opacity(0.75))
            ctx.fill(path, with: .color(color))
        }
    }
}

/// Coarse shape categories for the outline styles. Higher raw value wins an edge.
enum Shape2D: Int, Comparable {
    case wall = 0, glass, hillFar, hillNear, tree, fog, frost, cloud, sun, flower, box, plant, pot, cat, frame
    case rain = 100, snow, star, bird, firefly, butterfly, drop, bolt     // drawn as filled specks

    init(_ ink: Ink) {
        switch ink {
        case .frameDark, .frame, .frameLight, .mortar, .moss: self = .frame
        case .sky, .skyTop, .skyFlash, .glint: self = .glass
        case .sun: self = .sun
        case .cloud, .cloudMid, .cloudShade: self = .cloud
        case .rain: self = .rain
        case .rainFar: self = .glass            // the faint far layer would only clutter outlines
        case .snow, .snowCap: self = .snow
        case .bolt: self = .bolt
        case .star, .starDim: self = .star
        case .glassDrop: self = .drop
        case .frost: self = .frost
        case .fogWisp: self = .fog
        case .hillFar: self = .hillFar
        case .hillNear: self = .hillNear
        case .tree: self = .tree
        case .bird: self = .bird
        case .firefly: self = .firefly
        case .butterfly: self = .butterfly
        case .flowerA, .flowerB, .flowerC, .flowerCenter, .leaf, .leafDark: self = .flower
        case .box, .boxLight, .boxShade: self = .box
        case .plantLeaf, .plantLeafDark, .plantBloom: self = .plant
        case .pot, .potShade: self = .pot
        case .catBody, .catBelly, .catEye, .catNose: self = .cat
        default: self = .wall           // wall patterns, outline, labels, clear
        }
    }

    var isSpeck: Bool { rawValue >= 100 }
    static func < (a: Shape2D, b: Shape2D) -> Bool { a.rawValue < b.rawValue }

    var neon: UInt32 {
        switch self {
        case .frame, .box: Look.neonPink      // overridden by the material colour when drawn
        case .sun, .firefly: 0xFFE45C
        case .cloud, .frost, .drop: Look.neonCyan
        case .rain: 0x6C8CFF
        case .fog: 0xB49CFF
        case .hillFar, .hillNear, .tree, .plant: 0x5CFF9D
        case .flower, .cat, .butterfly, .pot: 0xFFA94D
        default: 0xFFFFFF
        }
    }
}

// MARK: - Labels as real text (Blueprint & Neon)

/// Time top-left, temperature top-right, "CITY, ST" centred along the bottom.
struct TextLabels: View {
    let time: String
    let temp: String
    let place: String
    let aesthetic: Aesthetic
    let material: WindowMaterial
    let fullColor: Bool
    let inset: CGFloat
    let size: CGFloat

    private var primary: Color {
        guard fullColor else { return .white }
        return aesthetic == .neon ? Color(hex: Look.neonFrame(material)) : .white   // matches the frame's glow
    }
    private var secondary: Color {
        guard fullColor else { return .white.opacity(0.8) }
        return aesthetic == .neon ? Color(hex: Look.neonCyan) : .white.opacity(0.75)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                label(time, primary)
                Spacer(minLength: 4)
                label(temp, primary)
            }
            Spacer(minLength: 0)
            label(place, secondary)
        }
        .font(.system(size: size * 1.15, weight: .semibold, design: .monospaced))
        .padding(.horizontal, inset)
        .padding(.vertical, inset - 1)
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .shadow(color: aesthetic == .neon && fullColor ? color.opacity(0.9) : .clear, radius: 3)
    }
}

// MARK: - Character weather display (ASCII Typewriter & Terminal)
//
// Light, airy character drawings — each mark chosen to follow the shape (Terminal converts every
// mark to the shade blocks █ ▓ ▒ ░ by density, keeping the same composition):
//   sun     a dotted core with 16 dashed rays, each ray drawn with - | / \ to match its direction
//   cloud   rows of = and - strokes (+ on paper) with a dotted underside
//   rain    neat columns of / slashes          storm  a solid bolt with clear space around it
//   fog     stacked dashed lines inside an oval  snow   * x + . flakes over a bumpy dotted ground
//   night   a dithered crescent, + stars, dotted hills on the horizon
// Depth comes from three tones (bright / normal / faint); everything moves once a minute.

struct AsciiCell {
    var ch: Character = " "
    var tone = 1            // 0 faint · 1 normal · 2 bright
}

struct AsciiGrid {
    let cols: Int
    let rows: Int
    private(set) var cells: [AsciiCell]

    init(cols: Int, rows: Int) {
        self.cols = max(0, cols)
        self.rows = max(0, rows)
        cells = Array(repeating: AsciiCell(), count: self.cols * self.rows)
    }

    subscript(c: Int, r: Int) -> AsciiCell {
        get { (c >= 0 && r >= 0 && c < cols && r < rows) ? cells[r * cols + c] : AsciiCell() }
        set { if c >= 0 && r >= 0 && c < cols && r < rows { cells[r * cols + c] = newValue } }
    }

    mutating func put(_ c: Int, _ r: Int, _ ch: Character, _ tone: Int) {
        self[c, r] = AsciiCell(ch: ch, tone: tone)
    }
}

typealias Mark = (ch: Character, tone: Int)

/// One cell of the picture: grid position, centre in the unit square (0…1, y down), and cell size.
struct MarkCtx {
    let c: Int, r: Int          // position in the whole grid (for row textures and rain lanes)
    let lc: Int, lr: Int        // position inside the picture
    let x: Double, y: Double
    let dx: Double, dy: Double
    let tick: Int
    let terminal: Bool
}

enum WeatherMarks {

    static func mark(_ k: MarkCtx, _ cond: SkyCondition, day: Bool, rays: [[Int: Mark]]) -> Mark? {
        let drift = 0.03 * (tri(k.tick, 6) - 0.5)        // clouds sway gently
        let flash = pmod(k.tick, 4) == 0
        func first(_ layers: [() -> Mark?]) -> Mark? {
            for layer in layers { if let m = layer() { return m } }
            return nil
        }
        switch cond {
        case .clear where day:
            return sun(k, 0.5, 0.5, 0.18, rays: rays[0])
        case .clear:
            return first([{ moon(k, 0.5, 0.42, 0.32) },
                          { stars(k, [(0.16, 0.18), (0.84, 0.14), (0.9, 0.46), (0.12, 0.5), (0.28, 0.3),
                                      (0.74, 0.66), (0.2, 0.7), (0.86, 0.78), (0.5, 0.1)]) },
                          { hills(k) }])
        case .partlyCloudy where day:
            return first([{ cloud(k, 0.6 + drift, 0.64, 0.4, tone: 1) },
                          { sun(k, 0.32, 0.34, 0.12, rays: rays[1]) }])
        case .partlyCloudy:
            return first([{ cloud(k, 0.6 + drift, 0.66, 0.38, tone: 1) },
                          { moon(k, 0.34, 0.34, 0.22) },
                          { stars(k, [(0.84, 0.14), (0.12, 0.72), (0.92, 0.4), (0.56, 0.1)]) }])
        case .cloudy:
            return first([{ cloud(k, 0.42 + drift, 0.64, 0.4, tone: 1) },
                          { cloud(k, 0.66 - drift, 0.38, 0.3, tone: 0) }])          // farther cloud, fainter
        case .rain:
            return first([{ cloud(k, 0.5 + drift, 0.32, 0.44, tone: 1) },
                          { rain(k, top: 0.56, bottom: 0.96, left: 0.1, right: 0.9, dense: false) }])
        case .storm:
            return first([{ bolt(k, flash: flash) },
                          { cloud(k, 0.5 + drift, 0.30, 0.44, tone: 1) },
                          { rain(k, top: 0.54, bottom: 0.96, left: 0.08, right: 0.92, dense: true) }])
        case .snow:
            return snow(k)
        case .fog:
            return fog(k)
        }
    }

    // Helpers ---------------------------------------------------------------

    private static func tri(_ tick: Int, _ n: Int) -> Double {
        let p = Double(pmod(tick, n))
        return 1 - abs(p - Double(n) / 2) / (Double(n) / 2)
    }
    private static func disk(_ px: Double, _ py: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Bool {
        (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r * r
    }
    private static func cloudIn(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ s: Double, _ t: Double) -> Bool {
        if y > cy + 0.45 * s - t { return false }
        if disk(x, y, cx - 0.5 * s, cy + 0.12 * s, 0.38 * s - t)
            || disk(x, y, cx - 0.05 * s, cy - 0.15 * s, 0.52 * s - t)
            || disk(x, y, cx + 0.48 * s, cy + 0.08 * s, 0.40 * s - t) { return true }
        return x >= cx - 0.5 * s + t && x <= cx + 0.48 * s - t && y >= cy + 0.1 * s
    }

    /// Rows of strokes with a dotted underside.
    private static func cloud(_ k: MarkCtx, _ cx: Double, _ cy: Double, _ s: Double, tone: Int) -> Mark? {
        guard cloudIn(k.x, k.y, cx, cy, s, 0) else { return nil }
        if k.y > cy + 0.45 * s - k.dy { return (".", tone) }
        let edge = !cloudIn(k.x, k.y, cx, cy, s, min(k.dx, k.dy) * 1.1)
        if k.terminal {
            if edge { return ("=", tone) }                          // ▒ outline
            return tone == 0 ? (" ", 0) : ("-", tone)              // ░ fill; the far cloud is outline only
        }
        return (edge ? ":" : "+", tone)
    }

    static func rayGlyph(_ a: Double) -> Character {
        let d = (a * 180 / .pi).truncatingRemainder(dividingBy: 180)
        if d < 23 || d > 157 { return "-" }
        if abs(d - 90) < 23 { return "|" }
        return d < 90 ? "\\" : "/"
    }

    /// Eight short, even rays (one per direction), set a little apart from the core.
    /// They pulse slightly longer and shorter each minute.
    static func traceRays(_ cx: Double, _ cy: Double, _ r: Double, tick: Int, ic: Int, ir: Int) -> [Int: Mark] {
        var out: [Int: Mark] = [:]
        let r0 = r * 1.5, r1 = r * (pmod(tick, 2) == 0 ? 2.25 : 2.0)
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            let c0 = (cx + cos(a) * r0) * Double(ic), w0 = (cy + sin(a) * r0) * Double(ir)
            let c1 = (cx + cos(a) * r1) * Double(ic), w1 = (cy + sin(a) * r1) * Double(ir)
            let n = max(1, Int((max(abs(c1 - c0), abs(w1 - w0)) * 1.5).rounded(.up)))
            for step in 0...n {
                let t = Double(step) / Double(n)
                let key = Int(floor(w0 + (w1 - w0) * t)) * 10000 + Int(floor(c0 + (c1 - c0) * t))
                out[key] = t > 0.85 ? (".", 0) : (rayGlyph(a), 1)
            }
        }
        return out
    }

    /// A round core (solid centre with a softer rim in Terminal, a filled disc of + on paper) plus the rays.
    private static func sun(_ k: MarkCtx, _ cx: Double, _ cy: Double, _ r: Double, rays: [Int: Mark]) -> Mark? {
        let d = hypot(k.x - cx, k.y - cy)
        if k.terminal {
            if d <= r * 0.62 { return ("O", 2) }
            if d <= r { return ("+", 2) }
        } else {
            if d <= r * 0.72 { return ("+", 1) }        // filled middle
            if d <= r { return ("+", 2) }               // bold ring
        }
        return rays[k.lr * 10000 + k.lc]
    }

    /// Dithered crescent with a dotted outline.
    private static func moon(_ k: MarkCtx, _ cx: Double, _ cy: Double, _ r: Double) -> Mark? {
        let bx = cx + 0.48 * r, by = cy - 0.26 * r, br = 0.76 * r
        guard disk(k.x, k.y, cx, cy, r) && !disk(k.x, k.y, bx, by, br) else { return nil }
        let m = min(k.dx, k.dy)
        if !disk(k.x, k.y, cx, cy, r - m) || disk(k.x, k.y, bx, by, br + m) { return (".", 1) }
        if k.terminal { return pmod(k.c + k.r, 2) == 0 ? ("x", 2) : ("+", 1) }    // ▓ ▒ checker
        return (pmod(k.c + k.r, 2) == 0 ? "#" : "x", 2)
    }

    /// Each star cycles + → * → · on its own rhythm.
    private static func stars(_ k: MarkCtx, _ points: [(Double, Double)]) -> Mark? {
        for (i, p) in points.enumerated() where abs(k.x - p.0) < k.dx * 0.6 && abs(k.y - p.1) < k.dy * 0.6 {
            switch pmod(k.tick + i, 3) {
            case 0: return ("+", 1)
            case 1: return ("*", 2)
            default: return (".", 0)
            }
        }
        return nil
    }

    /// Two faint dotted hills on the horizon.
    private static func hills(_ k: MarkCtx) -> Mark? {
        for (hx, hw, hh) in [(0.25, 0.22, 0.06), (0.75, 0.2, 0.05)] where abs(k.x - hx) < hw {
            let top = 0.9 - hh * cos((k.x - hx) / hw * .pi / 2)
            if abs(k.y - top) < k.dy * 0.55 { return (k.c % 3 == 0 ? "'" : ".", 0) }
        }
        if abs(k.y - 0.9) < k.dy * 0.55 && k.c % 2 == 0 { return (".", 0) }
        return nil
    }

    /// Columns of / slashes; each lane steps one column left every two rows and falls each minute.
    private static func rain(_ k: MarkCtx, top: Double, bottom: Double, left: Double, right: Double, dense: Bool) -> Mark? {
        guard k.y >= top, k.y <= bottom, k.x >= left, k.x <= right else { return nil }
        let lane = k.c + SceneArt.fdiv(k.r, 2)
        if pixelHash(lane, 0, 7) % (dense ? 4 : 3) == 0 { return nil }
        guard pmod(k.r - k.tick * 2 + pixelHash(lane, 1, 7) % 6, 4) < 3 else { return nil }
        return ("/", pixelHash(lane, 2, 7) % 3 == 0 ? 0 : 1)       // a few faint far streaks
    }

    private static func boltIn(_ x: Double, _ y: Double, grow: Double) -> Bool {
        var p: [(Double, Double)] = [(0.60, 0.50), (0.35, 0.77), (0.50, 0.77), (0.38, 1.0), (0.73, 0.68), (0.57, 0.68), (0.71, 0.50)]
        let mx = p.map { $0.0 }.reduce(0, +) / Double(p.count), my = p.map { $0.1 }.reduce(0, +) / Double(p.count)
        p = p.map { (mx + ($0.0 - mx) * (1 + grow), my + ($0.1 - my) * (1 + grow)) }
        var inside = false
        var j = p.count - 1
        for i in 0..<p.count {
            let (xi, yi) = p[i], (xj, yj) = p[j]
            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Solid bolt; brighter with a dotted glow when it flashes. The space around it stays clear.
    private static func bolt(_ k: MarkCtx, flash: Bool) -> Mark? {
        if boltIn(k.x, k.y, grow: 0) { return ("#", flash ? 2 : 1) }
        if boltIn(k.x, k.y, grow: 0.3) { return flash ? (".", 1) : (" ", 0) }
        return nil
    }

    /// Stacked dashed lines inside an oval, fading at the ends; rows drift in opposite directions.
    private static func fog(_ k: MarkCtx) -> Mark? {
        let yc = 0.52, hy = 0.34
        guard abs(k.y - yc) <= hy else { return nil }
        let hw = 0.46 * max(0, 1 - pow((k.y - yc) / hy, 2)).squareRoot()
        let dir = k.r % 2 == 1 ? 1 : -1
        let sx = 0.5 + 0.06 * Double(dir) * (tri(k.tick, 6) - 0.5)
        guard abs(k.x - sx) <= hw else { return nil }
        if pixelHash(SceneArt.fdiv(k.c - dir * k.tick, 5), k.r, 9) % 7 == 0 { return nil }
        if abs(k.x - sx) > hw * 0.82 { return (".", 0) }
        let near = k.r % 2 == 0
        return (near ? "=" : "-", near ? 1 : 0)
    }

    /// Mixed flakes falling with a little sway over a bumpy dotted ground.
    private static func snow(_ k: MarkCtx) -> Mark? {
        let gy = 0.9 - 0.025 * sin(k.x * 12) - 0.02 * sin(k.x * 5 + 1)
        if abs(k.y - gy) < k.dy * 0.55 { return (pixelHash(k.c, 0, 3) % 5 == 0 ? "_" : ".", 1) }
        if k.y > gy || k.y < 0.06 { return nil }
        let sway = pmod(SceneArt.fdiv(k.r + k.tick, 3), 2)
        switch pixelHash(k.c - sway, k.r - k.tick, 23) % 40 {
        case 0: return ("*", 2)
        case 1, 2: return ("x", 1)
        case 3: return ("+", 1)
        case 4, 5: return (".", 0)
        default: return nil
        }
    }
}

enum AsciiComposer {
    /// Terminal draws everything with the four shade blocks, kept delicate:
    /// █ only for the sun's core and the bolt · ▓ the sun's rim, moon, bright stars and flakes ·
    /// ▒ outlines, rays, rain, near fog · ░ fills, tips, far rain, faint fog, horizon dots.
    static func block(_ m: Mark) -> Character {
        switch m.ch {
        case "O", "#": return "█"                                   // sun core, lightning
        case ".", "'", "_", ",", "-": return "░"                    // fills, tips, faint marks
        case "*": return "▓"
        case "x", "+": return m.tone == 2 ? "▓" : (m.tone == 1 ? "▒" : "░")
        case "=": return m.tone == 0 ? "░" : "▒"                     // outlines, near fog
        case "|", "/", "\\": return m.tone == 0 ? "░" : "▒"          // rays, rain
        default: return m.tone == 2 ? "▓" : (m.tone == 1 ? "▒" : "░")
        }
    }

    /// Draws the weather picture, as large as fits, between rows `top` and `bottom`.
    static func compose(cols: Int, rows: Int, cellRatio: Double, weather: WeatherSnapshot?,
                        tick: Int, top: Int, bottom: Int, unicode: Bool) -> AsciiGrid {
        var g = AsciiGrid(cols: cols, rows: rows)
        let availW = cols - 2, availH = bottom - top + 1
        guard availW >= 4, availH >= 3 else { return g }
        var ir = availH
        var ic = Int((Double(ir) * cellRatio).rounded())       // visually square
        if ic > availW { ic = availW; ir = Int((Double(ic) / cellRatio).rounded()) }
        let x0 = (cols - ic) / 2, y0 = top + (availH - ir) / 2
        let cond = weather?.condition ?? .clear
        let day = weather?.isDay ?? true
        let rays = [WeatherMarks.traceRays(0.5, 0.5, 0.18, tick: tick, ic: ic, ir: ir),
                    WeatherMarks.traceRays(0.32, 0.34, 0.12, tick: tick, ic: ic, ir: ir)]
        for r in 0..<ir {
            for c in 0..<ic {
                let k = MarkCtx(c: x0 + c, r: y0 + r, lc: c, lr: r,
                                x: (Double(c) + 0.5) / Double(ic), y: (Double(r) + 0.5) / Double(ir),
                                dx: 1 / Double(ic), dy: 1 / Double(ir), tick: tick, terminal: unicode)
                if let m = WeatherMarks.mark(k, cond, day: day, rays: rays), m.ch != " " {
                    g.put(x0 + c, y0 + r, unicode ? block(m) : m.ch, m.tone)
                }
            }
        }
        return g
    }
}

/// Time top-left, temperature top-right, place along the bottom — as normal-size text over the grid.
struct CharLabels: View {
    let time: String
    let temp: String
    let place: String
    let terminal: Bool
    let fullColor: Bool
    let tick: Int
    let size: CGFloat
    let inset: CGFloat

    var body: some View {
        let primary: Color = !fullColor ? .white : Color(hex: terminal ? Look.terminalGreen : Look.typewriterInk)
        let secondary: Color = !fullColor ? .white.opacity(0.8)
            : (terminal ? Color(hex: Look.terminalDim) : Color(hex: Look.typewriterInk).opacity(0.6))
        VStack(spacing: 0) {
            HStack {
                Text(terminal ? "> " + time + (pmod(tick, 2) == 0 ? "█" : "") : time).foregroundStyle(primary)
                Spacer(minLength: 4)
                Text(temp).foregroundStyle(primary)
            }
            Spacer(minLength: 0)
            Text(place.uppercased()).foregroundStyle(secondary)
        }
        .font(.system(size: size, weight: terminal ? .semibold : .regular, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(inset)
    }
}

/// Draws an AsciiGrid in a monospaced font with three tones.
struct CharGridView: View {
    let grid: AsciiGrid
    let cell: CGSize
    let terminal: Bool
    let fullColor: Bool

    var body: some View {
        Canvas { ctx, size in
            if fullColor {
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(hex: terminal ? Look.terminalBlack : Look.typewriterPaper)))
            }
            let regular = Font.system(size: cell.width / 0.6, weight: .regular, design: .monospaced)
            let bold = Font.system(size: cell.width / 0.6, weight: .bold, design: .monospaced)
            let tones: [UInt32] = terminal ? [Look.termLo, Look.termMid, Look.termHi] : [Look.typeLo, Look.typeMid, Look.typeHi]
            let ox = ((size.width - CGFloat(grid.cols) * cell.width) / 2).rounded(.down)
            let oy = ((size.height - CGFloat(grid.rows) * cell.height) / 2).rounded(.down)
            var cache: [String: GraphicsContext.ResolvedText] = [:]
            for r in 0..<grid.rows {
                for c in 0..<grid.cols {
                    let v = grid[c, r]
                    guard v.ch != " " else { continue }
                    let key = "\(v.ch)\(v.tone)"
                    let resolved: GraphicsContext.ResolvedText
                    if let hit = cache[key] { resolved = hit } else {
                        let tone = max(0, min(2, v.tone))
                        let color: Color = fullColor ? Color(hex: tones[tone]) : .white.opacity([0.45, 0.8, 1][tone])
                        resolved = ctx.resolve(Text(String(v.ch)).font(tone == 2 ? bold : regular).foregroundColor(color))
                        cache[key] = resolved
                    }
                    ctx.draw(resolved, at: CGPoint(x: ox + (CGFloat(c) + 0.5) * cell.width,
                                                   y: oy + (CGFloat(r) + 0.5) * cell.height), anchor: .center)
                }
            }
        }
    }
}
