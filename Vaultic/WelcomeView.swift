import SwiftUI

struct WelcomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                VStack(spacing: 32) {
                    Spacer()
                    
                    // App Icon/Logo
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(spacing: 12) {
                        Text("Welcome to Vaultic")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Your secure 2FA token manager")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: index == currentPage ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    
                    // Next button
                    Button(action: {
                        withAnimation {
                            currentPage = 1
                        }
                    }) {
                        Text("Get Started")
                            .font(.headline)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                }
                .tag(0)
                
                // Page 2: Features
                VStack(spacing: 32) {
                    Spacer()
                    
                    // Feature 1: QR Scanning
                    VStack(spacing: 16) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 50))
                            .foregroundColor(.accentColor)
                            .frame(width: 80, height: 80)
                            .background(
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                        
                        VStack(spacing: 8) {
                            Text("Quick QR Scanning")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Easily add tokens by scanning QR codes from your authentication apps")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                    }
                    
                    // Feature 2: Secure Storage
                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.accentColor)
                            .frame(width: 80, height: 80)
                            .background(
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                        
                        VStack(spacing: 8) {
                            Text("Secure & Local")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Your tokens are encrypted and stored only on your device")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                    }
                    
                    Spacer()
                    
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: index == currentPage ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    
                    // Navigation buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            withAnimation {
                                currentPage = 0
                            }
                        }) {
                            Text("Back")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule()
                                        .stroke(Color.accentColor, lineWidth: 2)
                                )
                                .foregroundColor(.accentColor)
                        }
                        
                        Button(action: {
                            withAnimation {
                                currentPage = 2
                            }
                        }) {
                            Text("Next")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor)
                                )
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                }
                .tag(1)
                
                // Page 3: Get Started
                VStack(spacing: 32) {
                    Spacer()
                    
                    // Final illustration
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 160, height: 160)
                        
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(spacing: 12) {
                        Text("Ready to Secure Your Accounts")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Start by adding your first authentication token")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: index == currentPage ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    
                    // Get Started button
                    Button(action: {
                        // Mark onboarding as complete
                        hasCompletedOnboarding = true
                    }) {
                        Text("Start Using Vaultic")
                            .font(.headline)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
    }
}
