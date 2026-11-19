import SpriteKit
import UIKit
import CitySprintCore

extension RGB {
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    func uiColor(alpha: CGFloat) -> UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }

    func blended(with other: RGB, _ t: Double) -> UIColor {
        UIColor(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                blue: blue + (other.blue - blue) * t, alpha: 1)
    }
}

/// Draws every sprite procedurally (original stylised art, no external
/// assets) and packs them into a single `SKTextureAtlas` per level, so the
/// renderer works from one atlas and batches draw calls.
struct TextureFactory {
    struct Metrics {
        let laneWidth: CGFloat
        let pointsPerMeter: CGFloat
        func w(_ lanes: Double) -> CGFloat { max(4, CGFloat(lanes) * laneWidth) }
        func h(_ meters: Double) -> CGFloat { max(4, CGFloat(meters) * pointsPerMeter) }
    }

    let city: CityDefinition
    let signals: SignalPalette
    let metrics: Metrics
    let bike: CosmeticItem
    let jersey: CosmeticItem
    let helmet: CosmeticItem

    static let buildingVariants = 8

    func makeAtlas() -> SKTextureAtlas {
        var images: [String: UIImage] = [:]
        let p = city.palette
        images["player"] = player()
        for (i, color) in p.vehicles.enumerated() {
            images["car\(i)"] = car(color: color, taxi: city.id == .newYork && color == RGB(0xF5C518))
            images["bus\(i)"] = bus(color: color)
            images["scooter\(i)"] = scooter(color: color)
            images["parked\(i)"] = car(color: color, taxi: false)
        }
        for i in 0..<6 {
            images["ped\(i)"] = pedestrian(i)
            images["cyclist\(i)"] = cyclist(i)
        }
        images["door"] = door()
        images["construction"] = construction()
        for i in 0..<3 { images["pothole\(i)"] = pothole(i) }
        images["coin"] = coin()
        images["water"] = water()
        images["tram0"] = tram(flip: false)
        images["tram1"] = tram(flip: true)
        images["cobbleTile"] = cobbleTile()
        images["stopLine"] = stopLine()
        images["lightGo"] = lightHead(.go)
        images["lightCaution"] = lightHead(.caution)
        images["lightStop"] = lightHead(.stop)
        images["dash"] = rect(CGSize(width: 4, height: metrics.h(2.4)), p.laneMark.uiColor(alpha: 0.85))
        images["signal"] = blinker()
        images["speedLine"] = rect(CGSize(width: 2, height: metrics.h(2.5)), UIColor(white: 1, alpha: 0.5))
        images["rain"] = rect(CGSize(width: 1.5, height: 18), UIColor(white: 0.9, alpha: 0.55))
        images["particle"] = circle(8, .white)
        for i in 0..<TextureFactory.buildingVariants { images["building\(i)"] = building(i) }
        images["tree"] = tree()
        return SKTextureAtlas(dictionary: images)
    }

    // MARK: Helpers

    private func render(_ size: CGSize, _ draw: (CGContext, CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(ctx.cgContext, CGRect(origin: .zero, size: size))
        }
    }

    private func rect(_ size: CGSize, _ color: UIColor) -> UIImage {
        render(size) { c, r in
            c.setFillColor(color.cgColor)
            c.fill(r)
        }
    }

    private func circle(_ d: CGFloat, _ color: UIColor) -> UIImage {
        render(CGSize(width: d, height: d)) { c, r in
            c.setFillColor(color.cgColor)
            c.fillEllipse(in: r)
        }
    }

    private func roundRect(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, _ color: UIColor) {
        c.setFillColor(color.cgColor)
        c.addPath(UIBezierPath(roundedRect: r, cornerRadius: radius).cgPath)
        c.fillPath()
    }

    // Images are drawn in UIKit coordinates (y down). "Front" of a vehicle is
    // the top of the image because traffic travels up the screen.

    private func player() -> UIImage {
        let size = CGSize(width: metrics.w(0.36), height: metrics.h(1.9))
        return render(size) { c, r in
            let wheelW = r.width * 0.16
            // Wheels
            roundRect(c, CGRect(x: r.midX - wheelW / 2, y: 0, width: wheelW, height: r.height * 0.32), wheelW / 2, .black)
            roundRect(c, CGRect(x: r.midX - wheelW / 2, y: r.height * 0.68, width: wheelW, height: r.height * 0.32),
                      wheelW / 2, .black)
            // Frame
            c.setFillColor(bike.primary.uiColor.cgColor)
            c.fill(CGRect(x: r.midX - wheelW * 0.35, y: r.height * 0.15, width: wheelW * 0.7, height: r.height * 0.7))
            // Handlebar
            roundRect(c, CGRect(x: r.width * 0.12, y: r.height * 0.2, width: r.width * 0.76, height: r.height * 0.05),
                      2, bike.secondary.uiColor)
            // Rider torso (jersey) and arms
            let torso = CGRect(x: r.width * 0.18, y: r.height * 0.3, width: r.width * 0.64, height: r.height * 0.36)
            roundRect(c, torso, r.width * 0.3, jersey.primary.uiColor)
            c.setFillColor(jersey.secondary.uiColor.cgColor)
            c.fill(CGRect(x: torso.minX + torso.width * 0.12, y: torso.midY - 2, width: torso.width * 0.76, height: 4))
            // Helmet
            let hd = r.width * 0.44
            let helmetRect = CGRect(x: r.midX - hd / 2, y: r.height * 0.24, width: hd, height: hd * 1.15)
            c.setFillColor(helmet.primary.uiColor.cgColor)
            c.fillEllipse(in: helmetRect)
            c.setFillColor(helmet.secondary.uiColor.cgColor)
            c.fill(CGRect(x: helmetRect.midX - 1.5, y: helmetRect.minY + 3, width: 3, height: helmetRect.height - 6))
        }
    }

    private func car(color: RGB, taxi: Bool) -> UIImage {
        let size = CGSize(width: metrics.w(0.62), height: metrics.h(4.4))
        return render(size) { c, r in
            roundRect(c, r.insetBy(dx: 1, dy: 1), r.width * 0.25, color.uiColor)
            let glass = UIColor(red: 0.16, green: 0.22, blue: 0.3, alpha: 1)
            roundRect(c, CGRect(x: r.width * 0.14, y: r.height * 0.2, width: r.width * 0.72, height: r.height * 0.16), 4, glass)
            roundRect(c, CGRect(x: r.width * 0.16, y: r.height * 0.68, width: r.width * 0.68, height: r.height * 0.11), 4, glass)
            roundRect(c, CGRect(x: r.width * 0.16, y: r.height * 0.38, width: r.width * 0.68, height: r.height * 0.28), 5,
                      color.blended(with: RGB(0x000000), 0.15))
            if taxi {
                // Generic roof light, no text or branding.
                roundRect(c, CGRect(x: r.width * 0.3, y: r.height * 0.47, width: r.width * 0.4, height: r.height * 0.08), 3,
                          UIColor(white: 0.97, alpha: 1))
            }
            // Head/tail lights
            c.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).cgColor)
            c.fill(CGRect(x: r.width * 0.12, y: 1, width: r.width * 0.18, height: 3))
            c.fill(CGRect(x: r.width * 0.7, y: 1, width: r.width * 0.18, height: 3))
            c.setFillColor(UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1).cgColor)
            c.fill(CGRect(x: r.width * 0.12, y: r.height - 4, width: r.width * 0.18, height: 3))
            c.fill(CGRect(x: r.width * 0.7, y: r.height - 4, width: r.width * 0.18, height: 3))
        }
    }

    private func bus(color: RGB) -> UIImage {
        let size = CGSize(width: metrics.w(0.8), height: metrics.h(11.5))
        let doubleDecker = city.id == .london
        return render(size) { c, r in
            roundRect(c, r.insetBy(dx: 1, dy: 1), 8, color.uiColor)
            let roof = color.blended(with: RGB(doubleDecker ? 0x000000 : 0xFFFFFF), doubleDecker ? 0.2 : 0.35)
            roundRect(c, r.insetBy(dx: r.width * 0.12, dy: r.height * 0.06), 6, roof)
            // Roof vents
            c.setFillColor(UIColor(white: 0.3, alpha: 0.6).cgColor)
            for i in 0..<3 {
                c.fill(CGRect(x: r.width * 0.35, y: r.height * (0.25 + Double(i) * 0.2), width: r.width * 0.3,
                              height: r.height * 0.06))
            }
            c.setFillColor(UIColor(red: 0.16, green: 0.22, blue: 0.3, alpha: 1).cgColor)
            c.fill(CGRect(x: r.width * 0.15, y: 3, width: r.width * 0.7, height: r.height * 0.035))
        }
    }

    private func scooter(color: RGB) -> UIImage {
        let size = CGSize(width: metrics.w(0.34), height: metrics.h(1.8))
        return render(size) { c, r in
            roundRect(c, CGRect(x: r.width * 0.3, y: r.height * 0.1, width: r.width * 0.4, height: r.height * 0.8),
                      r.width * 0.2, color.uiColor)
            roundRect(c, CGRect(x: r.width * 0.05, y: r.height * 0.14, width: r.width * 0.9, height: r.height * 0.05), 2, .darkGray)
            // Rider with a plain delivery box (no logos)
            roundRect(c, CGRect(x: r.width * 0.15, y: r.height * 0.55, width: r.width * 0.7, height: r.height * 0.35), 3,
                      UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1))
            c.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: r.width * 0.25, y: r.height * 0.3, width: r.width * 0.5, height: r.width * 0.55))
        }
    }

    private static let clothing: [UIColor] = [
        UIColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1), UIColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1),
        UIColor(red: 0.3, green: 0.65, blue: 0.4, alpha: 1), UIColor(red: 0.95, green: 0.75, blue: 0.2, alpha: 1),
        UIColor(red: 0.55, green: 0.35, blue: 0.7, alpha: 1), UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1),
    ]
    private static let skin: [UIColor] = [
        UIColor(red: 0.98, green: 0.84, blue: 0.7, alpha: 1), UIColor(red: 0.8, green: 0.6, blue: 0.45, alpha: 1),
        UIColor(red: 0.55, green: 0.38, blue: 0.26, alpha: 1), UIColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 1),
    ]

    private func pedestrian(_ i: Int) -> UIImage {
        let size = CGSize(width: metrics.w(0.3), height: metrics.h(0.8))
        return render(size) { c, r in
            roundRect(c, CGRect(x: 0, y: r.height * 0.2, width: r.width, height: r.height * 0.6), r.height * 0.3,
                      TextureFactory.clothing[i % 6])
            let d = min(r.width, r.height) * 0.5
            c.setFillColor(TextureFactory.skin[i % 4].cgColor)
            c.fillEllipse(in: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d))
        }
    }

    private func cyclist(_ i: Int) -> UIImage {
        let size = CGSize(width: metrics.w(0.32), height: metrics.h(1.8))
        return render(size) { c, r in
            let wheelW = r.width * 0.16
            roundRect(c, CGRect(x: r.midX - wheelW / 2, y: 0, width: wheelW, height: r.height), wheelW / 2, .black)
            roundRect(c, CGRect(x: r.width * 0.15, y: r.height * 0.32, width: r.width * 0.7, height: r.height * 0.34),
                      r.width * 0.3, TextureFactory.clothing[i % 6])
            c.setFillColor(TextureFactory.skin[(i + 1) % 4].cgColor)
            let d = r.width * 0.4
            c.fillEllipse(in: CGRect(x: r.midX - d / 2, y: r.height * 0.28, width: d, height: d))
            // A basket on city bikes
            roundRect(c, CGRect(x: r.width * 0.3, y: 2, width: r.width * 0.4, height: r.height * 0.12), 2,
                      UIColor(red: 0.6, green: 0.45, blue: 0.25, alpha: 1))
        }
    }

    private func door() -> UIImage {
        render(CGSize(width: metrics.w(0.6), height: max(6, metrics.h(0.25)))) { c, r in
            roundRect(c, r, 3, signals.hazard.uiColor)
            c.setFillColor(UIColor(red: 0.16, green: 0.22, blue: 0.3, alpha: 1).cgColor)
            c.fill(CGRect(x: r.width * 0.2, y: r.height * 0.25, width: r.width * 0.45, height: r.height * 0.5))
        }
    }

    private func construction() -> UIImage {
        let size = CGSize(width: metrics.w(0.9), height: metrics.h(16))
        return render(size) { c, r in
            roundRect(c, r, 6, UIColor(red: 0.35, green: 0.33, blue: 0.3, alpha: 1))
            // Diagonal hazard stripes in the hazard colour + white.
            c.saveGState()
            c.addPath(UIBezierPath(roundedRect: r.insetBy(dx: 3, dy: 3), cornerRadius: 4).cgPath)
            c.clip()
            c.setFillColor(signals.hazard.uiColor.cgColor)
            let stripe: CGFloat = 14
            var y: CGFloat = -r.width
            while y < r.height + r.width {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: r.width, y: y - r.width * 0.6))
                path.addLine(to: CGPoint(x: r.width, y: y - r.width * 0.6 + stripe))
                path.addLine(to: CGPoint(x: 0, y: y + stripe))
                path.close()
                c.addPath(path.cgPath)
                c.fillPath()
                y += stripe * 2
            }
            c.restoreGState()
            // Cones
            c.setFillColor(UIColor(red: 1, green: 0.5, blue: 0.05, alpha: 1).cgColor)
            for k in 0..<5 {
                let cy = r.height * CGFloat(k) / 4.0
                c.fillEllipse(in: CGRect(x: -2, y: cy - 5, width: 10, height: 10))
            }
        }
    }

    private func pothole(_ i: Int) -> UIImage {
        let size = CGSize(width: metrics.w(0.38), height: metrics.h(0.9))
        return render(size) { c, r in
            c.setFillColor(UIColor(white: 0.08, alpha: 0.85).cgColor)
            c.fillEllipse(in: r.insetBy(dx: CGFloat(i) * 2, dy: 1))
            c.setStrokeColor(UIColor(white: 0.55, alpha: 0.6).cgColor)
            c.setLineWidth(2)
            c.strokeEllipse(in: r.insetBy(dx: CGFloat(i) * 2 + 1, dy: 2))
        }
    }

    private func coin() -> UIImage {
        let d = min(metrics.w(0.26), metrics.h(0.9))
        return render(CGSize(width: d, height: d)) { c, r in
            c.setFillColor(signals.coin.uiColor.cgColor)
            c.fillEllipse(in: r.insetBy(dx: 1, dy: 1))
            c.setStrokeColor(UIColor(white: 0, alpha: 0.35).cgColor)
            c.setLineWidth(2)
            c.strokeEllipse(in: r.insetBy(dx: r.width * 0.2, dy: r.width * 0.2))
            // Small star glyph keeps coins distinguishable without colour.
            let star = UIBezierPath()
            let cx = r.midX, cy = r.midY, outer = r.width * 0.22, inner = r.width * 0.1
            for k in 0..<10 {
                let a = CGFloat(k) * .pi / 5 - .pi / 2
                let rad = k % 2 == 0 ? outer : inner
                let pt = CGPoint(x: cx + cos(a) * rad, y: cy + sin(a) * rad)
                if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.close()
            c.setFillColor(UIColor(white: 1, alpha: 0.8).cgColor)
            c.addPath(star.cgPath)
            c.fillPath()
        }
    }

    private func water() -> UIImage {
        let size = CGSize(width: metrics.w(0.2), height: metrics.h(1.0))
        return render(size) { c, r in
            roundRect(c, CGRect(x: 0, y: r.height * 0.2, width: r.width, height: r.height * 0.8), r.width * 0.3,
                      signals.water.uiColor)
            roundRect(c, CGRect(x: r.width * 0.25, y: 0, width: r.width * 0.5, height: r.height * 0.22), 2, .white)
            c.setFillColor(UIColor(white: 1, alpha: 0.5).cgColor)
            c.fill(CGRect(x: r.width * 0.2, y: r.height * 0.45, width: r.width * 0.6, height: r.height * 0.12))
        }
    }

    private func tram(flip: Bool) -> UIImage {
        let size = CGSize(width: metrics.laneWidth * 3, height: metrics.h(12))
        return render(size) { c, r in
            c.setFillColor(UIColor(white: 0.5, alpha: 0.18).cgColor)
            c.fill(r)
            c.setStrokeColor(UIColor(white: 0.82, alpha: 0.95).cgColor)
            c.setLineWidth(4)
            for offset in [r.height * 0.3, r.height * 0.6] {
                c.move(to: CGPoint(x: 0, y: flip ? offset - r.height * 0.25 : offset + r.height * 0.25))
                c.addLine(to: CGPoint(x: r.width, y: flip ? offset + r.height * 0.25 : offset - r.height * 0.25))
            }
            c.strokePath()
            // Warning chevrons at the edges.
            c.setFillColor(signals.hazard.uiColor(alpha: 0.85).cgColor)
            c.fill(CGRect(x: 0, y: r.height - 6, width: r.width, height: 6))
        }
    }

    private func cobbleTile() -> UIImage {
        let size = CGSize(width: metrics.laneWidth * 3, height: metrics.h(4))
        return render(size) { c, r in
            c.setFillColor(UIColor(red: 0.5, green: 0.47, blue: 0.43, alpha: 1).cgColor)
            c.fill(r)
            let stone: CGFloat = 14
            var row = 0
            var y: CGFloat = 0
            while y < r.height {
                var x: CGFloat = row % 2 == 0 ? 0 : -stone / 2
                while x < r.width {
                    let shade = 0.55 + 0.1 * CGFloat((Int(x) * 7 + Int(y) * 13) % 5) / 5
                    roundRect(c, CGRect(x: x + 1, y: y + 1, width: stone - 2, height: stone - 2), 3,
                              UIColor(red: shade, green: shade * 0.95, blue: shade * 0.88, alpha: 1))
                    x += stone
                }
                y += stone
                row += 1
            }
        }
    }

    private func stopLine() -> UIImage {
        rect(CGSize(width: metrics.laneWidth * 3, height: 8), UIColor(white: 0.97, alpha: 0.95))
    }

    /// Traffic light head seen from above, placed at the roadside. Position
    /// (top = stop, bottom = go) and shape (square = stop) carry meaning
    /// independently of colour.
    private func lightHead(_ phase: TrafficLightPhase) -> UIImage {
        let unit = max(16, metrics.laneWidth * 0.2)
        let size = CGSize(width: unit + 8, height: unit * 3 + 12)
        return render(size) { c, r in
            roundRect(c, r, 6, UIColor(white: 0.1, alpha: 1))
            let slots: [(TrafficLightPhase, RGB)] = [(.stop, signals.lightStop), (.caution, signals.lightCaution),
                                                    (.go, signals.lightGo)]
            for (k, slot) in slots.enumerated() {
                let frame = CGRect(x: 4, y: 4 + CGFloat(k) * (unit + 2), width: unit, height: unit)
                let lit = slot.0 == phase
                c.setFillColor(lit ? slot.1.uiColor.cgColor : UIColor(white: 0.25, alpha: 1).cgColor)
                switch slot.0 {
                case .stop: c.fill(frame.insetBy(dx: 2, dy: 2))
                case .caution:
                    let tri = UIBezierPath()
                    tri.move(to: CGPoint(x: frame.midX, y: frame.minY + 2))
                    tri.addLine(to: CGPoint(x: frame.maxX - 2, y: frame.maxY - 2))
                    tri.addLine(to: CGPoint(x: frame.minX + 2, y: frame.maxY - 2))
                    tri.close()
                    c.addPath(tri.cgPath)
                    c.fillPath()
                case .go: c.fillEllipse(in: frame.insetBy(dx: 2, dy: 2))
                }
            }
        }
    }

    private func blinker() -> UIImage {
        circle(max(8, metrics.laneWidth * 0.08), UIColor(red: 1, green: 0.7, blue: 0.1, alpha: 1))
    }

    private func tree() -> UIImage {
        let d = metrics.h(4)
        return render(CGSize(width: d, height: d)) { c, r in
            c.setFillColor(city.palette.greenery.uiColor.cgColor)
            c.fillEllipse(in: r.insetBy(dx: 2, dy: 2))
            c.setFillColor(city.palette.greenery.blended(with: RGB(0xFFFFFF), 0.2).cgColor)
            c.fillEllipse(in: CGRect(x: r.width * 0.2, y: r.height * 0.15, width: r.width * 0.4, height: r.height * 0.4))
        }
    }

    /// Roof-top views of buildings in the city's architectural style.
    private func building(_ i: Int) -> UIImage {
        let p = city.palette
        let size = CGSize(width: 120, height: 160)
        let base = p.buildings[i % p.buildings.count]
        return render(size) { c, r in
            let lot = r.insetBy(dx: 3, dy: 3)
            roundRect(c, lot, 4, base.uiColor)
            let detail = p.roofDetail.uiColor
            switch city.architecture {
            case .gridTowers:
                roundRect(c, lot.insetBy(dx: 10, dy: 12), 2, base.blended(with: RGB(0x000000), 0.18))
                // Rooftop water tank (generic) + vents
                c.setFillColor(detail.cgColor)
                c.fillEllipse(in: CGRect(x: lot.midX - 14, y: lot.minY + 20, width: 28, height: 28))
                c.setFillColor(UIColor(white: 0.75, alpha: 1).cgColor)
                c.fill(CGRect(x: lot.minX + 18, y: lot.maxY - 40, width: 18, height: 14))
            case .mansardBlocks:
                // Zinc mansard ring around a courtyard
                roundRect(c, lot.insetBy(dx: 6, dy: 6), 3, detail)
                roundRect(c, lot.insetBy(dx: 26, dy: 30), 2, base.uiColor)
                c.setFillColor(UIColor(red: 0.75, green: 0.42, blue: 0.3, alpha: 1).cgColor)
                for k in 0..<4 { c.fill(CGRect(x: lot.minX + 10 + CGFloat(k) * 26, y: lot.minY + 8, width: 8, height: 8)) }
            case .denseNeon:
                for k in 0..<3 {
                    roundRect(c, CGRect(x: lot.minX + 6, y: lot.minY + 6 + CGFloat(k) * 50, width: lot.width - 12, height: 42),
                              3, base.blended(with: RGB(0xFFFFFF), Double(k) * 0.08))
                }
                c.setFillColor(detail.cgColor)
                c.fill(CGRect(x: lot.maxX - 10, y: lot.minY + 10, width: 6, height: lot.height - 20))
                c.setFillColor(UIColor(red: 0.3, green: 0.9, blue: 1, alpha: 1).cgColor)
                c.fill(CGRect(x: lot.minX + 4, y: lot.minY + 10, width: 4, height: lot.height * 0.4))
            case .terraceBrick:
                for k in 0..<4 {
                    let row = CGRect(x: lot.minX, y: lot.minY + CGFloat(k) * lot.height / 4, width: lot.width,
                                     height: lot.height / 4 - 2)
                    roundRect(c, row, 2, base.blended(with: RGB(0x000000), k % 2 == 0 ? 0.05 : 0.15))
                    c.setFillColor(detail.cgColor)
                    c.fill(CGRect(x: row.midX - 10, y: row.midY - 4, width: 20, height: 8)) // chimney stack
                }
            case .canalGables:
                for k in 0..<3 {
                    let w = lot.width / 3
                    let gable = UIBezierPath()
                    gable.move(to: CGPoint(x: lot.minX + CGFloat(k) * w, y: lot.maxY))
                    gable.addLine(to: CGPoint(x: lot.minX + CGFloat(k) * w, y: lot.minY + 30))
                    gable.addLine(to: CGPoint(x: lot.minX + (CGFloat(k) + 0.5) * w, y: lot.minY + 8))
                    gable.addLine(to: CGPoint(x: lot.minX + CGFloat(k + 1) * w, y: lot.minY + 30))
                    gable.addLine(to: CGPoint(x: lot.minX + CGFloat(k + 1) * w, y: lot.maxY))
                    gable.close()
                    c.setFillColor(p.buildings[(i + k) % p.buildings.count].uiColor.cgColor)
                    c.addPath(gable.cgPath)
                    c.fillPath()
                    c.setFillColor(detail.cgColor)
                    c.fill(CGRect(x: lot.minX + (CGFloat(k) + 0.35) * w, y: lot.minY + 40, width: w * 0.3, height: 6))
                }
            case .hillsideColor:
                for k in 0..<4 {
                    let col = p.buildings[(i + k) % p.buildings.count]
                    roundRect(c, CGRect(x: lot.minX + CGFloat(k % 2) * lot.width / 2 + 2,
                                        y: lot.minY + CGFloat(k / 2) * lot.height / 2 + 2,
                                        width: lot.width / 2 - 4, height: lot.height / 2 - 4), 3, col.uiColor)
                }
                c.setFillColor(detail.cgColor)
                c.fill(CGRect(x: lot.minX, y: lot.midY - 2, width: lot.width, height: 4))
            case .harbourModern:
                roundRect(c, lot.insetBy(dx: 8, dy: 8), 10, base.blended(with: RGB(0xFFFFFF), 0.25))
                c.setFillColor(UIColor(red: 0.55, green: 0.75, blue: 0.85, alpha: 0.9).cgColor)
                for k in 0..<5 { c.fill(CGRect(x: lot.minX + 14, y: lot.minY + 16 + CGFloat(k) * 26, width: lot.width - 28, height: 12)) }
                c.setFillColor(detail.cgColor)
                c.fillEllipse(in: CGRect(x: lot.maxX - 30, y: lot.minY + 6, width: 20, height: 20))
            case .capeColonial:
                roundRect(c, lot.insetBy(dx: 6, dy: 6), 3, base.uiColor)
                c.setFillColor(detail.cgColor)
                c.fill(CGRect(x: lot.minX + 6, y: lot.midY - 3, width: lot.width - 12, height: 6))
                c.setFillColor(UIColor.white.cgColor)
                // Curved gable outline
                let gable = UIBezierPath(arcCenter: CGPoint(x: lot.midX, y: lot.minY + 34), radius: 20, startAngle: .pi,
                                         endAngle: 0, clockwise: true)
                gable.close()
                c.addPath(gable.cgPath)
                c.fillPath()
            }
        }
    }
}
