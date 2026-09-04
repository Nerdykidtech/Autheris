import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    
    private var appMarketingVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    
    private var appBuildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Blur when backgrounded", isOn: $enablePrivacyBlur)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Toggle("Hide codes in app switcher", isOn: $hideCodesInAppSwitcher)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                } header: {
                    Text("Privacy")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• **Blur when backgrounded**: Automatically blurs the app when you switch to another app or go to the home screen.")
                        Text("• **Hide codes in app switcher**: Shows a privacy screen instead of your OTP codes when using the app switcher.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appMarketingVersion)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(appBuildNumber)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("Made By")
                        Spacer()
                        Text("Hunter Eddington")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://eddington.tech/autheris")!) {
                        HStack {
                            Text("Website")
                            Spacer()
                            Text("eddington.tech/autheris")
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
