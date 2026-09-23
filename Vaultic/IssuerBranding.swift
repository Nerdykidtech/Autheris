import SwiftUI
import Foundation

struct IssuerBranding: Equatable {
    let displayName: String
    let domain: String?
    let color: Color
    let labelHash: Int // Store hash of original label for cache invalidation
    
    // Use company name for logo fetching (clean version of display name)
    var companyName: String {
        // Clean up the display name for logo.dev
        let cleaned = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
    
    // Add a computed property for cache key
    var cacheKey: String {
        // Use company name for cache key to handle all services
        return "name_\(companyName.lowercased())_\(labelHash)"
    }
    
    init(displayName: String, domain: String?, color: Color) {
        self.displayName = displayName
        self.domain = domain
        self.color = color
        self.labelHash = displayName.lowercased().hashValue
    }
}

// MARK: - Logo Cache Manager
class LogoCacheManager {
    static let shared = LogoCacheManager()
    
    private let fileManager = FileManager.default
    private lazy var cacheDirectory: URL = {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheURL = urls[0].appendingPathComponent("IssuerLogos", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }
        return cacheURL
    }()
    
    private let logoDevPublishableKey: String? = {
        Bundle.main.object(forInfoDictionaryKey: "LOGODEV_PUBLISHABLE_KEY") as? String
    }()
    
    // MARK: - Public Methods
    
    func hasCachedLogo(for branding: IssuerBranding) -> Bool {
        let fileURL = cacheDirectory.appendingPathComponent("\(branding.cacheKey).png")
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    func getCachedLogo(for branding: IssuerBranding) -> PlatformImage? {
        let fileURL = cacheDirectory.appendingPathComponent("\(branding.cacheKey).png")
        
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = PlatformImage(data: data) else {
            return nil
        }
        
        return image
    }
    
    func cacheLogo(_ image: PlatformImage, for branding: IssuerBranding) {
        let fileURL = cacheDirectory.appendingPathComponent("\(branding.cacheKey).png")
        
        // Save as PNG
        if let data = image.pngData() {
            try? data.write(to: fileURL)
        }
    }
    
    func fetchAndCacheLogo(for branding: IssuerBranding, completion: @escaping (PlatformImage?) -> Void) {
        guard let token = logoDevPublishableKey, token.hasPrefix("pk_") else {
            // No API key, don't fetch
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
    
    private func fetchLogo(url: URL, branding: IssuerBranding, completion: @escaping (PlatformImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil,
                  let image = PlatformImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Cache the image
            self.cacheLogo(image, for: branding)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
    }
    
    // Remove old cached logos when label changes
    func removeOldLogo(forOldBranding oldBranding: IssuerBranding?, newBranding: IssuerBranding) {
        guard let oldBranding = oldBranding,
              oldBranding.cacheKey != newBranding.cacheKey else {
            return
        }
        
        let oldFileURL = cacheDirectory.appendingPathComponent("\(oldBranding.cacheKey).png")
        if fileManager.fileExists(atPath: oldFileURL.path) {
            try? fileManager.removeItem(at: oldFileURL)
        }
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
    
    private func logoURLByDomain(for domain: String) -> URL? {
        guard let token = logoDevPublishableKey, token.hasPrefix("pk_") else {
            return nil
        }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.logo.dev"
        components.path = "/\(domain)"
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
    @State private var cachedImage: PlatformImage?
    @State private var isLoading = false
    
    // Icon diameter; the token card passes 44, other callers use the default.
    var size: CGFloat = 28
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(branding.color.opacity(0.10))
            
            if let cachedImage = cachedImage {
                // Use cached image - fill the entire circle
                Image(platformImage: cachedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if isLoading {
                // Loading state - centered in circle
                ProgressView()
                    .controlSize(size >= 44 ? .regular : .small)
                    .frame(width: size, height: size)
            } else if LogoCacheManager.shared.hasCachedLogo(for: branding),
                      let image = LogoCacheManager.shared.getCachedLogo(for: branding) {
                // Load from cache if available - fill the entire circle
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
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
        .onAppear {
            // Check if we need to fetch a new logo
            if !LogoCacheManager.shared.hasCachedLogo(for: branding) {
                fetchLogoIfNeeded()
            }
        }
        .onChange(of: branding) { oldBranding, newBranding in
            // When branding changes (e.g., service name edited), update logo
            LogoCacheManager.shared.removeOldLogo(forOldBranding: oldBranding, newBranding: newBranding)
            cachedImage = nil
            if !LogoCacheManager.shared.hasCachedLogo(for: newBranding) {
                fetchLogoIfNeeded()
            }
        }
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
    
    private func fetchLogoIfNeeded() {
        // Check if we have API key
        guard let token = Bundle.main.object(forInfoDictionaryKey: "LOGODEV_PUBLISHABLE_KEY") as? String,
              token.hasPrefix("pk_") else {
            // No API key, don't fetch
            return
        }
        
        // Only fetch if we have a valid company name
        guard !branding.companyName.isEmpty else {
            return
        }
        
        isLoading = true
        
        LogoCacheManager.shared.fetchAndCacheLogo(for: branding) { image in
            DispatchQueue.main.async {
                self.isLoading = false
                if let image = image {
                    self.cachedImage = image
                }
            }
        }
    }
}

// MARK: - Helper Extension for Token Management
extension OTPDataStore {
    func handleNewTokenAddition(_ token: OTPCode) {
        // When a new token is added, check if we need to fetch its logo
        let branding = IssuerBranding.forLabel(token.label)
        
        // Only fetch if not already cached
        if !LogoCacheManager.shared.hasCachedLogo(for: branding) {
            LogoCacheManager.shared.fetchAndCacheLogo(for: branding) { _ in
                // Logo fetched and cached, view will update automatically
            }
        }
    }
    
    func handleTokenUpdate(oldToken: OTPCode, newToken: OTPCode) {
        let oldBranding = IssuerBranding.forLabel(oldToken.label)
        let newBranding = IssuerBranding.forLabel(newToken.label)
        
        // Remove old cached logo if branding changed
        LogoCacheManager.shared.removeOldLogo(forOldBranding: oldBranding, newBranding: newBranding)
        
        // Fetch new logo if needed
        if !LogoCacheManager.shared.hasCachedLogo(for: newBranding) {
            LogoCacheManager.shared.fetchAndCacheLogo(for: newBranding) { _ in
                // Logo fetched and cached
            }
        }
    }
}

// MARK: - Updated Branding Logic
extension IssuerBranding {
    static func forLabel(_ rawLabel: String) -> IssuerBranding {
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = label.lowercased()
        
        func hex(_ value: UInt32) -> Color {
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        
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
        let hash = normalized.hashValue
        let positiveHash = UInt32(bitPattern: Int32(truncatingIfNeeded: hash))
        let palette: [Color] = [
            hex(0x6366F1), // indigo
            hex(0x06B6D4), // cyan
            hex(0x10B981), // emerald
            hex(0xF59E0B), // amber
            hex(0xEF4444), // red
            hex(0xA855F7)  // purple
        ]
        let color = palette[Int(positiveHash % UInt32(palette.count))]
        return IssuerBranding(displayName: label, domain: nil, color: color)
    }
}

