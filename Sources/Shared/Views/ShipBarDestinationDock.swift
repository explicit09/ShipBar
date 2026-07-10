import SwiftUI

struct ShipBarDestinationDock: View {
    @Binding var selection: ShipBarDestination
    let count: (ShipBarDestination) -> Int?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(ShipBarDestination.allCases) { destination in
                    Button { self.selection = destination } label: {
                        VStack(spacing: 3) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: destination.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                if let count = self.count(destination), count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 14, minHeight: 14)
                                        .background(ShipBarStyle.badgeSurface, in: Capsule())
                                        .offset(x: 10, y: -6)
                                }
                            }
                            Text(destination.label)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(self.selection == destination ? ShipBarStyle.shipBlue : .secondary)
                        .background(
                            self.selection == destination ? ShipBarStyle.selectionSurface : .clear,
                            in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusable()
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(destination.shortcutNumber)")),
                        modifiers: .command)
                    .accessibilityLabel("\(destination.label), \(self.count(destination) ?? 0) actionable")
                    .accessibilityHint("Switches to \(destination.label)")
                }
            }
            .padding(6)
            .background(
                ShipBarStyle.dockSurface,
                in: RoundedRectangle(cornerRadius: ShipBarStyle.pageRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ShipBarStyle.pageRadius, style: .continuous)
                    .stroke(
                        Color.primary.opacity(self.contrast == .increased ? 0.34 : 0.10),
                        lineWidth: self.contrast == .increased ? 2 : 1)
            }
            .frame(width: min(proxy.size.width, 520))
            .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
    }
}
