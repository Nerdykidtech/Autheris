import SwiftUI

private struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    /// `LocalizedStringKey` rather than `String`: these are literals at the call
    /// site, and a `String` property would carry them past the point where
    /// `Text` could look them up, leaving them English in every language.
    let title: LocalizedStringKey
    let description: LocalizedStringKey
}

struct WelcomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let totalPages = 3

    /// Typed explicitly: a ternary of two literals infers as `String`, which
    /// `Text` renders verbatim and never looks up.
    private var advanceTitle: LocalizedStringKey {
        currentPage < totalPages - 1 ? "Next" : "Get Started"
    }

    private let features: [OnboardingFeature] = [
        OnboardingFeature(
            icon: "qrcode.viewfinder",
            title: "Instant QR Import",
            description: "Add accounts in seconds by scanning the same QR code you'd use with Google Authenticator."
        ),
        OnboardingFeature(
            icon: "lock.shield.fill",
            title: "Stored in Your Keychain",
            description: "Tokens live in the device Keychain, protected by your passcode and Face ID / Touch ID."
        ),
        OnboardingFeature(
            icon: "timer",
            title: "Live Codes & Timers",
            description: "One-tap copy with a clear countdown, so you always know when the next code is ready."
        ),
        OnboardingFeature(
            icon: "magnifyingglass",
            title: "Search & Organize",
            description: "Find the right token instantly, with a clean list built for fast scanning."
        ),
        OnboardingFeature(
            icon: "lock.doc.fill",
            title: "Encrypted Backups",
            description: "Export password-encrypted backups you control, stored right on your device."
        ),
        OnboardingFeature(
            icon: "hand.raised.fill",
            title: "No Account Required",
            description: "No sign-up, no tracking, no ads. Just a focused 2FA manager that respects your privacy."
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                #if os(iOS)
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    getStartedPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                #else
                // macOS has no paging container — `.page` is iOS-only, and a
                // plain `TabView` there draws a tab bar, which is not what three
                // onboarding screens should look like. The Back and Next buttons
                // already drive `currentPage`, so the Mac simply shows the
                // selected page and cross-fades between them.
                Group {
                    switch currentPage {
                    case 0: welcomePage
                    case 1: featuresPage
                    default: getStartedPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25),
                    value: currentPage
                )
                #endif

                VStack(spacing: 20) {
                    pageDots
                    navigationButtons
                }
                .readableWidth(ReadableWidth.prose)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.25), radius: 16, x: 0, y: 8)

            Text("Autheris")
                .font(.system(size: 46, weight: .heavy, design: .rounded))

            Text("Secure 2FA token manager")
                .font(.title3.weight(.medium))
                .foregroundColor(.secondary)

            Text("Your accounts, protected on device.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.9))
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .readableWidth(ReadableWidth.prose)
        .padding(.horizontal, 32)
    }

    private var featuresPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Why Autheris")
                    .font(.largeTitle.weight(.bold))

                Text("Private, simple, and reliable two-factor authentication.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)

                ForEach(features) { feature in
                    FeatureRow(feature: feature)
                }
            }
            .readableWidth(ReadableWidth.prose)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 140, height: 140)

                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                    .frame(width: 140, height: 140)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }

            Text("Ready to Begin")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Start securing your accounts. Your codes stay on your device.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                highlight("100% local storage")
                highlight("Face ID / Touch ID lock")
                highlight("Encrypted backups")
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .readableWidth(ReadableWidth.prose)
    }

    // MARK: - Bottom controls

    private var pageDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                        value: currentPage
                    )
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentPage > 0 {
                Button {
                    Haptics.impact(.light)
                    currentPage -= 1
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                        Text("Back")
                            .font(.headline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                    .foregroundColor(.primary)
                }
            }

            Button {
                Haptics.impact(.medium)
                if currentPage < totalPages - 1 {
                    currentPage += 1
                } else {
                    Haptics.notify(.success)
                    hasCompletedOnboarding = true
                }
            } label: {
                HStack(spacing: 8) {
                    Text(advanceTitle)
                        .font(.headline)
                    if currentPage < totalPages - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .frame(maxWidth: currentPage > 0 ? .infinity : nil)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentPage)
    }

    private func highlight(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.accentColor)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct FeatureRow: View {
    let feature: OnboardingFeature

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)

                Text(feature.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
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
