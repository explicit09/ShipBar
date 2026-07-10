import SwiftUI

enum ShipBarStyle {
    static let panelWidth: CGFloat = 340
    static let panelHeight: CGFloat = 560
    static let contentPadding: CGFloat = 16
    static let controlRadius: CGFloat = 6
    static let progressHeight: CGFloat = 5
    static let promptGreen = Color(red: 0.18, green: 0.66, blue: 0.55)
    static let shipBlue = Color(red: 0.35, green: 0.55, blue: 1.0)
    static let successGreen = Color(red: 0.28, green: 0.78, blue: 0.55)
    static let reviewAmber = Color(red: 0.96, green: 0.64, blue: 0.25)
    static let runPurple = Color(red: 0.58, green: 0.43, blue: 0.92)
    static var canvas: Color { Color.primary.opacity(0.012) }
    static var chromeSurface: Color { Color.primary.opacity(0.052) }
    static var dockSurface: Color { Color.primary.opacity(0.064) }
    static var selectionSurface: Color { Self.shipBlue.opacity(0.13) }
    static var badgeSurface: Color { Self.reviewAmber }
    static let pageRadius: CGFloat = 13
    static let rowRadius: CGFloat = 10

    static var accent: Color {
        #if os(macOS)
        Color(nsColor: .controlAccentColor)
        #else
        Color.accentColor
        #endif
    }

    static var separator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(.separator)
        #endif
    }

    static var subtleFill: Color {
        Color.primary.opacity(0.045)
    }

    static var raisedSurface: Color {
        Color.primary.opacity(0.038)
    }

    static var flightPlanSurface: Color {
        Self.shipBlue.opacity(0.045)
    }

    static var subtleStroke: Color {
        Color.primary.opacity(0.10)
    }

    static var glassShadow: Color {
        Color.black.opacity(0.07)
    }

    static var progressTrack: Color {
        Color.primary.opacity(0.12)
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: Color(red: 0.84, green: 0.37, blue: 0.24)
        case .medium: Color.secondary.opacity(0.75)
        case .low: Color(red: 0.22, green: 0.47, blue: 0.82)
        }
    }
}

struct ShipBarPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(width: ShipBarStyle.panelWidth, height: ShipBarStyle.panelHeight)
            .background(Color.clear)
        #else
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground).ignoresSafeArea())
        #endif
    }
}

struct ShipBarGlassSurface: ViewModifier {
    let radius: CGFloat
    let selected: Bool
    let shadow: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: self.radius, style: .continuous)
                    .fill(self.fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: self.radius, style: .continuous)
                    .stroke(self.stroke, lineWidth: self.selected ? 0 : (self.contrast == .increased ? 2 : 1))
            }
            .shadow(
                color: self.shadow ? ShipBarStyle.glassShadow : .clear,
                radius: self.selected ? 7 : 3,
                x: 0,
                y: self.selected ? 4 : 1)
    }

    private var fill: Color {
        if self.selected {
            return ShipBarStyle.accent
        }
        return Color.clear
    }

    private var stroke: Color {
        self.selected ? Color.clear : Color.primary.opacity(self.contrast == .increased ? 0.34 : 0.10)
    }
}

extension View {
    func shipBarGlass(
        radius: CGFloat = ShipBarStyle.controlRadius,
        selected: Bool = false,
        shadow: Bool = false) -> some View
    {
        self.modifier(ShipBarGlassSurface(radius: radius, selected: selected, shadow: shadow))
    }
}

struct ShipBarProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(self.progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ShipBarStyle.progressTrack)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                self.tint.opacity(0.88),
                                self.tint,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing))
                    .frame(width: max(0, proxy.size.width * clamped))
            }
        }
        .frame(height: ShipBarStyle.progressHeight)
    }
}
