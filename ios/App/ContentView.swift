import SwiftUI

/// The whole app: one number, anchored bottom-left like a poster, over one rule with the unit and the GPS accuracy.
/// Tap anywhere to switch km/h and mph.
struct ContentView: View {
    @EnvironmentObject private var meter: Speedometer
    @AppStorage("mph") private var mph = false
    @Environment(\.colorScheme) private var scheme

    // Warm paper and near-black ink; dark mode swaps them.
    private var paper: Color { scheme == .dark ? Color(white: 0.067) : Color(red: 0.957, green: 0.949, blue: 0.933) }
    private var ink: Color { scheme == .dark ? Color(red: 0.957, green: 0.949, blue: 0.933) : Color(white: 0.067) }

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                // Drawn once at a large fixed size and scaled down to fit, never re-set at a new font size: a scale
                // animates, so the number grows and shrinks smoothly through a rotation (and from 2 to 3 digits).
                let scale = numberScale(in: geo.size)
                Text(number)
                    .font(.system(size: Self.baseSize, weight: .black).width(.compressed))
                    .monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(ink.opacity(hasSpeed ? 1 : 0.25))
                    .background(GeometryReader { Color.clear.preference(key: NaturalSize.self, value: $0.size) })
                    .scaleEffect(scale, anchor: .bottomLeading)
                    .frame(width: natural.width * scale, height: natural.height * scale, alignment: .bottomLeading)
                    .animation(.smooth(duration: 0.35), value: scale)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(number)
                    .accessibilityIdentifier("speed")
                Rectangle().fill(ink).frame(height: 2).padding(.top, 14)
                HStack {
                    Text(mph ? "MPH" : "KM/H").accessibilityIdentifier("unit")
                    Spacer()
                    Text(status).accessibilityIdentifier("status")
                }
                .font(.system(size: 12, weight: .bold).width(.expanded))
                .tracking(2)
                .foregroundStyle(ink)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(paper.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {
            if meter.reading == .denied {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            } else {
                mph.toggle()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(meter.reading == .denied ? "Tap to open Settings" : "Tap to switch between km/h and mph")
        .onPreferenceChange(NaturalSize.self) { natural = $0 }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// Larger than the number ever shows, so the scale only shrinks and the digits stay sharp.
    private static let baseSize: CGFloat = 700
    @State private var natural = CGSize(width: 1, height: 1)

    /// Sized by the screen height (62% for a speed, 20% for the dashes), then shrunk to the width: two digits fill it
    /// edge to edge, three step down.
    private func numberScale(in size: CGSize) -> CGFloat {
        let byHeight = size.height * (hasSpeed ? 0.62 : 0.2) / Self.baseSize
        let byWidth = (size.width - 40) / max(natural.width, 1)
        return max(min(byHeight, byWidth), 0.01)
    }

    private var hasSpeed: Bool {
        if case .speed = meter.reading { return true }
        return false
    }

    private var number: String {
        guard case .speed(let ms, _) = meter.reading else { return "– –" }
        return String(Int((ms * (mph ? 2.236936 : 3.6)).rounded()))
    }

    private var status: String {
        switch meter.reading {
        case .waiting: "FINDING GPS"
        case .denied: "LOCATION OFF · TAP"
        case .speed(_, let accuracy): "GPS ±\(Int(accuracy.rounded())) M"
        }
    }
}

/// The number's size at `ContentView.baseSize`, before scaling.
private struct NaturalSize: PreferenceKey {
    static var defaultValue = CGSize(width: 1, height: 1)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
