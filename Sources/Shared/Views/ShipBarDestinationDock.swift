import SwiftUI

struct ShipBarDestinationDock: View {
    @Binding var selection: ShipBarDestination
    let count: (ShipBarDestination) -> Int?
    @FocusState private var focusedDestination: ShipBarDestination?

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(ShipBarDestination.allCases) { destination in
                    let actionableCount = self.count(destination)
                    Button { self.selection = destination } label: {
                        VStack(spacing: 3) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: destination.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                if let actionableCount, actionableCount > 0 {
                                    Text("\(actionableCount)")
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
                        .foregroundStyle(self.selection == destination ? ShipBarStyle.selectionForeground : .secondary)
                        .background(
                            self.selection == destination ? ShipBarStyle.selectionSurface : .clear,
                            in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusable()
                    .focused(self.$focusedDestination, equals: destination)
                    .focusEffectDisabled()
                    .shipBarOutline(
                        radius: ShipBarStyle.controlRadius,
                        color: self.focusedDestination == destination ? ShipBarStyle.focusStroke : .clear,
                        increasedColor: self.focusedDestination == destination ? ShipBarStyle.focusStroke : .clear)
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(destination.shortcutNumber)")),
                        modifiers: .command)
                    .accessibilityLabel(self.accessibilityLabel(for: destination, actionableCount: actionableCount))
                    .accessibilityHint("Switches to \(destination.label)")
                    .accessibilityRemoveTraits(.isSelected)
                    .accessibilityAddTraits(self.selection == destination ? .isSelected : [])
                }
            }
            .padding(6)
            .background(
                ShipBarStyle.dockSurface,
                in: RoundedRectangle(cornerRadius: ShipBarStyle.pageRadius, style: .continuous))
            .shipBarOutline(radius: ShipBarStyle.pageRadius)
            .frame(width: min(proxy.size.width, 520))
            .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
    }

    private func accessibilityLabel(
        for destination: ShipBarDestination,
        actionableCount: Int?) -> String
    {
        guard let actionableCount else { return destination.label }
        return "\(destination.label), \(actionableCount) actionable"
    }
}
