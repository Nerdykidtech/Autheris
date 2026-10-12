import SwiftUI

/// A short, looping picture of folders at work, for the introduction sheet.
///
/// Drawn from sample codes, never the user's own, so it is the same for everyone and
/// shows no account. A code lifts off the list, lands on the Work chip, and the list
/// then filters to that folder. With Reduce Motion it shows the filtered list, still.
struct FoldersIntroDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    /// Where the Work chip's centre is, measured, so the carried code lands on it at
    /// any text size and in any language.
    @State private var workChipCentre = CGPoint(x: 116, y: 22)

    private struct Sample: Identifiable {
        let id: Int
        let label: LocalizedStringKey
        let tint: Color
        let code: String
    }

    private let samples = [
        Sample(id: 0, label: "Email", tint: .blue, code: "482 913"),
        Sample(id: 1, label: "Bank", tint: .green, code: "105 772"),
        Sample(id: 2, label: "Cloud", tint: .purple, code: "630 248"),
    ]

    /// The sample that is filed into Work.
    private let filedID = 2
    private let size = CGSize(width: 300, height: 196)
    private let rowHeight: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Laid out side by side, so a longer name pushes the next chip along
            // rather than over it.
            HStack(spacing: 8) {
                chip("All", systemImage: "square.grid.2x2", tint: nil, isSelected: step < 3)
                chip("Work", systemImage: "folder", tint: .orange, isSelected: step == 3,
                     isTarget: step == 1 || step == 2)
                    .onGeometryChange(for: CGPoint.self) { proxy in
                        let frame = proxy.frame(in: .named(Self.space))
                        return CGPoint(x: frame.midX, y: frame.midY)
                    } action: { centre in
                        workChipCentre = centre
                    }
            }
            .padding(.leading, 12)
            .padding(.top, 8)

            ForEach(samples) { sample in
                let isCarried = sample.id == filedID && (step == 1 || step == 2)
                row(sample)
                    .frame(width: size.width - 24, height: rowHeight)
                    .shadow(color: .black.opacity(isCarried ? 0.25 : 0), radius: 8, y: 4)
                    .scaleEffect(scale(for: sample))
                    .opacity(opacity(for: sample))
                    .offset(offset(for: sample))
                    // The carried code passes over the others on its way to the chip.
                    .zIndex(sample.id == filedID ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        // A fixed-size picture: past this size the samples would not fit its frame.
        // It is hidden from VoiceOver and the sheet's text carries the meaning.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .task {
            guard !reduceMotion else {
                step = 3
                return
            }
            while !Task.isCancelled {
                for next in 0...3 {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        step = next
                    }
                    try? await Task.sleep(for: .seconds(next == 3 ? 2.2 : 1.1))
                }
            }
        }
        // A picture of the feature; the sheet's text says what it shows.
        .accessibilityHidden(true)
    }

    // MARK: - Steps
    //
    // 0: the list as it is. 1: a code lifts towards Work. 2: it lands, and Work
    // rings. 3: Work is chosen, and the list shows only what is in it.

    private func offset(for sample: Sample) -> CGSize {
        let listTop: CGFloat = 52
        if step == 3 {
            // Filtered: the filed code takes the first place.
            return CGSize(width: 12, height: listTop)
        }
        let rest = CGSize(width: 12, height: listTop + CGFloat(sample.id) * (rowHeight + 8))
        guard sample.id == filedID, step >= 1 else { return rest }
        // Carried up so its centre sits on the Work chip's centre.
        return CGSize(width: workChipCentre.x - (size.width - 24) / 2,
                      height: workChipCentre.y - rowHeight / 2)
    }

    private func scale(for sample: Sample) -> CGFloat {
        guard sample.id == filedID, step == 1 || step == 2 else { return 1 }
        return step == 2 ? 0.1 : 0.4
    }

    private func opacity(for sample: Sample) -> Double {
        switch step {
        case 2 where sample.id == filedID: return 0
        case 3: return sample.id == filedID ? 1 : 0
        default: return 1
        }
    }

    // MARK: - Parts

    private nonisolated static let space = "foldersIntroDemo"

    private func chip(_ title: LocalizedStringKey, systemImage: String, tint: Color?,
                      isSelected: Bool, isTarget: Bool = false) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : (tint ?? Color.primary))
            .background(
                isSelected ? AnyShapeStyle(tint ?? Color.accentColor)
                           : AnyShapeStyle((tint ?? Color.secondary).opacity(0.18)),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(isTarget ? (tint ?? Color.accentColor) : Color.clear, lineWidth: 2)
            }
            .scaleEffect(isTarget ? 1.08 : 1)
    }

    private func row(_ sample: Sample) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(sample.tint.gradient)
                .frame(width: 24, height: 24)
            Text(sample.label)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(verbatim: sample.code)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        // Opaque, so a card carried over another does not show the one beneath.
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .background(.background, in: .rect(cornerRadius: 10))
    }
}
