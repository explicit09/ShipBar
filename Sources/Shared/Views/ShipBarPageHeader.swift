import SwiftUI

struct ShipBarPageHeader<Action: View>: View {
    let eyebrow: String?
    let title: String
    let purpose: String
    let action: () -> Action

    init(
        eyebrow: String? = nil,
        title: String,
        purpose: String,
        @ViewBuilder action: @escaping () -> Action)
    {
        self.eyebrow = eyebrow
        self.title = title
        self.purpose = purpose
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(ShipBarStyle.shipBlue)
                }
                Text(self.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                Text(self.purpose)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            self.action()
        }
    }
}

extension ShipBarPageHeader where Action == EmptyView {
    init(eyebrow: String? = nil, title: String, purpose: String) {
        self.init(eyebrow: eyebrow, title: title, purpose: purpose) { EmptyView() }
    }
}
