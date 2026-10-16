import SwiftUI

struct SiteRow: View {
    let rank: Int
    let plan: SitePlan

    private var site: VotingSite { plan.site }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(site.name)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)   // wrap, don't ellipsize
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    totalBadge
                }
                Text(site.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                legs
                statusLine
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if os(macOS)
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
            #endif
        }
        .padding(.vertical, 4)
        .opacity(plan.isViable ? 1 : 0.55)
        .contextMenu {
            Button("Open in Maps") { Directions.open(site) }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Directions.open(site)
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .tint(.blue)
            .disabled(site.coordinate == nil)
        }
        #endif
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

    /// The three chips fit on one line on wide screens and stack on narrow phones.
    private var legs: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { legChips }
            VStack(alignment: .leading, spacing: 3) { legChips }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var legChips: some View {
        leg(icon: "car.fill", text: Format.minutes(plan.trip?.outbound), tint: .secondary)
        leg(icon: "person.3.fill", text: site.waitDisplay, tint: WaitColor.color(for: site.waitMinutes))
        leg(icon: "car.fill", text: plan.trip.map { Format.inbound($0) } ?? "–", tint: .secondary)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                statusText
                if let updated = site.waitUpdatedAt {
                    Text("·")
                    updatedText(updated)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                statusText
                if let updated = site.waitUpdatedAt {
                    updatedText(updated)
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var statusText: some View {
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
    }

    private func updatedText(_ updated: Date) -> some View {
        Text("wait updated \(updated, format: .relative(presentation: .named))")
    }
}
