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
                Text(number)
                    // Sized by the height, then shrunk to the width: two digits fill it edge to edge, three step down.
                    .font(.system(size: geo.size.height * 0.62, weight: .black).width(.compressed))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.1)
                    .foregroundStyle(ink.opacity(hasSpeed ? 1 : 0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("speed")
                    .accessibilityLabel(number)
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
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(meter.reading == .denied ? "Opens Settings" : "Switches between km/h and mph")
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
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
