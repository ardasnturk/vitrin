import SwiftUI

/// The Remote Code family look (Remote Code D-104, as Promo Studio carries it): glass cards on blurred colour blobs,
/// gradient icon badges, a gradient header and primary button. Vitrin owns the warm end: amber → coral → pink.
enum Brand {
    static let teal = Color(red: 0.05, green: 0.66, blue: 0.68)
    static let indigo = Color(red: 0.30, green: 0.36, blue: 0.93)
    static let violet = Color(red: 0.62, green: 0.32, blue: 0.92)
    static let pink = Color(red: 0.93, green: 0.36, blue: 0.62)
    static let mint = Color(red: 0.48, green: 0.91, blue: 0.77)
    static let amber = Color(red: 1.00, green: 0.62, blue: 0.20)
    static let coral = Color(red: 0.98, green: 0.42, blue: 0.38)

    /// Headers and featured cards
    static let gradient = LinearGradient(colors: [amber, coral, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Primary action buttons
    static let buttonGradient = LinearGradient(colors: [coral, pink], startPoint: .leading, endPoint: .trailing)
}

/// Soft, blurred color blobs behind the window content.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var intensity: Double = 1

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    blob(Brand.amber, diameter: size.width * 0.9)
                        .offset(x: -size.width * 0.35, y: -size.height * 0.35)
                    blob(Brand.coral, diameter: size.width * 0.8)
                        .offset(x: size.width * 0.4, y: -size.height * 0.1)
                    blob(Brand.pink, diameter: size.width * 0.9)
                        .offset(x: -size.width * 0.1, y: size.height * 0.45)
                }
                .frame(width: size.width, height: size.height)
            }
            .blur(radius: 60)
            .opacity((colorScheme == .dark ? 0.4 : 0.22) * intensity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        Circle().fill(color).frame(width: diameter, height: diameter)
    }
}

extension View {
    /// Translucent rounded card that lets the brand background show through.
    func glassCard(cornerRadius: CGFloat = 14, padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    /// Window content: brand background, with list/form backgrounds hidden.
    func brandWindowBackground(intensity: Double = 0.45) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(BrandBackground(intensity: intensity))
    }
}

/// White SF Symbol on a gradient rounded square (sidebar, headers).
struct IconBadge: View {
    let symbol: String
    var colors: [Color] = [Brand.coral, Brand.pink]
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Large primary action button: gradient, white text.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Brand.buttonGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Small colored status pill, e.g. "Ready".
struct StatusPill: View {
    let text: Text
    let color: Color
    /// White fill on a gradient header; colored on a regular background
    var onGradient = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            text
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(onGradient ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(color.opacity(0.16)), in: Capsule())
        .foregroundStyle(onGradient ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

/// Thin gradient progress bar.
struct ProgressBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let fraction {
                    Capsule()
                        .fill(Brand.buttonGradient)
                        .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                } else {
                    // Indeterminate job: a short moving segment
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        Capsule()
                            .fill(Brand.buttonGradient)
                            .frame(width: proxy.size.width * 0.3)
                            .offset(x: (proxy.size.width * 1.3) * t - proxy.size.width * 0.3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Full track width: without it the clip is only as wide as the segment
                    .frame(width: proxy.size.width, alignment: .leading)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Small uppercase section title inside a card.
struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// Large icon, title and one-line description at the top of a pane.
struct PaneHeader: View {
    let symbol: String
    let colors: [Color]
    let title: Text
    let subtitle: Text

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, colors: colors, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                title.font(.title2.weight(.bold))
                // Two lines at most, never a vertical fixedSize: measured at zero width that grew a letter per
                // line and pushed the whole window up (the Team pages).
                subtitle
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

/// Badge colours per area, so a page, its sidebar row and its settings pane match.
enum BadgeColors {
    static let warm = [Brand.amber, Brand.coral]
    static let brand = [Brand.coral, Brand.pink]
    static let cool = [Brand.teal, Brand.indigo]
    static let deep = [Brand.indigo, Brand.violet]
    static let magic = [Brand.violet, Brand.pink]
    static let fresh = [Color.green, Brand.teal]
    static let alert = [Color.orange, Color.red]
    static let gray = [Color.gray, Color.gray.opacity(0.65)]
}
