import SwiftUI

struct ContentView: View {
    @State private var startAnimation = false
    @State private var hasStarted = false
    @State private var showGlow = false
    @State private var showLogoText = false
    @State private var showTagline = false
    @State private var showButton = false
    @State private var gradientOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            if hasStarted {
                HomeView()
                    .transition(.asymmetric(
                        insertion: AnyTransition.move(edge: .bottom),
                        removal: .opacity
                    ))
            } else {
                welcomeScreen
                    .transition(.opacity)
            }
        }
    }
    
    var welcomeScreen: some View {
        ZStack {
            // Animated Gradient Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.08, green: 0.08, blue: 0.15),
                    Color(red: 0.12, green: 0.12, blue: 0.2),
                    Color(red: 0.08, green: 0.08, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                // Subtle wave pattern overlay
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.accentColor.opacity(0.03), location: 0),
                        .init(color: Color.accentColor.opacity(0.08), location: 0.3),
                        .init(color: Color.accentColor.opacity(0.03), location: 0.7),
                        .init(color: Color.accentColor.opacity(0.01), location: 1)
                    ]),
                    startPoint: UnitPoint(x: 0.5 + gradientOffset, y: 0),
                    endPoint: UnitPoint(x: 0.5 + gradientOffset, y: 1)
                )
                .blur(radius: 20)
                .opacity(0.6)
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(Animation.linear(duration: 8).repeatForever(autoreverses: false)) {
                    gradientOffset = 0.5
                }
            }
            
            // Subtle grid pattern
            GridPattern()
                .fill(Color.accentColor.opacity(0.05))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 1)
                .scaleEffect(startAnimation ? 1 : 1.1)
                .animation(.easeOut(duration: 1.5), value: startAnimation)
            
            // Main Content
            VStack(spacing: 0) {
                Spacer()
                
                // Logo Container
                ZStack {
                    // Outer Glow Pulse
                    if showGlow {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.accentColor.opacity(0.2),
                                        Color.accentColor.opacity(0.05),
                                        Color.clear
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .blur(radius: 15)
                            .scaleEffect(pulseScale)
                            .animation(
                                Animation.easeInOut(duration: 2.5)
                                    .repeatForever(autoreverses: true),
                                value: pulseScale
                            )
                    }
                    
                    // Glassmorphic Container
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 130, height: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.3),
                                            Color.accentColor.opacity(0.2),
                                            Color.accentColor.opacity(0.1)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 10)
                        .shadow(color: Color.accentColor.opacity(0.1), radius: 20, x: 0, y: 5)
                    
                    // COMPLETELY STATIC Shield Icon - NO ANIMATIONS
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.accentColor],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .scaleEffect(startAnimation ? 1 : 0.5)
                .opacity(startAnimation ? 1 : 0)
                .animation(
                    .spring(response: 0.7, dampingFraction: 0.7, blendDuration: 0.5)
                    .delay(0.2),
                    value: startAnimation
                )
                
                // App Name with Gradient
                if showLogoText {
                    VStack(spacing: 4) {
                        Text("VAULTIC")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .kerning(3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, Color.accentColor.opacity(0.9)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.accentColor.opacity(0.2), radius: 8, x: 0, y: 4)
                        
                        // Accent line
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 120, height: 3)
                            .cornerRadius(1.5)
                            .scaleEffect(x: showLogoText ? 1 : 0, anchor: .center)
                            .animation(
                                .spring(response: 0.6, dampingFraction: 0.8)
                                .delay(0.8),
                                value: showLogoText
                            )
                    }
                    .padding(.top, 28)
                    .transition(
                        .asymmetric(
                            insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
                
                // Tagline
                if showTagline {
                    Text("Your Secure Authentication Hub")
                        .font(.system(size: 17, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.7))
                        .italic()
                        .padding(.top, 12)
                        .transition(
                            .asymmetric(
                                insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
                
                Spacer()
                
                // Get Started Button
                if showButton {
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            hasStarted = true
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text("Get Started")
                                .fontWeight(.semibold)
                                .font(.system(size: 17))
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                                .scaleEffect(0.9)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .padding(.horizontal, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 12, x: 0, y: 6)
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        .scaleEffect(isButtonPressed ? 0.96 : 1.0)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, 50)
                    .padding(.bottom, 50)
                    .transition(
                        .asymmetric(
                            insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
            }
        }
        .onAppear {
            // Start all animations (EXCEPT icon animation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    startAnimation = true
                    showGlow = true
                    pulseScale = 1.1
                }
                
                // Stagger text animations
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5)) {
                    showLogoText = true
                }
                
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.9)) {
                    showTagline = true
                }
                
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.3)) {
                    showButton = true
                }
            }
        }
    }
    
    // Button press state
    @State private var isButtonPressed = false
}

// Subtle Grid Pattern
struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gridSize: CGFloat = 40
        
        // Vertical lines
        for x in stride(from: 0, through: rect.width, by: gridSize) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        // Horizontal lines
        for y in stride(from: 0, through: rect.height, by: gridSize) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}

// Custom Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

#Preview {
    ContentView()
}
