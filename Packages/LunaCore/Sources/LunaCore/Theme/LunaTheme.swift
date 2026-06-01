import SwiftUI

public struct LunaTheme {
    public static let primary = Color.purple
    public static let secondary = Color.indigo
    public static let accent = Color(red: 0.8, green: 0.4, blue: 1.0)

    public static let background = Color(red: 0.05, green: 0.05, blue: 0.12)
    public static let surface = Color(red: 0.1, green: 0.1, blue: 0.18)
    public static let surfaceElevated = Color(red: 0.15, green: 0.15, blue: 0.22)

    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.7)
    public static let textTertiary = Color.white.opacity(0.5)
}

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
