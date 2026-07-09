import Foundation

public enum DownloadSupport {
    /// v1 supports direct single-file streams only; HLS manifests need remuxing.
    public static func isDownloadable(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        guard let comps = URLComponents(string: urlString) else { return false }
        let ext = (comps.path as NSString).pathExtension.lowercased()
        if ext == "m3u8" || ext == "m3u" { return false }
        if lower.contains(".m3u8") { return false }
        return true
    }
}
