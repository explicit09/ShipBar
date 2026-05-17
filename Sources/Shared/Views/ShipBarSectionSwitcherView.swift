import SwiftUI

struct ShipBarSectionSwitcherView: View {
    @Binding var selectedSection: ShipBarSection

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            ForEach(ShipBarSection.allCases) { section in
                Button {
                    self.selectedSection = section
                } label: {
                    self.sectionLabel(section, isSelected: section == self.selectedSection)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ShipBarStyle.separator)
                .frame(height: 1)
        }
    }

    private func sectionLabel(_ section: ShipBarSection, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: section.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 17)

            Text(section.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            ShipBarProgressBar(
                progress: isSelected ? 0.78 : 0.38,
                tint: isSelected ? Color.white : section.progressTint)
                .frame(width: 36, height: 4)
        }
        .foregroundStyle(isSelected ? Color.white : Color.secondary)
        .frame(width: 43, height: 54)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius, style: .continuous)
                    .fill(ShipBarStyle.accent)
                    .shadow(color: ShipBarStyle.glassShadow, radius: 7, x: 0, y: 4)
            }
        }
    }
}
