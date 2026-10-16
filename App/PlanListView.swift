import SwiftUI

struct PlanListView: View {
    var model: PlannerModel

    #if os(iOS)
    private static let retryHint = "Pull down to try again."
    #else
    private static let retryHint = "Press Refresh (⌘R) to try again."
    #endif

    var body: some View {
        if model.plans.isEmpty {
            if model.isRefreshing {
                ProgressView("Loading wait times…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No sites loaded",
                                       systemImage: "wifi.exclamationmark",
                                       description: Text(model.errorMessage ?? Self.retryHint))
            }
        } else {
            List {
                if !model.hasOrigin {
                    Label("Enter a starting address or tap the location button to get drive times.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.plans.enumerated()), id: \.element.id) { index, plan in
                    SiteRow(rank: index + 1, plan: plan)
                }
            }
            .listStyle(.inset)
            .refreshable { await model.refresh() }
        }
    }
}
