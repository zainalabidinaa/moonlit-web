import SwiftUI

public struct LunaTypography {
    public static func registerFonts() {
        let names = ["JetBrainsSans-Regular", "JetBrainsSans-SemiBold", "JetBrainsSans-Bold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static let family = "JetBrains Sans"

    public static func displayLg(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 40 * m.fontScaleMultiplier).weight(.bold)
    }
    public static func titleLg(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 28 * m.fontScaleMultiplier).weight(.semibold)
    }
    public static func titleMd(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 22 * m.fontScaleMultiplier).weight(.semibold)
    }
    public static func titleSm(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 18 * m.fontScaleMultiplier).weight(.semibold)
    }
    public static func bodyLg(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 16 * m.fontScaleMultiplier).weight(.regular)
    }
    public static func bodyMd(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 14 * m.fontScaleMultiplier).weight(.regular)
    }
    public static func bodySm(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 13 * m.fontScaleMultiplier).weight(.regular)
    }
    public static func labelLg(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 14 * m.fontScaleMultiplier).weight(.semibold)
    }
    public static func labelMd(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 12 * m.fontScaleMultiplier).weight(.semibold)
    }
    public static func labelSm(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 11 * m.fontScaleMultiplier).weight(.semibold)
    }
    public static func labelXs(_ m: ResponsiveMetrics) -> Font {
        .custom(family, size: 10 * m.fontScaleMultiplier).weight(.bold)
    }
}
