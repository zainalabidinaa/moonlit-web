import SwiftUI
import MoonlitCore

enum OklchPalette {
    static func genre(_ name: String) -> (from: Color, to: Color, ink: Color) {
        switch GenreCatalog.normalize(name) {
        case "action":
            return (oklch(0.40, 0.18, 25), oklch(0.18, 0.10, 20), oklch(0.96, 0.02, 25))
        case "adventure":
            return (oklch(0.45, 0.14, 145), oklch(0.20, 0.10, 155), oklch(0.96, 0.02, 145))
        case "animation":
            return (oklch(0.50, 0.16, 200), oklch(0.20, 0.10, 195), oklch(0.96, 0.02, 200))
        case "comedy":
            return (oklch(0.55, 0.16, 75), oklch(0.22, 0.08, 60), oklch(0.96, 0.02, 80))
        case "crime":
            return (oklch(0.32, 0.10, 50), oklch(0.14, 0.04, 30), oklch(0.95, 0.04, 60))
        case "documentary":
            return (oklch(0.36, 0.10, 145), oklch(0.18, 0.06, 150), oklch(0.96, 0.02, 145))
        case "drama":
            return (oklch(0.36, 0.12, 240), oklch(0.18, 0.06, 230), oklch(0.96, 0.02, 240))
        case "family":
            return (oklch(0.50, 0.13, 100), oklch(0.20, 0.08, 110), oklch(0.96, 0.02, 100))
        case "fantasy":
            return (oklch(0.42, 0.14, 320), oklch(0.18, 0.08, 305), oklch(0.96, 0.02, 320))
        case "history":
            return (oklch(0.42, 0.10, 70), oklch(0.16, 0.05, 55), oklch(0.95, 0.04, 75))
        case "horror":
            return (oklch(0.30, 0.10, 15), oklch(0.10, 0.04, 20), oklch(0.94, 0.02, 20))
        case "music":
            return (oklch(0.46, 0.18, 320), oklch(0.18, 0.10, 305), oklch(0.96, 0.02, 320))
        case "mystery":
            return (oklch(0.32, 0.10, 95), oklch(0.14, 0.06, 80), oklch(0.95, 0.04, 90))
        case "romance":
            return (oklch(0.45, 0.15, 0), oklch(0.20, 0.08, 350), oklch(0.96, 0.02, 0))
        case "sci-fi":
            return (oklch(0.38, 0.16, 285), oklch(0.18, 0.10, 280), oklch(0.96, 0.02, 285))
        case "thriller":
            return (oklch(0.32, 0.10, 200), oklch(0.14, 0.04, 220), oklch(0.96, 0.02, 220))
        case "war":
            return (oklch(0.32, 0.06, 70), oklch(0.14, 0.04, 60), oklch(0.95, 0.02, 75))
        case "western":
            return (oklch(0.45, 0.12, 55), oklch(0.18, 0.08, 35), oklch(0.96, 0.04, 60))
        default:
            return (oklch(0.36, 0.12, 240), oklch(0.18, 0.06, 230), oklch(0.96, 0.02, 240))
        }
    }

    private static func oklch(_ L: Double, _ C: Double, _ h: Double) -> Color {
        oklchToColor(L: L, C: C, h: h)
    }

    static func oklchToColor(L: Double, C: Double, h: Double) -> Color {
        let hRad = h * .pi / 180.0
        let a = C * cos(hRad)
        let b = C * sin(hRad)

        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b

        let l3 = l_ * l_ * l_
        let m3 = m_ * m_ * m_
        let s3 = s_ * s_ * s_

        let rLin = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let gLin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bLin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

        func srgb(_ c: Double) -> Double {
            let v = max(0, min(1, c))
            if v <= 0.0031308 { return 12.92 * v }
            return 1.055 * pow(v, 1.0 / 2.4) - 0.055
        }

        return Color(red: srgb(rLin), green: srgb(gLin), blue: srgb(bLin))
    }
}
