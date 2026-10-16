import SwiftUI

struct SiteRow: View {
    let rank: Int
    let plan: SitePlan

    private var site: VotingSite { plan.site }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(rank)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(site.name)
                        .font(.headline)
                    Spacer(minLength: 8)
                    totalBadge
                }
                Text(site.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                legs
                statusLine
                    .font(.caption)
            }

            Button {
                Directions.open(site)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(site.coordinate == nil)
            .help("Open driving directions in Maps")
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .opacity(plan.isViable ? 1 : 0.55)
        .contextMenu {
            Button("Open in Maps") { Directions.open(site) }
        }
    }

    private var totalBadge: some View {
        let color = WaitColor.color(forTotal: plan.total)
        return Text(plan.total.map(Format.minutes) ?? (plan.waitMinutes == nil ? "no data" : "–"))
            .font(.callout.weight(.bold).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
            .fixedSize()
    }

    private var legs: some View {
        HStack(spacing: 10) {
            leg(icon: "car.fill", text: Format.minutes(plan.trip?.outbound), tint: .secondary)
            leg(icon: "person.3.fill", text: site.waitDisplay, tint: WaitColor.color(for: site.waitMinutes))
            leg(icon: "car.fill", text: plan.trip.map { Format.inbound($0) } ?? "–", tint: .secondary)
        }
        .font(.subheadline)
    }

    private func leg(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 4) {
            switch plan.status {
            case .open:
                if let hours = plan.hours {
                    Text("Open until \(Format.clock(hours.close))")
                }
            case .opensLater(let open):
                Text("Opens at \(Format.clock(open))")
            case .closesBeforeArrival:
                if let hours = plan.hours {
                    Text("Closes at \(Format.clock(hours.close)), before you'd arrive")
                        .foregroundStyle(.red)
                }
            case .closedForDay:
                Text("Closed for the day").foregroundStyle(.red)
            case .noVotingToday:
                Text("No early voting today").foregroundStyle(.red)
            case .noRoute:
                Text("Driving time unavailable").foregroundStyle(.orange)
            }
            if let updated = site.waitUpdatedAt {
                Text("·")
                Text("wait updated \(updated, format: .relative(presentation: .named))")
            }
        }
        .foregroundStyle(.secondary)
    }
}
