import SwiftUI
import Foundation

struct IssuerBranding: Equatable {
    let displayName: String
    let domain: String?
    let color: Color
    
    // Use company name for logo fetching (clean version of display name)
    var companyName: String {
        // Clean up the display name for logo.dev
        let cleaned = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
    
    /// The logo's file name in the cache, without the extension.
    ///
    /// Only the company name goes in, because that is all the logo is looked up
    /// by: two labels that clean to the same name get the same picture anyway.
    /// This used to carry a suffix of `hashValue`, which Swift seeds randomly on
    /// every launch, so no launch could find what the previous one had cached —
    /// each re-fetched every logo (sending the user's service names to logo.dev
    /// again) and left the old file behind. `companyName` holds only letters,
    /// digits and spaces, so an underscore after the `name_` prefix can only be
    /// one of those old suffixes; `LogoCacheManager.migrateLegacyFiles(in:)`
    /// relies on that. Matches Android's `cacheKey`.
    var cacheKey: String {
        "name_\(companyName.lowercased())"
    }
    
    init(displayName: String, domain: String?, color: Color) {
        self.displayName = displayName
        self.domain = domain
        self.color = color
    }
}

// MARK: - Logo Cache Manager
class LogoCacheManager {
    static let shared = LogoCacheManager()

    /// Whether the user allows the issuer-logo lookup at all.
    ///
    /// Read straight from `UserDefaults` rather than through `@AppStorage`, because
    /// the callers are not views. `true` when the key has never been written, which
    /// is the default the Settings switch and `AppPreferences` both declare — a
    /// plain `bool(forKey:)` would read as `false` and silently turn the feature off
    /// for everyone who has never opened Settings. A new install never reaches
    /// that fallback: onboarding writes its answer, off unless the user turned it
    /// on (`OnboardingChoices`).
    static var isFetchingEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferences.fetchIssuerLogosKey) as? Bool ?? true
    }

    /// Set once the hash-suffixed files from before `cacheKey` was made stable
    /// have been renamed, so the directory is only walked for them once.
    static let legacyCacheMigratedKey = "issuerLogoCacheKeysMigrated"

    private let fileManager = FileManager.default
    private lazy var cacheDirectory: URL = {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheURL = urls[0].appendingPathComponent("IssuerLogos", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.legacyCacheMigratedKey) {
            Self.migrateLegacyFiles(in: cacheURL, fileManager: fileManager)
            defaults.set(true, forKey: Self.legacyCacheMigratedKey)
        }
        return cacheURL
    }()

    /// Renames logos cached under the old `name_<company>_<hashValue>.png` keys to
    /// the stable `name_<company>.png`, so they are found again instead of
    /// fetched again.
    ///
    /// The old suffix changed on every launch, so one company can have several of
    /// these piled up: the first one wins and the rest are deleted (they are the
    /// same picture). A file already under the new name is kept as it is.
    static func migrateLegacyFiles(in directory: URL, fileManager: FileManager = .default) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "png" {
            let key = file.deletingPathExtension().lastPathComponent
            guard key.hasPrefix("name_") else { continue }
            let rest = key.dropFirst("name_".count)
            guard let suffixStart = rest.lastIndex(of: "_") else { continue }

            let stable = directory.appendingPathComponent("name_\(rest[..<suffixStart]).png")
            if fileManager.fileExists(atPath: stable.path) {
                try? fileManager.removeItem(at: file)
            } else {
                try? fileManager.moveItem(at: file, to: stable)
            }
        }
    }
    
    private let logoDevPublishableKey: String? = {
        Bundle.main.object(forInfoDictionaryKey: "LOGODEV_PUBLISHABLE_KEY") as? String
    }()
    
    /// Logos already decoded this launch, so an icon can draw its logo on its
    /// first frame. Without it, every icon drew its letter first and swapped the
    /// logo in a frame later — at launch, on every scroll, in every sheet —
    /// because the disk read waited for `.task`.
    private let decoded = NSCache<NSString, PlatformImage>()

    /// Names logo.dev answered without a logo, this launch. Remembered so an
    /// unknown service is asked about once rather than every time its icon
    /// appears, which is both a request wasted and the service's name sent again.
    /// Not kept across launches, so a logo added later is still found.
    private var notFound: Set<String> = []

    // MARK: - Public Methods

    /// The logo if it is already decoded, and `nil` otherwise. Cheap enough to
    /// call from `body`; it never touches the disk.
    func decodedLogo(for branding: IssuerBranding) -> PlatformImage? {
        decoded.object(forKey: branding.cacheKey as NSString)
    }

    /// The logo from memory, or else from the cache on disk — read and decoded
    /// once per name per launch.
    func getCachedLogo(for branding: IssuerBranding) -> PlatformImage? {
        if let image = decodedLogo(for: branding) { return image }
        let fileURL = cacheDirectory.appendingPathComponent("\(branding.cacheKey).png")

        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = PlatformImage(data: data) else {
            return nil
        }

        decoded.setObject(image, forKey: branding.cacheKey as NSString)
        return image
    }

    func cacheLogo(_ image: PlatformImage, for branding: IssuerBranding) {
        decoded.setObject(image, forKey: branding.cacheKey as NSString)
        let fileURL = cacheDirectory.appendingPathComponent("\(branding.cacheKey).png")

        // Save as PNG
        if let data = image.pngData() {
            try? data.write(to: fileURL)
        }
    }
    
    /// `completion` runs on the main actor.
    func fetchAndCacheLogo(for branding: IssuerBranding, completion: @escaping @MainActor (PlatformImage?) -> Void) {
        // Nothing leaves the device unless the user has left this on. The lookup sends
        // the *issuer's name* to logo.dev — not a secret, but a statement about which
        // services this person has accounts with, which is the kind of thing a
        // privacy-first app should ask about rather than decide. The switch that
        // writes this key is in Settings; icons already in the cache keep showing
        // either way, because this only stops the request.
        guard Self.isFetchingEnabled else {
            completion(nil)
            return
        }

        guard let token = logoDevPublishableKey, token.hasPrefix("pk_") else {
            // No API key, don't fetch
            completion(nil)
            return
        }

        guard !notFound.contains(branding.cacheKey) else {
            completion(nil)
            return
        }
        
        // Try to fetch by company name first (works for all services)
        if let url = logoURLByName(for: branding.companyName) {
            fetchLogo(url: url, branding: branding, completion: completion)
        } else {
            completion(nil)
        }
    }
    
    private func fetchLogo(url: URL, branding: IssuerBranding, completion: @escaping @MainActor (PlatformImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            let image = data.flatMap { error == nil ? PlatformImage(data: $0) : nil }
            // Only a real "no logo" is remembered: a 404, or a successful reply
            // that isn't an image. A request that never got an answer (offline),
            // or one refused for some other reason — rate limited, a bad key, a
            // server error — says nothing about the service, so it is tried again.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let answeredWithoutLogo = error == nil && image == nil
                && (status == 404 || (200..<300).contains(status))
            // The cache is main-actor state, read by the views, so it is written
            // there too rather than from URLSession's queue.
            Task { @MainActor in
                if let image {
                    self.cacheLogo(image, for: branding)
                } else if answeredWithoutLogo {
                    self.notFound.insert(branding.cacheKey)
                }
                completion(image)
            }
        }.resume()
    }
    
    func clearCache() {
        decoded.removeAllObjects()
        notFound.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
    }
    
    // MARK: - Private Methods
    
    private func logoURLByName(for companyName: String) -> URL? {
        guard let token = logoDevPublishableKey, token.hasPrefix("pk_") else {
            return nil
        }
        
        // Clean the company name for URL
        let cleanedName = companyName
            .replacingOccurrences(of: " ", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? companyName
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.logo.dev"
        components.path = "/name/\(cleanedName)"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "format", value: "png"),
            URLQueryItem(name: "size", value: "64"),
            URLQueryItem(name: "retina", value: "true"),
            URLQueryItem(name: "fit", value: "cover")
        ]
        return components.url
    }
}

// MARK: - Icon View with Caching
struct IssuerIconView: View {
    let branding: IssuerBranding

    // Icon diameter; the token card passes 44, other callers use the default.
    var size: CGFloat = 28

    /// Whether a logo that isn't cached may be looked up.
    ///
    /// `false` for the Edit Token preview, which follows the name field as it is
    /// typed: looking each keystroke up sent logo.dev "G", "Gi", "Git" in turn —
    /// none of them names a service the user has — for a picture the card fetches
    /// anyway once the rename is saved.
    var fetchesMissingLogo = true

    /// The logo, once read from the cache or fetched. Read from disk in `.task`
    /// rather than in `body`, which used to read and decode the file on every
    /// evaluation — and the token list re-evaluates every second. `body` only
    /// asks the in-memory copy, which costs nothing.
    @State private var logo: PlatformImage?
    @State private var isLoading = false

    /// How long a name has to stay put before it is looked up, so a list that
    /// scrolls past, or a label that is still changing, doesn't send a request
    /// for each step on the way.
    private static let fetchDelay: Duration = .milliseconds(400)

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(branding.color.opacity(0.10))

            // The decoded copy first, so a logo seen before draws on this frame
            // rather than after `.task` runs.
            if let logo = logo ?? LogoCacheManager.shared.decodedLogo(for: branding) {
                Image(platformImage: logo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if isLoading {
                // Loading state - centered in circle
                ProgressView()
                    .controlSize(size >= 44 ? .regular : .small)
                    .frame(width: size, height: size)
            } else {
                // Fallback monogram - centered in circle
                fallbackMonogram
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(branding.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityLabel(Text("\(branding.displayName) icon"))
        // Keyed on the cache key, so a rename loads the new name's logo and a
        // change that doesn't affect it (a colour, say) doesn't reload anything.
        // Nothing is ever deleted from here: two tokens can share one cached
        // logo, and the one being renamed is not the only one using it.
        .task(id: branding.cacheKey) {
            await loadLogo()
        }
    }

    private func loadLogo() async {
        isLoading = false
        logo = LogoCacheManager.shared.getCachedLogo(for: branding)
        guard logo == nil, fetchesMissingLogo, !branding.companyName.isEmpty,
              LogoCacheManager.isFetchingEnabled else { return }

        // Cancelled by the next change to the name, or by the icon going away.
        try? await Task.sleep(for: Self.fetchDelay)
        guard !Task.isCancelled else { return }

        isLoading = true
        let fetched = await withCheckedContinuation { continuation in
            LogoCacheManager.shared.fetchAndCacheLogo(for: branding) { image in
                continuation.resume(returning: image)
            }
        }
        guard !Task.isCancelled else { return }
        isLoading = false
        logo = fetched
    }

    private var fallbackMonogram: some View {
        ZStack {
            // Monogram circle background
            Circle()
                .fill(branding.color.opacity(0.15))

            // Monogram letter
            Text(String(branding.displayName.prefix(1)).uppercased())
                .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                .foregroundColor(branding.color)
        }
    }
}

// MARK: - Updated Branding Logic
extension IssuerBranding {
    /// Colours for services without a brand colour of their own, picked by
    /// `fallbackPaletteIndex(for:)`. The order is shared with Android's palette,
    /// so changing it changes which colour every such service gets on both.
    static let fallbackPalette: [Color] = [
        hex(0x6366F1), // indigo
        hex(0x06B6D4), // cyan
        hex(0x10B981), // emerald
        hex(0xF59E0B), // amber
        hex(0xEF4444), // red
        hex(0xA855F7)  // purple
    ]

    private static func hex(_ value: UInt32) -> Color {
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    static func forLabel(_ rawLabel: String) -> IssuerBranding {
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = label.lowercased()
        
        // Common issuers for domain-based color matching
        if normalized.contains("github") {
            return IssuerBranding(displayName: label, domain: "github.com", color: hex(0x8E8E93))
        }
        if normalized.contains("google") || normalized.contains("gmail") {
            return IssuerBranding(displayName: label, domain: "google.com", color: hex(0x4285F4))
        }
        if normalized == "aws" || normalized.contains("amazon web services") || normalized.contains("amazon") {
            return IssuerBranding(displayName: label, domain: "aws.amazon.com", color: hex(0xFF9900))
        }
        if normalized.contains("microsoft") || normalized.contains("azure") || normalized.contains("office") {
            return IssuerBranding(displayName: label, domain: "microsoft.com", color: hex(0x0078D4))
        }
        if normalized.contains("dropbox") {
            return IssuerBranding(displayName: label, domain: "dropbox.com", color: hex(0x0061FF))
        }
        if normalized.contains("discord") {
            return IssuerBranding(displayName: label, domain: "discord.com", color: hex(0x5865F2))
        }
        if normalized.contains("slack") {
            return IssuerBranding(displayName: label, domain: "slack.com", color: hex(0x4A154B))
        }
        if normalized.contains("notion") {
            return IssuerBranding(displayName: label, domain: "notion.so", color: hex(0x8E8E93))
        }
        if normalized.contains("gitlab") {
            return IssuerBranding(displayName: label, domain: "gitlab.com", color: hex(0xFC6D26))
        }
        if normalized.contains("bitbucket") {
            return IssuerBranding(displayName: label, domain: "bitbucket.org", color: hex(0x0052CC))
        }
        
        // Generic fallback (stable per label)
        let color = fallbackPalette[fallbackPaletteIndex(for: normalized)]
        return IssuerBranding(displayName: label, domain: nil, color: color)
    }

    /// Which `fallbackPalette` colour a trimmed, lowercased label gets.
    ///
    /// Deliberately not `hashValue`: Swift seeds `Hasher` randomly on every
    /// launch, so a service's ring and monogram changed colour each time the app
    /// started. FNV-1a gives the same answer on every launch and device, and is
    /// exactly what Android uses, so a service is the same colour on both.
    static func fallbackPaletteIndex(for normalized: String) -> Int {
        Int(fnv1a(normalized) % UInt32(fallbackPalette.count))
    }

    /// 32-bit FNV-1a over the UTF-8 bytes of `text`. Byte for byte the same as
    /// `fnv1a` in Android's `IssuerBranding.kt`.
    static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash = (hash ^ UInt32(byte)) &* 0x0100_0193
        }
        return hash
    }
}
