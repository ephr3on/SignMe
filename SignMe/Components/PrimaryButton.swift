import SwiftUI

/// The single consistent "primary action" button used across the app (gold, navy text).
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(GoldButtonStyle(height: 50))
        .disabled(isDisabled)
    }
}

#Preview {
    VStack(spacing: 12) {
        PrimaryButton(title: "Add Job", systemImage: "plus") {}
        PrimaryButton(title: "Save", isDisabled: true) {}
    }
    .padding()
    .background(Theme.background)
}
