import Foundation

public enum MoonlitConfig {
    public static let supabaseURL = "https://hvfsntdyowapjxobtyli.supabase.co"
    public static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2ZnNudGR5b3dhcGp4b2J0eWxpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNzg0OTUsImV4cCI6MjA5NTc1NDQ5NX0.YraHrXjD-l_CmzEbs7jRW34i83HIlKcOh76xbfOn6sQ"
    // SECURITY: the service_role key must NEVER ship in the client — it bypasses
    // Row-Level Security and grants full DB admin. Admin operations must run
    // server-side (Supabase Edge Functions) using the key held there.
    public static let tmdbApiKey = "1e818317d3086727eceecf0571621527"
    public static nonisolated(unsafe) var traktClientId: String? = nil
    public static nonisolated(unsafe) var traktClientSecret: String? = nil
    public static let homeOrganizerRemoteURL: String? = "https://hvfsntdyowapjxobtyli.supabase.co/functions/v1/home-organizer"

    public static let defaultAddons: [String] = [
        "https://aiometadata.fortheweak.cloud/stremio/1bf2cd94-2057-4992-9ed7-a8464f12e4a4/manifest.json",
        "https://streailer.elfhosted.com/%7B%22language%22%3A%22en-US%22%2C%22externalLink%22%3Atrue%2C%22showRecap%22%3Atrue%2C%22onlyRecaps%22%3Afalse%7D/manifest.json",
        "https://stremio-content-deepdive-addon-dc8f7b513289.herokuapp.com/manifest.json",
        "https://opensubtitlesv3-pro.dexter21767.com/eyJsYW5ncyI6WyJlbmdsaXNoIl0sInNvdXJjZSI6ImFsbCIsImFpVHJhbnNsYXRlZCI6ZmFsc2UsImF1dG9BZGp1c3RtZW50IjpmYWxzZX0=/manifest.json",
        "https://opensubtitles-v3.strem.io/manifest.json",
    ]
}
