import SwiftUI

/// The card used to represent a Job in the Jobs list.
struct JobCardView: View {
    let job: Job

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "briefcase.fill")
                .font(.title3)
                .foregroundStyle(Theme.background)
                .frame(width: 44, height: 44)
                .background(Theme.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(Theme.display(.headline))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(job.projects.count) project\(job.projects.count == 1 ? "" : "s") · \(DateDurationService.formattedDuration(hours: job.totalHours))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                if let last = job.lastActivityDate {
                    Text("Last activity \(DateDurationService.relativeFormatter.localizedString(for: last, relativeTo: .now))")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .card(padding: 16, radius: 20)
    }
}

#Preview {
    JobCardView(job: PreviewSupport.sampleJob)
        .padding()
        .background(Theme.background)
        .modelContainer(PreviewSupport.container)
}
