import SwiftUI

/// A friendly, reusable empty state with an optional primary action.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Theme.gold)
                .padding(22)
                .background(Theme.surfaceRaised, in: Circle())

            VStack(spacing: 6) {
                Text(title)
                    .font(Theme.display(.title3))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, systemImage: "plus", action: action)
                    .frame(maxWidth: 220)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyStateView(
        icon: "briefcase",
        title: "No jobs yet",
        message: "Create your first job to start tracking work.",
        actionTitle: "Add Job",
        action: {}
    )
    .background(Theme.background)
}
