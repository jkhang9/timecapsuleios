//  PixelWindow.swift
//  SHARED FILE — add to BOTH the app target and the widget extension target.
//
//  A cozy pixel-art window: options, pixel buffer, tiny font, window + scene art,
//  sill decorations, patterned wallpapers, palettes, and the SwiftUI views.
//  "tick" is the animation frame (minutes of the day in the widget, faster in the app).

import SwiftUI

// MARK: - Style options (chosen in the app, saved to the shared App Group)

protocol PixelOption: CaseIterable, Hashable, Codable, Identifiable where AllCases == [Self] {
    static var titles: [Self: String] { get }
}
extension PixelOption {
    var title: String { Self.titles[self] ?? "" }
    var id: Self { self }
}


enum WindowMaterial: String, PixelOption {
    case wood, painted, stone, brick, metal
    static let titles: [WindowMaterial: String] = [
        .wood: "Honey Oak", .painted: "Cottage White", .stone: "Mossy Stone",
        .brick: "Terracotta Brick", .metal: "Seafoam Metal",
    ]
}

enum WindowShape: String, PixelOption {
    case rectangle, arch, gothic, round
    static let titles: [WindowShape: String] = [
        .rectangle: "Rectangle", .arch: "Round Arch", .gothic: "Gothic Arch", .round: "Porthole",
    ]
}

enum WindowPanes: String, PixelOption {
    case single, split, cross, grid
    static let titles: [WindowPanes: String] = [
        .single: "Single", .split: "Split", .cross: "Cross", .grid: "Six Panes",
    ]
}

enum FrameWeight: String, PixelOption {
    case thin, medium, thick
    static let titles: [FrameWeight: String] = [
        .thin: "Thin", .medium: "Medium", .thick: "Thick",
    ]
    var pixels: Int {
        switch self { case .thin: 2; case .medium: 3; case .thick: 4 }
    }
}

enum Wallpaper: String, PixelOption {
    case sage, gingham, terracotta, navy, charcoal, cabin, midnight
    static let titles: [Wallpaper: String] = [
        .sage: "Sage Pinstripe", .gingham: "Mint Gingham", .terracotta: "Terracotta Tile",
        .navy: "Navy Diamond", .charcoal: "Charcoal Dot", .cabin: "Cozy Cabin", .midnight: "Starry Night",
    ]

    /// wall, pattern, accent, window outline, text, dim text
    var colors: (wall: UInt32, line: UInt32, accent: UInt32, outline: UInt32, text: UInt32, dim: UInt32) {
        switch self {
        case .sage: (0xC9D8C0, 0xB5C8AA, 0xA3B896, 0x5E7356, 0x2F4029, 0x51684A)
        case .gingham: (0xDDF3E6, 0xC6EAD5, 0xA8DDBF, 0x6FA88A, 0x2E6049, 0x4F8A6E)
        case .terracotta: (0xD9845F, 0xF0D5BF, 0xC5714D, 0x7A3A22, 0xFFF3E6, 0xF6D4BE)
        case .navy: (0x2C3E5C, 0x34496B, 0xE2B866, 0x111A2B, 0xF4EBD8, 0xC9BFA8)
        case .charcoal: (0x3A3D42, 0x565B62, 0x4A4E54, 0x1C1E21, 0xF0EEE8, 0xB9B6AE)
        case .cabin: (0x9A6640, 0x6E4428, 0x5C3820, 0x3E2414, 0xFFF0D6, 0xEBCFA5)
        case .midnight: (0x272C55, 0x4A5190, 0xFFF3B0, 0x14172F, 0xF3EEFF, 0xB9B3E6)
        }
    }

    /// The wallpaper's repeating pattern.
    func ink(_ x: Int, _ y: Int) -> Ink {
        switch self {
        case .sage: // vertical pinstripes
            return x % 5 == 0 ? .wallLine : .wall
        case .gingham:
            let a = (x / 4) % 2 == 0, b = (y / 4) % 2 == 0
            return a && b ? .wallAccent : (a || b ? .wallLine : .wall)
        case .terracotta: // tiles with light grout, a few tiles a shade darker
            if x % 8 == 0 || y % 8 == 0 { return .wallLine }
            return pixelHash(x / 8, y / 8, 23) % 3 == 0 ? .wallAccent : .wall
        case .navy: // small gold diamonds
            let lx = pmod(x + (y / 8 % 2) * 4, 8), ly = y % 8
            if abs(lx - 4) + abs(ly - 4) <= 1 { return .wallAccent }
            return (lx + ly) % 8 == 0 ? .wallLine : .wall
        case .charcoal: // staggered dots
            let lx = pmod(x + (y / 6 % 2) * 3, 6), ly = y % 6
            return lx == 3 && ly == 3 ? .wallLine : .wall
        case .cabin: // wooden planks with knots
            if y % 7 == 6 || (x + (y / 7) * 13) % 23 == 0 { return .wallLine }
            return pixelHash(x / 2, y / 2, 21) % 53 == 0 ? .wallAccent : .wall
        case .midnight: // starry
            let h = pixelHash(x, y, 22) % 97
            return h == 0 ? .wallAccent : (h < 3 ? .wallLine : .wall)
        }
    }
}

enum SillDecor: String, PixelOption {
    case none, flowerBox, cat, plants
    static let titles: [SillDecor: String] = [
        .none: "Nothing", .flowerBox: "Window Box", .cat: "Sleepy Cat", .plants: "Potted Plants",
    ]
}

struct WindowStyle: Hashable, Codable {
    var aesthetic: Aesthetic = .pixel
    var material: WindowMaterial = .wood
    var shape: WindowShape = .arch
    var panes: WindowPanes = .cross
    var frame: FrameWeight = .medium
    var wallpaper: Wallpaper = .sage
    var sill: SillDecor = .plants
}

// MARK: - Shared storage (app writes, widget reads)

enum StyleStore {
    /// Must match the App Group added to BOTH targets under Signing & Capabilities.
    static let appGroup = "group.com.example.pixelwindow"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var style: WindowStyle {
        get {
            guard let data = defaults.data(forKey: "style"),
                  let saved = try? JSONDecoder().decode(WindowStyle.self, from: data) else { return WindowStyle() }
            return saved
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "style") }
    }

    /// Optional "City, ST" override; empty means use the current location.
    static var placeName: String {
        get { defaults.string(forKey: "placeName") ?? "" }
        set { defaults.set(newValue, forKey: "placeName") }
    }
}

// MARK: - Weather model

enum SkyCondition: String, CaseIterable, Hashable {
    case clear, partlyCloudy, cloudy, fog, rain, snow, storm

    /// WMO weather codes as used by Open-Meteo
    init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .storm
        default: self = .cloudy
        }
    }
}

struct WeatherSnapshot: Hashable {
    var condition: SkyCondition
    var isDay: Bool
    var temperature: Int? = nil       // whole degrees in the user's unit
    static let sample = WeatherSnapshot(condition: .partlyCloudy, isDay: true, temperature: 72)
}

// MARK: - Pixel buffer

enum Ink: UInt8 {
    case clear
    case frameDark, frame, frameLight, mortar, moss, outline
    case sky, skyTop, skyFlash, glint, sun, cloud, cloudMid, cloudShade, star, starDim
    case rain, rainFar, snow, bolt, glassDrop, frost, fogWisp
    case hillFar, hillNear, tree, bird, firefly, butterfly
    case flowerA, flowerB, flowerC, flowerCenter, leaf, leafDark, box, boxLight, boxShade   // outside
    case plantLeaf, plantLeafDark, plantBloom, pot, potShade                                 // indoors
    case catBody, catBelly, catEye, catNose, snowCap
    case text, textDim, wall, wallLine, wallAccent
}

struct PixelBuffer {
    let width: Int
    let height: Int
    private(set) var pixels: [Ink]

    init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        pixels = Array(repeating: .clear, count: self.width * self.height)
    }

    subscript(x: Int, y: Int) -> Ink {
        get { (x >= 0 && y >= 0 && x < width && y < height) ? pixels[y * width + x] : .clear }
        set { if x >= 0 && y >= 0 && x < width && y < height { pixels[y * width + x] = newValue } }
    }

    /// Stamps a small sprite; characters not in the map are transparent.
    mutating func stamp(_ sprite: [String], _ map: [Character: Ink], x: Int, y: Int) {
        for (r, line) in sprite.enumerated() {
            for (c, ch) in line.enumerated() { if let ink = map[ch] { self[x + c, y + r] = ink } }
        }
    }
}

/// Deterministic noise so textures never flicker between refreshes.
@inline(__always) func pixelHash(_ x: Int, _ y: Int, _ seed: Int = 0) -> Int {
    var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Int(h & 0x7FFF_FFFF)
}

/// Modulo that never goes negative.
@inline(__always) func pmod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

// MARK: - Pixel font (tiny 3×5 for the corner labels)

enum PixelFont {
    static let height = 5

    static let glyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"], "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
        "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
        "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
        "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
        "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
        ":": [".", "#", ".", "#", "."], ".": [".", ".", ".", ".", "#"],
        ",": [".", ".", ".", "#", "#"], "'": ["#", "#", ".", ".", "."],
        "-": ["...", "...", "###", "...", "..."], "/": ["..#", "..#", ".#.", "#..", "#.."],
        "°": ["##", "##", "..", "..", ".."], " ": ["..", "..", "..", "..", ".."],
    ]

    static func normalize(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil).uppercased()
    }

    static func glyph(_ c: Character) -> [String] { glyphs[c] ?? glyphs[" "]! }

    static func width(_ text: String) -> Int {
        let chars = Array(normalize(text))
        guard !chars.isEmpty else { return 0 }
        return chars.reduce(0) { $0 + glyph($1)[0].count } + chars.count - 1
    }

    static func fit(_ text: String, maxWidth: Int) -> String {
        var s = normalize(text)
        while !s.isEmpty && width(s) > maxWidth { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func draw(_ text: String, into buf: inout PixelBuffer, x: Int, y: Int, ink: Ink) {
        var cx = x
        for ch in normalize(text) {
            let g = glyph(ch)
            for (row, line) in g.enumerated() {
                for (col, bit) in line.enumerated() where bit == "#" { buf[cx + col, y + row] = ink }
            }
            cx += g[0].count + 1
        }
    }
}

// MARK: - Window renderer

enum WindowRenderer {

    /// Draws a complete window (outline, frame, glass scene, sill, decor) inside the box.
    static func draw(into buf: inout PixelBuffer, x ox: Int, y oy: Int, width: Int, height: Int,
                     style: WindowStyle, weather: WeatherSnapshot?, tick: Int) {
        let hasSill = style.shape != .round
        let over = hasSill ? 1 : 0                 // sill overhang each side
        let sillH = hasSill ? 2 : 0
        let t = style.frame.pixels                 // frame thickness
        let m = t >= 3 ? 2 : 1                     // mullion thickness
        var fw = width - over * 2
        if (fw - m) % 2 != 0 { fw -= 1 }           // keeps centre mullions symmetric
        let fh = height - sillH
        guard fw >= t * 2 + 3, fh >= t * 2 + 3 else { return }
        let fx = ox + over

        // 1. Silhouette
        var inside = [Bool](repeating: false, count: fw * fh)
        for y in 0..<fh { for x in 0..<fw { inside[y * fw + x] = insideShape(style.shape, x, y, fw, fh) } }

        // 2. Distance from the outside edge (4-neighbour BFS) → frame vs. glass
        var dist = [Int](repeating: 0, count: fw * fh)
        var queue: [Int] = []
        for y in 0..<fh {
            for x in 0..<fw where inside[y * fw + x] {
                let edge = x == 0 || y == 0 || x == fw - 1 || y == fh - 1
                    || !inside[y * fw + x - 1] || !inside[y * fw + x + 1]
                    || !inside[(y - 1) * fw + x] || !inside[(y + 1) * fw + x]
                if edge { dist[y * fw + x] = 1; queue.append(y * fw + x) }
            }
        }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % fw, y = i / fw
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < fw, ny < fh else { continue }
                let j = ny * fw + nx
                if inside[j] && dist[j] == 0 { dist[j] = dist[i] + 1; queue.append(j) }
            }
        }

        // 3. Glass bounding box
        var minX = fw, maxX = -1, minY = fh, maxY = -1
        for i in 0..<(fw * fh) where dist[i] > t {
            let x = i % fw, y = i / fw
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        let hasGlass = maxX >= minX
        let bw = maxX - minX + 1, bh = maxY - minY + 1

        func isOut(_ x: Int, _ y: Int) -> Bool { x < 0 || y < 0 || x >= fw || y >= fh || !inside[y * fw + x] }
        func isGlassArea(_ x: Int, _ y: Int) -> Bool { !isOut(x, y) && dist[y * fw + x] > t }

        func isMullion(_ x: Int, _ y: Int) -> Bool {
            guard hasGlass else { return false }
            let u = x - minX, v = y - minY
            let vc = (bw - m) / 2, hc = (bh - m) / 2
            let vBar = u >= vc && u < vc + m
            let hBar = v >= hc && v < hc + m
            switch style.panes {
            case .single: return false
            case .split: return vBar
            case .cross: return vBar || hBar
            case .grid:
                let a = Int((Double(bw - m) / 3).rounded()), b = bw - a - m
                return (u >= a && u < a + m) || (u >= b && u < b + m) || hBar
            }
        }
        func isPane(_ x: Int, _ y: Int) -> Bool { isGlassArea(x, y) && !isMullion(x, y) }

        // 4. Paint frame, glass scene and mullions
        for y in 0..<fh {
            for x in 0..<fw {
                let i = y * fw + x
                guard inside[i] else { continue }
                let gx = fx + x, gy = oy + y
                let d = dist[i]

                if d > t {
                    let u = x - minX, v = y - minY
                    if isMullion(x, y) {
                        if isPane(x + 1, y) || isPane(x, y + 1) { buf[gx, gy] = .frameDark }
                        else { buf[gx, gy] = style.material == .wood || style.material == .painted
                                ? texture(style.material, gx, gy, d: 0, t: t) : .frame }
                    } else {
                        buf[gx, gy] = SceneArt.ink(u: u, v: v, w: bw, h: bh, weather: weather, tick: tick,
                                                   windowBox: style.sill == .flowerBox && style.shape != .round)
                    }
                    continue
                }

                // Bevels: light from the top-left
                if d == 1 {
                    if isOut(x, y - 1) || isOut(x - 1, y) { buf[gx, gy] = .frameLight; continue }
                    if isOut(x, y + 1) || isOut(x + 1, y) { buf[gx, gy] = .frameDark; continue }
                }
                if d == t {
                    if isGlassArea(x, y + 1) || isGlassArea(x + 1, y) { buf[gx, gy] = .frameDark; continue }
                    if isGlassArea(x, y - 1) || isGlassArea(x - 1, y) { buf[gx, gy] = .frameLight; continue }
                }
                buf[gx, gy] = texture(style.material, gx, gy, d: d, t: t)
            }
        }

        // 5. Sill (we're indoors looking out, so the sill stays dry)
        let sy = oy + fh
        if hasSill {
            for sx in 0..<(fw + over * 2) {
                buf[ox + sx, sy] = .frameLight
                buf[ox + sx, sy + 1] = .frameDark
            }
        }

        // 6. Dark outline around the whole window — the cozy-game look
        func isWin(_ gx: Int, _ gy: Int) -> Bool {
            let x = gx - fx, y = gy - oy
            if x >= 0 && y >= 0 && x < fw && y < fh { return inside[y * fw + x] }
            return hasSill && gy >= sy && gy < sy + sillH && gx >= ox && gx < ox + fw + over * 2
        }
        for gy in (oy - 1)...(sy + sillH) {
            for gx in (ox - 1)...(ox + fw + over * 2) where !isWin(gx, gy) {
                if isWin(gx - 1, gy) || isWin(gx + 1, gy) || isWin(gx, gy - 1) || isWin(gx, gy + 1) {
                    buf[gx, gy] = .outline
                }
            }
        }

        // 7. Indoor sill decorations (the window box is outside, drawn with the scene)
        if hasSill && fw >= 22 && fh >= 20 {
            drawDecor(style.sill, into: &buf, fx: fx, fw: fw, sy: sy, weather: weather, tick: tick)
        }
    }

    // MARK: Decor

    static func drawDecor(_ decor: SillDecor, into buf: inout PixelBuffer, fx: Int, fw: Int, sy: Int,
                          weather: WeatherSnapshot?, tick: Int) {
        let day = weather?.isDay ?? true
        let cond = weather?.condition ?? .clear
        let fair = cond == .clear || cond == .partlyCloudy

        switch decor {
        case .none, .flowerBox:
            break   // the window box sits outside the glass

        case .cat:
            // Naps through bad weather and nights; peeks out on nice days; startled by lightning.
            let flash = cond == .storm && pmod(tick, 4) == 0
            let awake = (day && fair && pmod(tick, 3) == 0) || flash
            let sprite = [
                ".#.....#.",
                ".##...##.",
                ".#######.",
                awake ? "##o###o##" : "#--###--#",
                awake ? "##o#n#o##" : "####n####",
                ".#######.",
                "##sssss##",
                "##sssss##",
            ]
            let cx = fx + fw / 4 - 4, cy = sy - 8
            buf.stamp(sprite, ["#": .catBody, "s": .catBelly, "o": .catEye, "-": .catEye, "n": .catNose], x: cx, y: cy)
            let swish = fair && day
            let tail = (swish && pmod(tick, 2) == 0) ? [(9, 6), (10, 5), (10, 4), (11, 3)] : [(9, 7), (10, 7), (11, 6), (12, 6)]
            for (dx, dy) in tail { buf[cx + dx, cy + dy] = .catBody }

        case .plants:
            let leafy = [".l.l.", "lLlLl", ".lLl.", "..l..", "ppppp", ".PPP."]
            let cactus = ["..f..", "..c..", "c.c..", "ccc.c", "..ccc", "..c..", ".ppp.", ".PPP."]
            let map: [Character: Ink] = ["l": .plantLeaf, "L": .plantLeafDark, "c": .plantLeafDark,
                                         "f": .plantBloom, "p": .pot, "P": .potShade]
            buf.stamp(leafy, map, x: fx + 2, y: sy - 6)
            buf.stamp(cactus, map, x: fx + fw - 7, y: sy - 8)
        }
    }

    // MARK: Shapes & textures

    static func insideShape(_ shape: WindowShape, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Bool {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        let W = Double(w), H = Double(h)
        switch shape {
        case .rectangle:
            return true
        case .round:
            let dx = (px - W / 2) / (W / 2), dy = (py - H / 2) / (H / 2)
            return dx * dx + dy * dy <= 1
        case .arch:
            let ry = min(W / 2, H / 2)
            guard py < ry else { return true }
            let dx = (px - W / 2) / (W / 2), dy = (py - ry) / ry
            return dx * dx + dy * dy <= 1
        case .gothic:
            let r = W * 0.8
            let natural = (r * r - (r - W / 2) * (r - W / 2)).squareRoot()
            let rise = min(natural, H * 0.6)
            guard py < rise else { return true }
            let ny = natural - (rise - py) * natural / rise
            let a = (px - r) * (px - r) + (ny - natural) * (ny - natural)
            let b = (px - (W - r)) * (px - (W - r)) + (ny - natural) * (ny - natural)
            return a <= r * r && b <= r * r
        }
    }

    static func texture(_ material: WindowMaterial, _ x: Int, _ y: Int, d: Int, t: Int) -> Ink {
        switch material {
        case .wood:
            if pixelHash(x / 3, y, 1) % 5 == 0 { return .frameDark }
            if pixelHash(x / 4, y, 2) % 9 == 0 { return .frameLight }
            return .frame
        case .painted:
            return pixelHash(x / 4, y, 3) % 11 == 0 ? .frameDark : .frame
        case .stone:
            let row = y / 3
            if y % 3 == 2 { return .mortar }
            if pixelHash(x, y, 14) % 9 == 0 { return .moss }
            let shift = pixelHash(row, 0, 4) % 4
            if (x + shift) % 5 == 4 { return .mortar }
            switch pixelHash((x + shift) / 5, row, 5) % 4 {
            case 0: return .frameDark
            case 1: return .frameLight
            default: return .frame
            }
        case .brick:
            let row = y / 3
            if y % 3 == 2 { return .mortar }
            let shift = row % 2 == 0 ? 0 : 3
            if (x + shift) % 6 == 5 { return .mortar }
            return pixelHash((x + shift) / 6, row, 6) % 4 == 0 ? .frameDark : .frame
        case .metal:
            if t >= 3 && d == 2 {
                if (x + y) % 5 == 0 { return .frameLight }   // rivet
                if (x + y) % 5 == 1 { return .frameDark }    // rivet shadow
            }
            return .frame
        }
    }
}

// MARK: - The view through the glass

enum SceneArt {
    /// Floor division (rounds toward −∞, unlike `/`).
    @inline(__always) static func fdiv(_ a: Int, _ n: Int) -> Int { (a - pmod(a, n)) / n }

    /// Layers, front to back: glass (drops, frost) → lightning → near rain/snow → window box →
    /// fog banks → far rain/snow → clouds → birds → sun/moon/stars → fireflies → haze and splashes →
    /// trees → hills → sky. Everything that moves sideways drifts to the right, like the wind.
    static func ink(u: Int, v: Int, w: Int, h: Int, weather: WeatherSnapshot?, tick: Int, windowBox: Bool) -> Ink {
        let W = Double(w), H = Double(h)
        let px = Double(u) + 0.5, py = Double(v) + 0.5
        let cond = weather?.condition ?? .clear
        let day = weather?.isDay ?? true
        let fair = cond == .clear || cond == .partlyCloudy
        let rainy = cond == .rain || cond == .storm
        let storm = cond == .storm
        let flash = storm && pmod(tick, 4) == 0
        let unit = max(2.0, min(W, H) / 4.5)
        let farTop = H * 0.70 + sin(px * 0.21 + 1.0) * H * 0.04
        let nearTop = H * 0.83 + sin(px * 0.33 + 2.0) * H * 0.03

        func disk(_ cx: Double, _ cy: Double, _ r: Double) -> Bool {
            let dx = px - cx, dy = py - cy
            return dx * dx + dy * dy <= r * r
        }

        // 1. On the glass itself: water beads sliding down in rain, frost creeping in from the corners in snow
        if rainy {
            for i in 0..<max(2, w / 7) {
                let dx = pixelHash(i, 0, 81) % w
                let speed = 1 + pixelHash(i, 1, 81) % 2
                let dy = pmod(pixelHash(i, 2, 81) + tick * speed, h + 8) - 4
                if u == dx {
                    if v == dy { return .glassDrop }
                    if v == dy + 1 { return .cloudShade }                          // bead's shadow side
                    if speed == 2 && v < dy && v >= dy - 2 { return .rainFar }   // wet trail behind a fast bead
                }
            }
        }
        if cond == .snow {
            let c = min(u, w - 1 - u) + min(v, h - 1 - v)
            if c < 3 || (c < 6 && pixelHash(u, v, 91) % 3 == 0) { return .frost }
        }

        // 2. Lightning: a jagged bolt with one branch
        if flash {
            let seed = tick / 4
            let y0 = Int(H * 0.34), y1 = Int(farTop)
            if v >= y0 && v <= y1 {
                func boltX(_ row: Int) -> Int {
                    var x = Int(W * 0.25) + pixelHash(seed, 1, 61) % max(1, Int(W * 0.5))
                    for yy in y0..<max(y0, row) {
                        let r = pixelHash(yy, seed, 62) % 4
                        x += r == 0 ? -1 : (r == 1 ? 1 : 0)
                    }
                    return x
                }
                if u == boltX(v) { return .bolt }
                let by = y0 + (y1 - y0) / 3, k = v - by
                let dir = pixelHash(seed, 2, 61) % 2 == 0 ? -1 : 1
                if k >= 1 && k <= 4 && u == boltX(by) + dir * k { return .bolt }
            }
        }

        // 3. Near layer of rain / snow
        func rainLayer(fall: Int, shear: Int, period: Int, len: Int, density: Int, seed: Int) -> Bool {
            let p = v - tick * fall
            let x = u - fdiv(v, shear)                 // streaks slant down-right, with the wind
            let off = pixelHash(x, seed, 53) % period
            return pmod(p + off, period) < len && pixelHash(x, fdiv(p + off, period), seed) % density == 0
        }
        let deckFrac = storm ? 0.36 : 0.30
        let deckEdge = H * deckFrac + sin(px * 0.35 - Double(tick) * 0.12) * 1.2 + sin(px * 0.9 + 1.7) * 0.7
        let belowDeck = py >= deckEdge
        if rainy && belowDeck {
            let hit = storm ? rainLayer(fall: 7, shear: 3, period: 10, len: 5, density: 4, seed: 1)
                            : rainLayer(fall: 5, shear: 4, period: 12, len: 4, density: 6, seed: 1)
            if hit { return .rain }
        }
        let snowTop = Int(H * 0.28 + unit * 1.1 * 0.65) + 1
        if cond == .snow && v >= snowTop {
            let sway = Int((sin(Double(v) * 0.4 + Double(tick) * 0.3) * 1.2).rounded())
            if pixelHash(u - sway, v - tick, 8) % 13 == 0 { return .snow }
        }

        // 4. Window box on the outside ledge — it lives in the weather
        if windowBox && w >= 20 && h >= 16 {
            let boxW = Int(W * 0.72), bx0 = (w - boxW) / 2, i = u - bx0
            let inBox = i >= 0 && i < boxW
            if inBox {
                if v == h - 3 { return .boxLight }
                if v == h - 2 { return .box }
                if v == h - 1 { return .boxShade }
            }
            if cond == .snow {
                // Winter: no blooms — a snow mound with bare sprigs poking through
                if inBox && v == h - 4 { return .snow }
                if inBox && v == h - 5 && pixelHash(i, 0, 42) % 3 != 0 { return .snow }
                if inBox && pmod(i, 4) == 2 {
                    if v == h - 7 && pixelHash(i, 0, 43) % 2 == 0 { return .snow }
                    if v == h - 6 { return .leafDark }
                }
            } else {
                if inBox && v == h - 4 { return pixelHash(i, 0, 41) % 3 == 0 ? .leafDark : .leaf }
                let droop = rainy ? 1 : 0              // rain bows the flowers down
                var k = 0
                for fi in stride(from: 1, to: boxW - 1, by: 3) {
                    let tall = k % 2 == 0 && !rainy
                    let sway = fair && pmod(tick + fi, 5) == 0 ? 1 : 0
                    let cx = bx0 + fi + sway, cy = h - (tall ? 7 : 6) + droop
                    if tall && u == bx0 + fi && v == h - 5 { return .leaf }
                    let du = u - cx, dv = v - cy
                    let petal: Ink = [.flowerA, .flowerB, .flowerC][k % 3]
                    if !day {
                        if du == 0 && dv == 0 { return petal }          // closed buds at night
                    } else {
                        if du == 0 && dv == 0 { return .flowerCenter }
                        if abs(du) + abs(dv) == 1 {
                            return rainy && pixelHash(u, v, tick) % 5 == 0 ? .rain : petal   // drops on petals
                        }
                    }
                    k += 1
                }
                if day && fair && h >= 24 {           // a butterfly on nice days
                    let bx = bx0 + pmod(tick * 3, boxW), by = h - 11 - pmod(tick, 2)
                    let shape = pmod(tick, 2) == 0 ? [(0, 0), (2, 0), (1, 1)] : [(1, 0), (1, 1)]
                    if shape.contains(where: { $0 == (u - bx, v - by) }) { return .butterfly }
                }
            }
        }

        // 5. Fog banks drifting low over the hills, soft-edged
        if cond == .fog {
            for i in 0..<3 {
                let cy = H * (0.6 + 0.12 * Double(i)) + sin(px * 0.08 + Double(i) * 2 - Double(tick) * 0.05)
                let dy = abs(py - cy)
                let open = pixelHash(fdiv(u - tick * (i + 1), 7), i, 71) % 4 != 0
                if open && (dy < 1 || (dy < 2 && (u + v) % 2 == 0)) { return .fogWisp }
            }
        }

        // 6. Far layer of rain / snow (fainter, slower)
        if rainy && belowDeck {
            let hit = storm ? rainLayer(fall: 5, shear: 3, period: 8, len: 3, density: 5, seed: 2)
                            : rainLayer(fall: 3, shear: 4, period: 9, len: 3, density: 8, seed: 2)
            if hit { return .rainFar }
        }
        if cond == .snow && v >= snowTop && pixelHash(u, v - tick / 2, 88) % 19 == 0 { return .rainFar }

        // 7. Clouds — an overcast deck for rain and storms, puffy clouds otherwise
        if rainy && !belowDeck {
            if py > deckEdge - 1.6 { return .cloudShade }       // darker underside
            for i in 0..<5 {
                let lx = Double(pmod(pixelHash(i, 0, 52) % w + tick / 2, w + 8) - 4) + 0.5
                let ly = H * deckFrac * (0.25 + Double(pixelHash(i, 1, 52) % 50) / 100)
                let lr = 2 + Double(pixelHash(i, 2, 52) % 3)
                if disk(lx, ly, lr) { return (py < ly && px < lx) ? .cloud : .cloudMid }   // soft highlight
            }
            return .cloudMid
        }
        func cloud(_ baseX: Double, _ cy: Double, _ s: Double, speed: Int) -> Ink? {
            let span = W + s * 3.4
            let cx = (baseX + s * 1.7 + Double(tick * speed)).truncatingRemainder(dividingBy: span) - s * 1.7
            let body = disk(cx - s * 0.9, cy + s * 0.15, s * 0.7) || disk(cx, cy - s * 0.2, s)
                || disk(cx + s * 0.9, cy + s * 0.15, s * 0.7)
            guard body && py <= cy + s * 0.65 else { return nil }
            return py > cy + s * 0.3 ? .cloudShade : .cloud
        }
        switch cond {
        case .partlyCloudy:
            if let c = cloud(W * 0.38, H * 0.5, unit, speed: 1) { return c }
        case .cloudy:
            if let c = cloud(W * 0.3, H * 0.3, unit * 0.9, speed: 1) { return c }
            if let c = cloud(W * 0.7, H * 0.52, unit, speed: 1) { return c }
        case .snow:
            if let c = cloud(W * 0.5, H * 0.28, unit * 1.1, speed: 0) { return c }
        default:
            break
        }

        // 8. Two little birds on nice days
        if day && fair && w >= 14 {
            for i in 0..<2 {
                let bx = pmod(tick * 2 + i * 9 + 3, w + 8) - 4
                let by = Int(H * 0.16) + i * 3
                let shape = pmod(tick + i, 2) == 0 ? [(0, 0), (2, 0), (1, 1)] : [(0, 1), (1, 0), (2, 1)]
                if shape.contains(where: { $0 == (u - bx, v - by) }) { return .bird }
            }
        }

        // 9. Sun with twinkling rays, or a crescent moon and stars; in fog only a pale disc shows through
        let sx = W * 0.62, sy = H * 0.3, r = unit * 0.72
        if fair {
            let dx = px - sx, dy = py - sy
            let d = (dx * dx + dy * dy).squareRoot()
            if day {
                if d <= r { return .sun }
                if d > r + 1 && d < r + 2.6 && py < farTop {
                    let step = Double.pi / 4
                    let a = atan2(dy, dx) - (pmod(tick, 2) == 0 ? 0 : step / 2)
                    if abs(a - (a / step).rounded() * step) < 0.22 { return .sun }
                }
            } else {
                if d <= r && !disk(sx + r * 0.55, sy - r * 0.35, r * 0.85) { return .sun }
                if py < farTop - 1 && pixelHash(u, v, 9) % 23 == 0 {
                    return pixelHash(u, v, tick) % 3 == 0 ? .starDim : .star
                }
            }
        } else if cond == .fog && disk(sx, sy, r) {
            return .sun
        }

        // 10. Fireflies over the hills on fair nights
        if !day && fair && py >= farTop {
            for i in 0..<3 {
                let fx = pixelHash(i, tick, 31) % max(1, w)
                let fy = Int(H * 0.74) + pixelHash(i, tick, 32) % max(1, Int(H * 0.22))
                if u == fx && v == fy { return .firefly }
            }
        }

        // 11. Haze on the horizon in rain and fog; little splashes on the grass in rain
        if (rainy || cond == .fog) && abs(py - farTop) < 1.2 && (u + v) % 2 == 0 { return .fogWisp }
        if rainy && py >= nearTop && py < nearTop + 1 && pixelHash(u, tick, 95) % 6 == 0 { return .rain }

        // 12. Little round trees (crown, highlight, trunk; snow on top in winter)
        if H >= 18 {
            for c in (u - 2)...(u + 2) where pmod(c, 8) == 4 && pixelHash(c / 8, 0, 11) % 3 != 0 {
                let cx = Double(c) + 0.5
                let top = H * 0.70 + sin(cx * 0.21 + 1.0) * H * 0.04
                let cy = top - 2.2
                if disk(cx, cy, 2.1) {
                    if cond == .snow && py < cy - 0.6 { return .snow }
                    return (px < cx - 0.5 && py < cy - 0.5) ? .hillFar : .tree
                }
                if u == c && py >= cy + 1.5 && py < top + 1 { return .boxShade }
            }
        }

        // 13. Hills (their colours carry the weather: wet, foggy, snowy, night)
        if py >= nearTop { return .hillNear }
        if py >= farTop { return .hillFar }

        // 14. Sky: soft dithered gradient, a glint on the glass, and the lightning flash
        if flash { return .skyFlash }
        if u >= 1 && v >= 1 && u <= 4 && v <= 4 && (u + v == 3 || u + v == 5) { return .glint }
        if rainy || cond == .fog { return .sky }                           // overcast and fog are flat
        if py < H * 0.3 { return .skyTop }
        if py < H * 0.42 { return (u + v) % 2 == 0 ? .skyTop : .sky }
        return .sky
    }
}

// MARK: - Layouts
//
// A patterned wallpaper fills the widget, and the window takes the widget's own shape:
//      9:41 AM ··········· 89°
//           [  window  ]
//          AUSTIN, TX

enum SceneLayout { case lockRectangular, lockCircular, home, thumbnail }

enum SceneComposer {
    static func timeParts(_ date: Date) -> (String, String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm"
        let time = f.string(from: date)
        f.dateFormat = "a"
        return (time, f.string(from: date))
    }

    /// "9:41 AM"
    static func timeText(_ date: Date) -> String {
        let t = timeParts(date)
        return "\(t.0) \(t.1)"
    }

    /// "89°", or "--°" before the first fetch
    static func tempText(_ weather: WeatherSnapshot?) -> String {
        weather?.temperature.map { "\($0)°" } ?? "--°"
    }

    /// "CITY, ST" if it fits, else just "CITY", trimmed if needed.
    static func fitPlace(_ place: String, maxChars: Int) -> String {
        let p = place.uppercased()
        if p.count <= maxChars { return p }
        let city = String(p.split(separator: ",").first ?? "")
        return String(city.prefix(maxChars))
    }

    static func placeParts(_ place: String) -> (String, String) {
        let parts = place.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }

    /// Time top-left, temperature top-right, "CITY, ST" centred along the bottom.
    static func labels(_ buf: inout PixelBuffer, margin m: Int, time: String, temp: String, place: String) {
        let h = PixelFont.height
        func put(_ text: String, x: Int, y: Int, ink: Ink) {
            guard !text.isEmpty else { return }
            // Clear the wallpaper pattern behind the label so it stays crisp.
            for yy in (y - 1)...(y + h) {
                for xx in (x - 1)...(x + PixelFont.width(text)) where buf[xx, yy] != .clear { buf[xx, yy] = .wall }
            }
            PixelFont.draw(text, into: &buf, x: x, y: y, ink: ink)
        }
        let right = PixelFont.fit(temp, maxWidth: buf.width / 3)
        let rightW = PixelFont.width(right)
        put(right, x: buf.width - m - rightW, y: m, ink: .text)
        put(PixelFont.fit(time, maxWidth: buf.width - m * 2 - rightW - 3), x: m, y: m, ink: .text)
        var p = PixelFont.normalize(place)
        if PixelFont.width(p) > buf.width - m * 2 { p = String(p.split(separator: ",").first ?? "") }
        p = PixelFont.fit(p, maxWidth: buf.width - m * 2)
        put(p, x: (buf.width - PixelFont.width(p)) / 2, y: buf.height - m - h, ink: .textDim)
    }

    static func render(layout: SceneLayout, cols: Int, rows: Int, style: WindowStyle,
                       weather: WeatherSnapshot?, date: Date, place: String, tick: Int,
                       labels: Bool = true) -> PixelBuffer {
        var buf = PixelBuffer(width: cols, height: rows)
        guard cols >= 30, rows >= 30 else { return buf }
        let paper = style.wallpaper

        switch layout {
        case .thumbnail:
            // Just wallpaper and window — used for the option swatches in the app.
            for y in 0..<rows { for x in 0..<cols { buf[x, y] = paper.ink(x, y) } }
            WindowRenderer.draw(into: &buf, x: 3, y: 3, width: cols - 6, height: rows - 6,
                                style: style, weather: weather, tick: tick)

        case .lockCircular:
            // Wallpapered pixel disc with a square-proportioned window (no corners on a circle).
            let r = Double(min(cols, rows)) / 2
            for y in 0..<rows {
                for x in 0..<cols {
                    let dx = Double(x) + 0.5 - Double(cols) / 2, dy = Double(y) + 0.5 - Double(rows) / 2
                    if dx * dx + dy * dy <= r * r { buf[x, y] = paper.ink(x, y) }
                }
            }
            let ir = r - 3
            let side = style.shape == .round ? Int(2 * ir) : Int(2 * ir / 2.0.squareRoot())
            WindowRenderer.draw(into: &buf, x: (cols - side) / 2, y: (rows - side) / 2, width: side, height: side,
                                style: style, weather: weather, tick: tick)

        case .lockRectangular, .home:
            for y in 0..<rows { for x in 0..<cols { buf[x, y] = paper.ink(x, y) } }
            if layout == .lockRectangular {
                // Pixel-notched corners on the Lock Screen panel.
                for (x, y) in [(0, 0), (1, 0), (0, 1)] {
                    buf[x, y] = .clear; buf[cols - 1 - x, y] = .clear
                    buf[x, rows - 1 - y] = .clear; buf[cols - 1 - x, rows - 1 - y] = .clear
                }
            }
            // Labels in bands along the top and bottom; the window fills the space between
            // with the SAME aspect ratio as the widget (square → square, wide → wide).
            let home = layout == .home
            let m = home ? 5 : 2                       // home margin clears the rounded corners
            let band = m + PixelFont.height + (home ? 3 : 2)
            let boxW = cols - m * 2, boxH = rows - band * 2
            let aspect = Double(cols) / Double(rows)
            var winH = boxH
            var winW = Int(Double(boxH) * aspect)
            if winW > boxW { winW = boxW; winH = Int(Double(boxW) / aspect) }
            WindowRenderer.draw(into: &buf, x: (cols - winW) / 2, y: band + (boxH - winH) / 2,
                                width: winW, height: winH, style: style, weather: weather, tick: tick)
            if labels {
                SceneComposer.labels(&buf, margin: m, time: timeText(date), temp: tempText(weather), place: place)
            }
        }
        return buf
    }
}

// MARK: - Palettes

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

struct PixelPalette {
    private var table: [Ink: Color] = [:]
    /// Raw colours (used by the other aesthetics to read hue and brightness).
    private(set) var hex: [Ink: UInt32] = [:]
    /// Lock Screen brightness levels.
    private(set) var mono: [Ink: Double] = [:]
    let fullColor: Bool

    func color(_ ink: Ink) -> Color { table[ink] ?? .clear }

    /// Red, green, blue in 0…1.
    func rgb(_ ink: Ink) -> (Double, Double, Double) {
        let h = hex[ink] ?? 0
        return (Double((h >> 16) & 0xFF) / 255, Double((h >> 8) & 0xFF) / 255, Double(h & 0xFF) / 255)
    }

    /// Perceived brightness 0…1 (from the colour on Home Screen, from the tint level on Lock Screen).
    func luminance(_ ink: Ink) -> Double {
        guard fullColor else { return mono[ink] ?? 0 }
        let (r, g, b) = rgb(ink)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    init(style: WindowStyle, weather: WeatherSnapshot?, hour: Int, fullColor: Bool) {
        self.fullColor = fullColor
        let day = weather?.isDay ?? true
        let cond = weather?.condition ?? .clear

        do {
            // Lock Screen: iOS renders widgets in one tint, so everything is told apart by brightness.
            let o: [Ink: Double] = [
                .frameDark: 0.45, .frame: 0.75, .frameLight: 1, .mortar: 0.3, .moss: 0.55, .outline: 0.04,
                .sky: day ? 0.1 : 0.04, .skyTop: day ? 0.06 : 0.02, .skyFlash: 0.3, .glint: 0.4,
                .cloudMid: 0.75, .rainFar: 0.45, .glassDrop: 0.65, .frost: 0.8, .fogWisp: 0.55,
                .box: 0.6, .boxLight: 0.8, .boxShade: 0.45, .plantLeaf: 0.55, .plantLeafDark: 0.4, .plantBloom: 0.95,
                .sun: 1, .cloud: 0.9, .cloudShade: 0.6,
                .rain: 0.75, .snow: 1, .bolt: 1, .star: 1, .starDim: 0.5,
                .hillFar: 0.28, .hillNear: 0.42, .tree: 0.55, .bird: 0.8, .firefly: 1, .butterfly: 0.9,
                .flowerA: 0.95, .flowerB: 1, .flowerC: 0.85, .flowerCenter: 0.6, .leaf: 0.55, .leafDark: 0.4,
                .pot: 0.7, .potShade: 0.5, .catBody: 0.85, .catBelly: 1, .catEye: 0.15, .catNose: 0.5,
                .snowCap: 1, .text: 1, .textDim: 0.8, .wall: 0.2, .wallLine: 0.25, .wallAccent: 0.32,
            ]
            mono = o
        }

        let golden = day && (cond == .clear || cond == .partlyCloudy) && (17...18).contains(hour)
        let rainy = cond == .rain || cond == .storm
        let mat: (UInt32, UInt32, UInt32, UInt32) = switch style.material {
        case .wood: (0x6B3E22, 0xB0703C, 0xE0A061, 0x6B3E22)
        case .painted: (0xA9B8D0, 0xF4F1EA, 0xFFFFFF, 0xA9B8D0)
        case .stone: (0x7A7470, 0xA8A29A, 0xD2CCC2, 0x6A635E)
        case .brick: (0x9B4A35, 0xD0714F, 0xF0A07A, 0xF6E3C8)
        case .metal: (0x5E7C8A, 0x8FB3C0, 0xD3ECF2, 0x5E7C8A)
        }
        let sky: (top: UInt32, low: UInt32) = {
            if golden { return (0xF7A8C4, 0xFFD39A) }
            if day {
                switch cond {
                case .clear: return (0x7CC6F2, 0xB4E4FF)
                case .partlyCloudy: return (0x86C8F0, 0xBDE6FB)
                case .cloudy: return (0xA6BBD2, 0xCBD9E8)
                case .fog: return (0xC9D2DA, 0xE2E8EE)
                case .rain: return (0x8696A8, 0xA4B1BF)
                case .snow: return (0x8FA6C4, 0xAFC3DC)
                case .storm: return (0x555A75, 0x6E7390)
                }
            }
            switch cond {
            case .clear, .partlyCloudy: return (0x161A45, 0x2D3478)
            case .cloudy: return (0x272C50, 0x3A416A)
            case .fog: return (0x3A4062, 0x4B5275)
            case .rain: return (0x1F2440, 0x2C3354)
            case .snow: return (0x22284A, 0x333A62)
            case .storm: return (0x171A33, 0x23264A)
            }
        }()
        // Hills carry the mood: wet and muted in rain, washed out in fog, white in snow.
        let hills: (far: UInt32, near: UInt32, tree: UInt32) = {
            switch cond {
            case .snow: return day ? (0xEEF4FB, 0xFFFFFF, 0x6E8F86) : (0xB8C3E0, 0xD6DEF2, 0x4E6480)
            case .fog: return day ? (0xD3DBDD, 0xB3C6B5, 0x9DB3A2) : (0x464D6E, 0x3B4663, 0x343E5A)
            default: break
            }
            if !day { return (0x2E4A5E, 0x24404F, 0x1B3340) }
            if golden { return (0xB5CF84, 0x93BC6E, 0x6A9A5A) }
            switch cond {
            case .rain: return (0x86A88C, 0x64916B, 0x4D7A56)
            case .storm: return (0x6E8C7C, 0x557A5E, 0x41654B)
            case .cloudy: return (0x86BE88, 0x6AA872, 0x4E8F5C)
            default: return (0x9BDB8C, 0x74C26E, 0x4FA35E)
            }
        }()
        let clouds: (UInt32, UInt32, UInt32) = {
            switch cond {
            case .storm: return day ? (0x8E93AE, 0x737894, 0x585C78) : (0x3C4062, 0x30344F, 0x24273D)
            case .rain: return day ? (0xC4CCD6, 0xAAB4C1, 0x8E99A8) : (0x4D5576, 0x3F4664, 0x31374F)
            default: break
            }
            if !day { return (0x9AA2C8, 0x8890B6, 0x7880A8) }
            if golden { return (0xFFF0F5, 0xFBDDE6, 0xF7C6D6) }
            return (0xFFFFFF, 0xEEF3FA, 0xDDE8F6)
        }()
        let haze: UInt32 = switch cond {
        case .fog: day ? 0xF4F6F8 : 0x6B7393
        case .storm: day ? 0x8288A3 : 0x2E3250
        default: day ? 0xB8C3CF : 0x3B4364
        }
        let sun: UInt32 = cond == .fog ? (day ? 0xEEEDE6 : 0x6E7598) : (day ? (golden ? 0xFF9E6B : 0xFFD95A) : 0xFFF1B8)
        // The window box is outdoors: darker at night, a little darker when wet.
        let blooms: (UInt32, UInt32, UInt32, UInt32) = day ? (0xE35D5D, 0xF4C542, 0x6F9BE8, 0xFFF2C8)
                                                           : (0x7E3E4A, 0x8C7A3E, 0x40598A, 0x8C8A78)
        let leaves: (UInt32, UInt32) = !day ? (0x3B6447, 0x2B4D36) : (rainy ? (0x5EAE64, 0x418C4C) : (0x6CC070, 0x4A9A55))
        let box: (UInt32, UInt32, UInt32) = !day ? (0x5E4130, 0x6E4E38, 0x432E21)
                                                 : (rainy ? (0x8A5631, 0xA97245, 0x5E391F) : (0xA0673A, 0xC98A52, 0x6E4426))
        let paper = style.wallpaper.colors

        let t: [Ink: UInt32] = [
            .frameDark: mat.0, .frame: mat.1, .frameLight: mat.2, .mortar: mat.3, .moss: 0x8DBF6A,
            .outline: paper.outline,
            .skyTop: sky.top, .sky: sky.low, .skyFlash: day ? 0xC8CCE4 : 0x5E6390,
            .sun: sun, .cloud: clouds.0, .cloudMid: clouds.1, .cloudShade: clouds.2,
            .star: 0xFFF6C8, .starDim: 0x8C93D6,
            .rain: day ? (cond == .storm ? 0xC5CDE0 : 0xD3DFEA) : 0x8391B8,
            .rainFar: cond == .snow ? (day ? 0xDCE6F2 : 0x9AA6C8) : (day ? (cond == .storm ? 0x8F96B0 : 0xB3C0CE) : 0x4B5680),
            .snow: day ? 0xFFFFFF : 0xE3E9F7, .bolt: 0xFFF4B0,
            .glassDrop: day ? 0xE4EEF6 : 0xA6B2D4, .frost: day ? 0xF2F8FF : 0xC4CEE8, .fogWisp: haze,
            .hillFar: hills.far, .hillNear: hills.near, .tree: hills.tree,
            .bird: golden ? 0x5A4A4A : 0x4B5175, .firefly: 0xF4FF7A, .butterfly: 0xF2A541,
            .flowerA: blooms.0, .flowerB: blooms.1, .flowerC: blooms.2, .flowerCenter: blooms.3,
            .leaf: leaves.0, .leafDark: leaves.1, .box: box.0, .boxLight: box.1, .boxShade: box.2,
            .plantLeaf: 0x6CC070, .plantLeafDark: 0x4A9A55, .plantBloom: 0xE35D5D, .pot: 0xD9774F, .potShade: 0xA8553A,
            .catBody: 0xF5A65B, .catBelly: 0xFFE6C7, .catEye: 0x3B2A20, .catNose: 0xF27D8E,
            .snowCap: 0xFFFFFF,
            .text: paper.text, .textDim: paper.dim,
            .wall: paper.wall, .wallLine: paper.line, .wallAccent: paper.accent,
        ]
        hex = t
        hex[.glint] = 0xEAF6FF
        if fullColor {
            table = t.mapValues { Color(hex: $0) }
            table[.glint] = .white.opacity(0.55)
        } else {
            table = mono.mapValues { Color.white.opacity($0) }
        }
    }
}

// MARK: - SwiftUI views

/// Paints a PixelBuffer as crisp squares (one merged path per colour).
struct PixelArtView: View {
    let buffer: PixelBuffer
    let palette: PixelPalette
    let pixelSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let ox = ((size.width - CGFloat(buffer.width) * pixelSize) / 2).rounded(.down)
            let oy = ((size.height - CGFloat(buffer.height) * pixelSize) / 2).rounded(.down)
            var paths: [Ink: Path] = [:]
            for y in 0..<buffer.height {
                var x = 0
                while x < buffer.width {
                    let ink = buffer[x, y]
                    var run = 1
                    while x + run < buffer.width && buffer[x + run, y] == ink { run += 1 }
                    if ink != .clear {
                        paths[ink, default: Path()].addRect(CGRect(
                            x: ox + CGFloat(x) * pixelSize, y: oy + CGFloat(y) * pixelSize,
                            width: CGFloat(run) * pixelSize, height: pixelSize))
                    }
                    x += run
                }
            }
            for (ink, path) in paths { context.fill(path, with: .color(palette.color(ink))) }
        }
    }
}

/// The complete widget picture; used by the widget and the app preview.
/// `tick` is the animation frame — defaults to the minute of the day.
struct PixelWeatherScene: View {
    var layout: SceneLayout
    var style: WindowStyle
    var weather: WeatherSnapshot?
    var date: Date
    var place: String
    var fullColor: Bool
    var pixelSize: CGFloat = 2
    var tick: Int? = nil

    var body: some View {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let frame = tick ?? hour * 60 + cal.component(.minute, from: date)
        GeometryReader { geo in
            if style.aesthetic.isCharacterGrid {
                // ASCII & Terminal: a character grid (≈26 rows on Home Screen widgets) so the
                // weather picture reads like an image; labels are normal-size text on top.
                let dense: CGFloat = layout == .home ? (geo.size.height > 300 ? 36 : 26) : 14
                let chH = geo.size.height / dense
                let cw = chH / 1.7
                let rowsN = Int(geo.size.height / chH)
                let labels = layout == .home || layout == .lockRectangular
                let labelSize: CGFloat = layout == .home ? (geo.size.height > 300 ? 14 : 10.5) : 8
                let inset: CGFloat = layout == .home ? 10 : 3
                let band = labels ? Int(((inset + labelSize + 4) / chH).rounded(.up)) : 0
                ZStack {
                    CharGridView(
                        grid: AsciiComposer.compose(cols: Int(geo.size.width / cw), rows: rowsN, cellRatio: 1.7,
                                                    weather: weather, tick: frame,
                                                    top: band, bottom: rowsN - 1 - band,
                                                    unicode: style.aesthetic == .terminal),
                        cell: CGSize(width: cw, height: chH), terminal: style.aesthetic == .terminal, fullColor: fullColor)
                    if labels {
                        CharLabels(time: SceneComposer.timeText(date), temp: SceneComposer.tempText(weather),
                                   place: place, terminal: style.aesthetic == .terminal, fullColor: fullColor,
                                   tick: frame, size: labelSize, inset: inset)
                    }
                }
            } else {
                let cols = Int(geo.size.width / pixelSize)
                let rows = Int(geo.size.height / pixelSize)
                ZStack {
                    AestheticCanvas(
                        buffer: SceneComposer.render(layout: layout, cols: cols, rows: rows, style: style,
                                                     weather: weather, date: date, place: place, tick: frame,
                                                     labels: !style.aesthetic.textLabels),
                        palette: PixelPalette(style: style, weather: weather, hour: hour, fullColor: fullColor),
                        pixelSize: pixelSize, aesthetic: style.aesthetic, material: style.material,
                        isDay: weather?.isDay ?? true, tick: frame)
                    if style.aesthetic.textLabels && (layout == .home || layout == .lockRectangular) {
                        TextLabels(time: SceneComposer.timeText(date), temp: SceneComposer.tempText(weather),
                                   place: place, aesthetic: style.aesthetic, material: style.material, fullColor: fullColor,
                                   inset: CGFloat(layout == .home ? 5 : 2) * pixelSize, size: 5 * pixelSize)
                    }
                }
            }
        }
    }
}
