import SwiftUI

struct ShipBarNavigationIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ShipBarStyle.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ShipBarStyle.subtleStroke))
        .accessibilityLabel(self.accessibilityLabel)
        .help(self.accessibilityLabel)
    }
}
