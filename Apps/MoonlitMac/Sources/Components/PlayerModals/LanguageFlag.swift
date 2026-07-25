import Foundation

/// Small ISO 639-1 → flag-emoji lookup shared by the audio and subtitle
/// track panels (the reference shows a country flag next to each language).
/// Falls back to a globe glyph for codes we don't have a mapping for.
enum LanguageFlag {
    private static let map: [String: String] = [
        "en": "🇺🇸", "es": "🇪🇸", "fr": "🇫🇷", "de": "🇩🇪", "it": "🇮🇹",
        "pt": "🇵🇹", "ru": "🇷🇺", "ja": "🇯🇵", "ko": "🇰🇷", "zh": "🇨🇳",
        "ar": "🇸🇦", "hi": "🇮🇳", "nl": "🇳🇱", "sv": "🇸🇪", "no": "🇳🇴",
        "da": "🇩🇰", "fi": "🇫🇮", "pl": "🇵🇱", "tr": "🇹🇷", "cs": "🇨🇿",
        "el": "🇬🇷", "he": "🇮🇱", "th": "🇹🇭", "vi": "🇻🇳", "id": "🇮🇩",
        "uk": "🇺🇦", "ro": "🇷🇴", "hu": "🇭🇺", "bg": "🇧🇬", "sk": "🇸🇰",
        "hr": "🇭🇷", "sr": "🇷🇸", "fa": "🇮🇷", "ms": "🇲🇾", "tl": "🇵🇭",
        "sq": "🇦🇱", "bn": "🇧🇩", "sw": "🇰🇪", "ta": "🇮🇳", "te": "🇮🇳",
        "ml": "🇮🇳", "kn": "🇮🇳", "mr": "🇮🇳", "gu": "🇮🇳", "pa": "🇮🇳",
        "ur": "🇵🇰", "my": "🇲🇲", "km": "🇰🇭", "lo": "🇱🇦", "mn": "🇲🇳",
        "ka": "🇬🇪", "hy": "🇦🇲", "az": "🇦🇿", "kk": "🇰🇿", "uz": "🇺🇿",
        "am": "🇪🇹", "so": "🇸🇴", "zu": "🇿🇦", "af": "🇿🇦", "is": "🇮🇸",
        "lt": "🇱🇹", "lv": "🇱🇻", "et": "🇪🇪", "sl": "🇸🇮", "mk": "🇲🇰",
        "bs": "🇧🇦", "mt": "🇲🇹", "ga": "🇮🇪", "cy": "🇬🇧", "eu": "🇪🇸",
        "ca": "🇪🇸", "gl": "🇪🇸", "ne": "🇳🇵", "si": "🇱🇰",
        "ps": "🇦🇫", "sd": "🇵🇰", "ku": "🇮🇶", "yi": "🇮🇱", "la": "🇻🇦",
        "eo": "🌐", "haw": "🇺🇸", "mi": "🇳🇿", "sm": "🇼🇸", "to": "🇹🇴",
        "fj": "🇫🇯", "ht": "🇭🇹", "jv": "🇮🇩", "su": "🇮🇩", "ceb": "🇵🇭",
        "co": "🇫🇷", "fy": "🇳🇱", "lb": "🇱🇺", "mg": "🇲🇬",
        "ny": "🇲🇼", "sn": "🇿🇼", "st": "🇱🇸", "xh": "🇿🇦", "yo": "🇳🇬",
        "ig": "🇳🇬", "ha": "🇳🇬", "rw": "🇷🇼", "gd": "🇬🇧", "sc": "🇮🇹",
    ]

    /// Returns an emoji flag for a 2-3 letter language code, matching a
    /// prefix if the exact code isn't mapped (e.g. "eng" → "en" → 🇺🇸).
    static func emoji(for code: String) -> String {
        let lower = code.lowercased()
        if let exact = map[lower] { return exact }
        if lower.count > 2, let prefix = map[String(lower.prefix(2))] { return prefix }
        return "🌐"
    }
}
