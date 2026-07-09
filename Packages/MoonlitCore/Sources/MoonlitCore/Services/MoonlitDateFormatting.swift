import Foundation

public enum MoonlitDateFormatting {

    public static func mediumDate(from raw: String?) -> String? {
        guard let raw else { return nil }
        let date = parseDate(raw)
        guard let date else { return raw }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    public static func year(from raw: String?) -> String? {
        guard let raw else { return nil }
        return String(raw.prefix(4))
    }

    private static func parseDate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        if let date = f.date(from: raw) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return iso.date(from: raw)
    }

    public static func formattedMoney(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            let billions = Double(value) / 1_000_000_000.0
            return String(format: "$%.1fB", billions)
        }
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000.0
            return String(format: "$%.0fM", millions)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    public static func formattedVoteCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
