import SwiftUI

struct ShipBarCommandStrip: View {
    let openSearch: () -> Void
    let openCapture: () -> Void
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case search
        case capture
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: self.openSearch) {
                HStack(spacing: 7) {
                    Image(systemName: "command")
                    Text(ShipBarDestination.searchPrompt)
                    Spacer()
                    Text("K").font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ShipBarCommandStripButtonStyle(focused: self.focusedControl == .search))
            .focusable()
            .focused(self.$focusedControl, equals: .search)
            .focusEffectDisabled()
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityLabel("Search ShipBar, Command K")
            .accessibilityHint("Opens command search")

            Button(action: self.openCapture) {
                Image(systemName: "plus")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(ShipBarCommandStripButtonStyle(focused: self.focusedControl == .capture))
            .focusable()
            .focused(self.$focusedControl, equals: .capture)
            .focusEffectDisabled()
            .accessibilityLabel("Global capture")
            .accessibilityHint("Opens quick capture")
        }
    }
}

private struct ShipBarCommandStripButtonStyle: ButtonStyle {
    let focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(configuration.isPressed || self.focused ? ShipBarStyle.selectionForeground : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                configuration.isPressed || self.focused
                    ? ShipBarStyle.selectionSurface
                    : ShipBarStyle.chromeSurface,
                in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius, style: .continuous))
            .shipBarOutline(
                radius: ShipBarStyle.controlRadius,
                color: configuration.isPressed || self.focused ? .clear : ShipBarStyle.subtleStroke,
                increasedColor: configuration.isPressed || self.focused ? .clear : ShipBarStyle.increasedContrastStroke)
    }
}
