import SwiftUI

struct ShipBarCommandStrip: View {
    let openSearch: () -> Void
    let openCapture: () -> Void

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
            .buttonStyle(ShipBarCommandStripButtonStyle())
            .focusable()
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityLabel("Search ShipBar, Command K")
            .accessibilityHint("Opens command search")

            Button(action: self.openCapture) {
                Image(systemName: "plus")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(ShipBarCommandStripButtonStyle())
            .focusable()
            .accessibilityLabel("Global capture")
            .accessibilityHint("Opens quick capture")
        }
    }
}

private struct ShipBarCommandStripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? ShipBarStyle.shipBlue : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                configuration.isPressed
                    ? ShipBarStyle.selectionSurface
                    : ShipBarStyle.chromeSurface,
                in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius, style: .continuous))
            .shipBarOutline(
                radius: ShipBarStyle.controlRadius,
                color: configuration.isPressed ? ShipBarStyle.shipBlue.opacity(0.32) : ShipBarStyle.subtleStroke,
                increasedColor: configuration.isPressed ? ShipBarStyle.shipBlue.opacity(0.72) : ShipBarStyle.increasedContrastStroke)
    }
}
