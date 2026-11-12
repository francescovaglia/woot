import SwiftUI

/// A round avatar with initials as the fallback, an optional flag badge and presence dot.
struct AvatarView: View {
    let name: String
    let url: URL?
    var size: CGFloat = 52
    var countryCode: String?
    var isOnline = false

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            initials
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(alignment: .bottomTrailing) {
            if let flag = countryCode.flatMap(Self.flag) {
                Text(flag)
                    .font(.system(size: size * 0.3))
                    .background(.background, in: .circle.inset(by: -2))
                    .offset(x: 2, y: 2)
            }
        }
        .overlay(alignment: .topLeading) {
            if isOnline {
                Circle()
                    .fill(.green)
                    .frame(width: size * 0.22, height: size * 0.22)
                    .overlay { Circle().stroke(.background, lineWidth: 2) }
            }
        }
        .accessibilityHidden(true)
    }

    private var initials: some View {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return Circle()
            .fill(Self.tint(for: name).gradient)
            .overlay {
                Text(letters.isEmpty ? "?" : letters.uppercased())
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    /// A stable color per name, so the same visitor always looks the same.
    private static func tint(for name: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .mint, .cyan]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    /// Turns `GB` into 🇬🇧 using regional indicator symbols.
    static func flag(for countryCode: String) -> String? {
        guard countryCode.count == 2 else { return nil }
        let scalars = countryCode.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : nil
    }
}

#Preview {
    HStack {
        AvatarView(name: "Maya Patel", url: nil, countryCode: "GB", isOnline: true)
        AvatarView(name: "withered-darkness-514", url: nil, countryCode: "IT")
    }
}
