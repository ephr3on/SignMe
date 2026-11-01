import SwiftUI

/// The card used to represent a Project inside a Job's project list.
struct ProjectCardView: View {
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.app(.title3))
                .foregroundStyle(Theme.gold)
                .frame(width: 44, height: 44)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.app(.headline))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(project.entries.count) entr\(project.entries.count == 1 ? "y" : "ies") · \(DateDurationService.formattedDuration(hours: project.totalHours))")
                    .font(.app(.caption))
                    .foregroundStyle(Theme.textSecondary)

                if let last = project.lastEntryDate {
                    Text("Last entry \(DateDurationService.dateFormatter.string(from: last))")
                        .font(.app(.caption2))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.app(.caption, .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .card(padding: 16, radius: 20)
    }
}

#Preview {
    ProjectCardView(project: PreviewSupport.sampleProject)
        .padding()
        .background(Theme.background)
        .modelContainer(PreviewSupport.container)
}
