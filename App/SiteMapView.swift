import SwiftUI
import MapKit

struct SiteMapView: View {
    var model: PlannerModel
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: String?

    private var ranked: [(Int, SitePlan)] {
        Array(zip(1..., model.plans))
    }

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            ForEach(ranked, id: \.1.id) { rank, plan in
                if let coordinate = plan.site.coordinate {
                    Annotation(plan.site.name, coordinate: coordinate) {
                        marker(rank: rank, plan: plan)
                    }
                    .tag(plan.id)
                }
            }
            if let origin = model.origin {
                Annotation("Start", coordinate: origin) {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .padding(7)
                        .background(Circle().fill(.blue))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let selectedID, let index = model.plans.firstIndex(where: { $0.id == selectedID }) {
                // Same row as the list, so directions, site details and the chips behave identically.
                SiteRow(rank: index + 1, plan: model.plans[index])
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedID)
    }

    /// Marker color follows the ranking total (drive + wait + drive), like the list's capsules;
    /// falls back to the wait color before drive times are known.
    private func marker(rank: Int, plan: SitePlan) -> some View {
        let color = plan.total != nil ? WaitColor.color(forTotal: plan.total) : WaitColor.color(for: plan.site.waitMinutes)
        return Text("\(rank)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
            .opacity(plan.isViable ? 1 : 0.5)
    }
}
