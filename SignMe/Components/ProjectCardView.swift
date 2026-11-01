import SwiftUI

/// The card used to represent a Project inside a Job's project list.
struct ProjectCardView: View {
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("\(project.entries.count) entr\(project.entries.count == 1 ? "y" : "ies") · \(DateDurationService.formattedDuration(hours: project.totalHours))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let last = project.lastEntryDate {
                    Text("Last entry \(DateDurationService.dateFormatter.string(from: last))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }
}

#Preview {
    ProjectCardView(project: PreviewSupport.sampleProject)
        .padding()
        .modelContainer(PreviewSupport.container)
}
