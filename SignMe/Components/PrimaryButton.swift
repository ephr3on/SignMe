import SwiftUI

/// The single consistent "primary action" button style used across the app.
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
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(isDisabled)
    }
}

#Preview {
    VStack(spacing: 12) {
        PrimaryButton(title: "Add Job", systemImage: "plus") {}
        PrimaryButton(title: "Save", isDisabled: true) {}
    }
    .padding()
}
