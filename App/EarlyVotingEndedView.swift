import SwiftUI

/// Shown instead of the planner once the early-voting period is over, so the app never
/// presents stale wait times as if they meant something.
struct EarlyVotingEndedView: View {
    let endedOn: Date

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Early voting ended on \(endedOn.formatted(.dateTime.month(.wide).day().year())).")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("You can still vote on Election Day at your assigned precinct.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("Wake County Board of Elections",
                 destination: URL(string: "https://www.wake.gov/departments-government/board-elections")!)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 320)
        #endif
    }
}
