import SwiftUI

struct WelcomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @Environment(\.colorScheme) private var colorScheme
    
    // Animated gradient state
    @State private var gradientStart = UnitPoint(x: 0, y: 0)
    @State private var gradientEnd = UnitPoint(x: 1, y: 1)
    @State private var gradientColors: [Color] = []
    
    private let totalPages = 3
    private let animationDuration = 8.0
    
    init() {
        // Initialize gradient colors based on system appearance
        _gradientColors = State(initialValue: Self.defaultGradientColors(for: .light))
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background
            animatedGradientBackground
                .ignoresSafeArea()
                .blur(radius: 40)
                .overlay(
                    Color(.systemBackground)
                        .opacity(colorScheme == .dark ? 0.85 : 0.7)
                        .ignoresSafeArea()
                )
            
            VStack(spacing: 0) {
                // Content area - Centered properly
                TabView(selection: $currentPage) {
                    // Page 1: Welcome
                    welcomePage
                        .tag(0)
                    
                    // Page 2: Features
                    featuresPage
                        .tag(1)
                    
                    // Page 3: Get Started
                    getStartedPage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 24)
                
                // Bottom controls
                VStack(spacing: 24) {
                    // Page indicators (modern dots with animation)
                    HStack(spacing: 12) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: index == currentPage ? 28 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    
                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentPage > 0 {
                            Button(action: {
                                // Haptic feedback
                                let impactLight = UIImpactFeedbackGenerator(style: .light)
                                impactLight.impactOccurred()
                                
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    currentPage -= 1
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.left")
                                        .font(.caption.weight(.semibold))
                                    Text("Back")
                                        .font(.headline)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                )
                                .foregroundColor(.primary)
                            }
                        }
                        
                        Button(action: {
                            // Haptic feedback
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                            
                            if currentPage < totalPages - 1 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    currentPage += 1
                                }
                            } else {
                                // Final page - complete onboarding
                                let successHaptic = UINotificationFeedbackGenerator()
                                successHaptic.notificationOccurred(.success)
                                hasCompletedOnboarding = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Text(currentPage < totalPages - 1 ? "Next" : "Get Started")
                                    .font(.headline)
                                if currentPage < totalPages - 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .frame(maxWidth: currentPage > 0 ? .infinity : nil)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                            .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            // Set initial gradient colors based on current color scheme
            gradientColors = Self.gradientColors(for: colorScheme)
            startGradientAnimation()
        }
        .onChange(of: colorScheme) { newColorScheme in
            // Update gradient colors when color scheme changes
            withAnimation(.easeInOut(duration: 1.0)) {
                gradientColors = Self.gradientColors(for: newColorScheme)
            }
        }
    }
    
    // MARK: - Animated Gradient Background
    private var animatedGradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: gradientColors),
            startPoint: gradientStart,
            endPoint: gradientEnd
        )
        .onAppear {
            startGradientAnimation()
        }
    }
    
    // MARK: - Gradient Animation
    private func startGradientAnimation() {
        withAnimation(
            Animation.easeInOut(duration: animationDuration)
                .repeatForever(autoreverses: true)
        ) {
            gradientStart = UnitPoint(x: 1, y: 0)
            gradientEnd = UnitPoint(x: 0, y: 1)
        }
        
        // Also animate the gradient points back and forth
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            withAnimation(
                Animation.easeInOut(duration: animationDuration)
                    .repeatForever(autoreverses: true)
            ) {
                gradientStart = UnitPoint(x: 0, y: 1)
                gradientEnd = UnitPoint(x: 1, y: 0)
            }
        }
    }
    
    // MARK: - Gradient Colors for Different Color Schemes
    private static func gradientColors(for colorScheme: ColorScheme) -> [Color] {
        switch colorScheme {
        case .dark:
            // Dark mode: Deep, professional blues and purples
            return [
                Color(red: 0.05, green: 0.1, blue: 0.3),   // Deep navy
                Color(red: 0.15, green: 0.1, blue: 0.35),  // Deep purple
                Color(red: 0.1, green: 0.2, blue: 0.4),    // Midnight blue
                Color(red: 0.2, green: 0.15, blue: 0.45)   // Royal purple
            ]
        default:
            // Light mode: Soft, professional pastels
            return [
                Color(red: 0.9, green: 0.95, blue: 1.0),   // Soft blue
                Color(red: 0.95, green: 0.9, blue: 1.0),   // Soft lavender
                Color(red: 0.9, green: 1.0, blue: 0.95),   // Soft mint
                Color(red: 1.0, green: 0.95, blue: 0.9)    // Soft peach
            ]
        }
    }
    
    private static func defaultGradientColors(for colorScheme: ColorScheme) -> [Color] {
        gradientColors(for: colorScheme)
    }
    
    // MARK: - Page 1: Welcome
    private var welcomePage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 32) {
                    // Vertical spacer to center content
                    Spacer(minLength: max(0, (geometry.size.height - 400) / 3))
                    
                    // App icon/logo with modern glow effect
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.accentColor.opacity(0.2),
                                        Color.accentColor.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 30, x: 0, y: 15)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.accentColor.opacity(0.3),
                                                Color.accentColor.opacity(0.1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60, weight: .regular))
                            .foregroundColor(.accentColor)
                            .symbolRenderingMode(.hierarchical)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    VStack(spacing: 16) {
                        Text("Welcome to")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .tracking(1)
                        
                        Text("Vaultic")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .overlay(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.accentColor,
                                        Color.accentColor.opacity(0.8)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .mask(
                                    Text("Vaultic")
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                )
                            )
                        
                        Text("Secure 2FA Token Manager")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    // Bottom spacer
                    Spacer(minLength: max(0, (geometry.size.height - 400) / 3))
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }
    
    // MARK: - Page 2: Features
    private var featuresPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 40) {
                    // Vertical spacer to center content
                    Spacer(minLength: max(0, (geometry.size.height - 500) / 4))
                    
                    Text("Everything You Need")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 32)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 32) {
                        // Feature 1: QR Scanning
                        featureRow(
                            icon: "qrcode.viewfinder",
                            title: "Quick QR Scanning",
                            description: "Add tokens instantly by scanning QR codes from any authenticator app"
                        )
                        
                        // Feature 2: Security
                        featureRow(
                            icon: "lock.iphone",
                            title: "Device-Locked Security",
                            description: "Your tokens are encrypted and never leave your device"
                        )
                        
                        // Feature 3: Modern Interface
                        featureRow(
                            icon: "timer",
                            title: "Live Countdowns",
                            description: "Real-time OTP updates with beautiful visual timers"
                        )
                    }
                    .padding(.horizontal, 32)
                    
                    // Bottom spacer
                    Spacer(minLength: max(0, (geometry.size.height - 500) / 4))
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }
    
    // MARK: - Page 3: Get Started
    private var getStartedPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 40) {
                    // Vertical spacer to center content
                    Spacer(minLength: max(0, (geometry.size.height - 500) / 4))
                    
                    // Animated checkmark with pulse effect
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.accentColor.opacity(0.15),
                                        Color.accentColor.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 30, x: 0, y: 15)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.accentColor.opacity(0.3),
                                                Color.accentColor.opacity(0.1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 56, weight: .regular))
                            .foregroundColor(.accentColor)
                            .symbolRenderingMode(.hierarchical)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    VStack(spacing: 16) {
                        Text("Ready to Begin")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("Start securing your accounts with military-grade encryption and a beautiful interface")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }
                    
                    // Feature highlights
                    VStack(spacing: 16) {
                        featureHighlight("100% Local Storage")
                        featureHighlight("End-to-End Encryption")
                        featureHighlight("No Account Required")
                    }
                    .padding(.horizontal, 32)
                    
                    // Bottom spacer
                    Spacer(minLength: max(0, (geometry.size.height - 500) / 4))
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }
    
    // MARK: - Helper Views
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Icon container with subtle glow
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.top, 4)
            
            // Text content with flexible width
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func featureHighlight(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .symbolRenderingMode(.hierarchical)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WelcomeView()
                .preferredColorScheme(.light)
            
            WelcomeView()
                .preferredColorScheme(.dark)
        }
    }
}
