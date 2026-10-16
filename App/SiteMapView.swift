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
            if let selectedID, let plan = model.plans.first(where: { $0.id == selectedID }) {
                SelectedSiteCard(rank: (model.plans.firstIndex { $0.id == selectedID } ?? 0) + 1, plan: plan) {
                    self.selectedID = nil
                }
                .padding()
            }
        }
    }

    private func marker(rank: Int, plan: SitePlan) -> some View {
        let color = WaitColor.color(for: plan.site.waitMinutes)
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

private struct SelectedSiteCard: View {
    let rank: Int
    let plan: SitePlan
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(rank)  \(plan.site.name)")
                    .font(.headline)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 12) {
                Label(Format.minutes(plan.trip?.outbound), systemImage: "car.fill")
                Label(plan.site.waitDisplay, systemImage: "person.3.fill")
                    .foregroundStyle(WaitColor.color(for: plan.site.waitMinutes))
                Label(plan.trip.map { Format.inbound($0) } ?? "–", systemImage: "car.fill")
                Spacer()
                Text(plan.total.map(Format.minutes) ?? "–")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(WaitColor.color(forTotal: plan.total))
            }
            .font(.subheadline)
            Button {
                Directions.open(plan.site)
            } label: {
                Label("Directions in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }
}
